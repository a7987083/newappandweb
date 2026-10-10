import Foundation
import UIKit

/// Persistent icon cache. URL is the identity; existing downloaded icons survive app relaunch.
final class SourceIconCache {
    static let shared = SourceIconCache()
    private let memory = NSCache<NSString, UIImage>()
    private let worker = OperationQueue()
    private let lock = NSLock()
    private var waiting = [String: [(UIImage?) -> Void]]()
    private var pendingOperations = [String: Operation]()
    private let session: URLSession
    private let directory: URL

    private init() {
        worker.maxConcurrentOperationCount = 4
        worker.qualityOfService = .utility
        memory.countLimit = 300
        memory.totalCostLimit = 48 * 1024 * 1024
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("GameStore/Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        var config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    private func path(for url: URL) -> URL {
        // Stable FNV-1a 64-bit fingerprint, independent of Swift's randomized Hasher.
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
        enqueue(url, priority: .veryHigh, completion: completion)
    }

    private func enqueue(_ url: URL, priority: Operation.QueuePriority, completion: @escaping (UIImage?) -> Void) {
        if let image = cachedMemoryImage(for: url) {
            DispatchQueue.main.async { completion(image) }
            return
        }
        let key = url.absoluteString
        lock.lock()
        if waiting[key] != nil {
            waiting[key]?.append(completion)
            if priority == .veryHigh { pendingOperations[key]?.queuePriority = .veryHigh }
            lock.unlock()
            return
        }
        waiting[key] = [completion]
        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }
            let file = self.path(for: url)
            var image: UIImage?
            if let data = try? Data(contentsOf: file) { image = UIImage(data: data) }
            if image == nil, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
                let gate = DispatchSemaphore(value: 0)
                var bytes: Data?
                self.session.dataTask(with: url) { data, response, error in
                    if error == nil, let http = response as? HTTPURLResponse,
                       (200...299).contains(http.statusCode), let data = data,
                       data.count <= 5 * 1024 * 1024 {
                        bytes = data
                    }
                    gate.signal()
                }.resume()
                _ = gate.wait(timeout: .now() + 25)
                if let data = bytes, let valid = UIImage(data: data) {
                    image = valid
                    try? data.write(to: file, options: .atomic)
                }
            }
            if let image = image {
                self.memory.setObject(image, forKey: key as NSString,
                                      cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
            }
            self.lock.lock()
            let callbacks = self.waiting.removeValue(forKey: key) ?? []
            self.pendingOperations.removeValue(forKey: key)
            self.lock.unlock()
            let result = image
            DispatchQueue.main.async { callbacks.forEach { $0(result) } }
        }
        operation.queuePriority = priority
        pendingOperations[key] = operation
        lock.unlock()
        worker.addOperation(operation)
    }

    func prefetch(_ urls: [URL]) {
        // Bounded concurrency; duplicate URL requests are merged by load().
        for url in Set(urls) { enqueue(url, priority: .veryLow) { _ in } }
    }
}
