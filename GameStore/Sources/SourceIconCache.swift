import Foundation
import UIKit

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

    private init() {
        memory.countLimit = 300
        memory.totalCostLimit = 48 * 1024 * 1024
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("GameStore/Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
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
                        self.complete(url, image: image)
                        self.schedule()
                    }
                }
            }.resume()
        }
    }

    func prefetch(_ urls: [URL]) {
        state.async {
            self.prefetchGeneration += 1
            let generation = self.prefetchGeneration
            self.background.removeAll()
            // Check existing files off the UI and network scheduling queues.
            self.diskQueue.async {
                var seen = Set<String>()
                let missing = urls.filter {
                    seen.insert($0.absoluteString).inserted &&
                    !FileManager.default.fileExists(atPath: self.path(for: $0).path)
                }
                self.state.async {
                    guard generation == self.prefetchGeneration else { return }
                    for url in missing {
                        let key = url.absoluteString
                        if self.memory.object(forKey: key as NSString) == nil &&
                            !self.active.contains(key) &&
                            !self.diskChecking.contains(key) &&
                            !self.foreground.contains(where: { $0.absoluteString == key }) {
                            self.background.append(url)
                        }
                    }
                    self.schedule()
                }
            }
        }
    }
}
