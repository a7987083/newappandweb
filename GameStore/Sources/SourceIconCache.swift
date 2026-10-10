import Foundation
import UIKit
import SystemConfiguration

/// URL-keyed two-layer cache. Visible requests never wait behind bulk prefetch work.
final class SourceIconCache {
    static let shared = SourceIconCache()
    private let memory = NSCache<NSString, UIImage>()
    private let diskQueue = DispatchQueue(label: "gamestore.icons.disk", qos: .userInitiated, attributes: .concurrent)
    private let state = DispatchQueue(label: "gamestore.icons.state")
    private let session: URLSession
    private let directory: URL
    private var callbacks: [String: [(UIImage?) -> Void]] = [:]
    private var foreground: [URL] = []
    private var background: [URL] = []
    private var active = Set<String>()
    private var diskChecking = Set<String>()
    private var maxDownloads = 12
    private var prefetchGeneration = 0
    private var knownURLs: [URL] = []
    private var retries: [String: Int] = [:]
    private var retryAfter: [String: Date] = [:]
    private var retryWorkScheduled = false
    private let diskLimit: Int64 = 300 * 1024 * 1024
    private var networkReachability: SCNetworkReachability?

    private init() {
        memory.countLimit = 300
        memory.totalCostLimit = 48 * 1024 * 1024
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("GameStore/Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        if let reachability = SCNetworkReachabilityCreateWithName(nil, "apple.com") {
            networkReachability = reachability
            let callback: SCNetworkReachabilityCallBack = { _, flags, info in
                guard let info = info else { return }
                let cache = Unmanaged<SourceIconCache>.fromOpaque(info).takeUnretainedValue()
                let reachable = flags.contains(.reachable) && !flags.contains(.connectionRequired)
                if reachable { cache.retryWhenOnline() }
            }
            var context = SCNetworkReachabilityContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
            if SCNetworkReachabilitySetCallback(reachability, callback, &context) {
                SCNetworkReachabilitySetDispatchQueue(reachability, state)
            }
        }
    }

    private func retryWhenOnline() {
        state.async {
            self.retryAfter.removeAll()
            self.retries.removeAll()
            self.enqueueMissing(self.knownURLs)
        }
    }

    private func path(for url: URL) -> URL {
        // Preserve V2 filenames so previously saved icons remain usable.
        var hash: UInt64 = 14695981039346656037
        for byte in url.absoluteString.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return directory.appendingPathComponent(String(format: "%016llx", hash) + ".img")
    }

    func cachedMemoryImage(for url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        if let image = cachedMemoryImage(for: url) {
            DispatchQueue.main.async { completion(image) }
            return
        }
        state.async {
            let key = url.absoluteString
            if self.callbacks[key] != nil {
                self.callbacks[key]?.append(completion)
                self.background.removeAll { $0.absoluteString == key }
                if !self.active.contains(key) && !self.diskChecking.contains(key) &&
                    !self.foreground.contains(where: { $0.absoluteString == key }) {
                    self.foreground.insert(url, at: 0)
                }
            } else {
                self.callbacks[key] = [completion]
                self.foreground.insert(url, at: 0)
                self.checkDisk(url)
            }
            self.schedule()
        }
    }

    private func checkDisk(_ url: URL) {
        let key = url.absoluteString
        guard diskChecking.insert(key).inserted else { return }
        diskQueue.async {
            let image = (try? Data(contentsOf: self.path(for: url))).flatMap(UIImage.init(data:))
            self.state.async {
                self.diskChecking.remove(key)
                if let image = image {
                    self.foreground.removeAll { $0.absoluteString == key }
                    self.background.removeAll { $0.absoluteString == key }
                    self.complete(url, image: image)
                } else {
                    self.schedule()
                }
            }
        }
    }

    private func complete(_ url: URL, image: UIImage?) {
        let key = url.absoluteString
        if let image = image {
            memory.setObject(image, forKey: key as NSString,
                             cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        }
        let handlers = callbacks.removeValue(forKey: key) ?? []
        DispatchQueue.main.async { handlers.forEach { $0(image) } }
    }

    private func schedule() {
        while active.count < maxDownloads {
            let frontIndex = foreground.firstIndex { !diskChecking.contains($0.absoluteString) && !active.contains($0.absoluteString) }
            let url: URL
            if let index = frontIndex {
                url = foreground.remove(at: index)
            } else if !background.isEmpty {
                // Keep two network slots available for visible icons.
                if active.count >= maxDownloads - 4 { break }
                url = background.removeFirst()
            } else {
                break
            }
            let key = url.absoluteString
            if active.contains(key) || diskChecking.contains(key) { continue }
            active.insert(key)
            session.dataTask(with: url) { data, response, error in
                let valid: Data?
                if error == nil, let http = response as? HTTPURLResponse,
                   (200...299).contains(http.statusCode),
                   let bytes = data, bytes.count <= 5 * 1024 * 1024,
                   UIImage(data: bytes) != nil {
                    valid = bytes
                } else {
                    valid = nil
                }
                self.diskQueue.async {
                    if let valid = valid {
                        try? valid.write(to: self.path(for: url), options: .atomic)
                    }
                    let image = valid.flatMap(UIImage.init(data:))
                    self.state.async {
                        self.active.remove(key)
                        if image == nil {
                            let count = min((self.retries[key] ?? 0) + 1, 6)
                            self.retries[key] = count
                            if count < 6 {
                                self.retryAfter[key] = Date().addingTimeInterval(min(300, pow(2.0, Double(count)) * 2.0))
                            } else {
                                // Stop retrying until the next refresh or connectivity recovery.
                                self.retryAfter.removeValue(forKey: key)
                            }
                        } else {
                            self.retries.removeValue(forKey: key)
                            self.retryAfter.removeValue(forKey: key)
                        }
                        self.complete(url, image: image)
                        self.schedule()
                        if image == nil { self.scheduleRetry() }
                    }
                }
            }.resume()
        }
    }

    private func scheduleRetry() {
        guard !retryWorkScheduled, !retryAfter.isEmpty else { return }
        retryWorkScheduled = true
        let delay = max(1, retryAfter.values.map { $0.timeIntervalSinceNow }.min() ?? 5)
        state.asyncAfter(deadline: .now() + delay) {
            self.retryWorkScheduled = false
            self.enqueueMissing(self.knownURLs)
            if !self.retryAfter.isEmpty { self.scheduleRetry() }
        }
    }

    private func enqueueMissing(_ urls: [URL]) {
        prefetchGeneration += 1
        let generation = prefetchGeneration
        background.removeAll()
        diskQueue.async {
            var seen = Set<String>()
            let missing = urls.filter {
                seen.insert($0.absoluteString).inserted &&
                !FileManager.default.fileExists(atPath: self.path(for: $0).path)
            }
            self.state.async {
                guard generation == self.prefetchGeneration else { return }
                for url in missing {
                    let key = url.absoluteString
                    guard (self.retryAfter[key] ?? .distantPast) <= Date(),
                          (self.retries[key] ?? 0) < 6 else { continue }
                    if self.memory.object(forKey: key as NSString) == nil &&
                       !self.active.contains(key) && !self.diskChecking.contains(key) &&
                       !self.foreground.contains(where: { $0.absoluteString == key }) {
                        self.background.append(url)
                    }
                }
                self.schedule()
                self.scheduleRetry()
            }
        }
    }

    func prefetch(_ urls: [URL]) {
        state.async {
            self.retries.removeAll()
            self.retryAfter.removeAll()
            self.knownURLs = Array(Dictionary(grouping: urls, by: { $0.absoluteString }).values.compactMap { $0.first })
            self.enqueueMissing(self.knownURLs)
            self.cleanDisk(protecting: Set(self.knownURLs.map { self.path(for: $0).lastPathComponent }))
        }
    }

    private func cleanDisk(protecting protected: Set<String>) {
        diskQueue.async {
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(at: self.directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
            var entries: [(URL, Int64, Date)] = []
            var total: Int64 = 0
            for file in files {
                guard let metadata = try? file.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]),
                      let size = metadata.fileSize else { continue }
                let bytes = Int64(size)
                total += bytes
                entries.append((file, bytes, metadata.contentAccessDate ?? metadata.contentModificationDate ?? .distantPast))
            }
            guard total > self.diskLimit else { return }
            let sorted = entries.sorted(by: { $0.2 < $1.2 })
            // First evict orphaned icons, preserving the current source catalog.
            for entry in sorted where !protected.contains(entry.0.lastPathComponent) {
                if total <= self.diskLimit { break }
                do { try fm.removeItem(at: entry.0); total -= entry.1 } catch { }
            }
            // A strict storage ceiling cannot guarantee every icon remains available offline.
            // If the active catalog alone exceeds the limit, evict its oldest icons.
            for entry in sorted where protected.contains(entry.0.lastPathComponent) {
                if total <= self.diskLimit { break }
                do { try fm.removeItem(at: entry.0); total -= entry.1 } catch { }
            }
        }
    }
}
