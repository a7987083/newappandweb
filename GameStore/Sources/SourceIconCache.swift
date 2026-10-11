import Foundation
import UIKit
import ImageIO
import SQLite3

/// URL-keyed image thumbnails kept exclusively as SQLite BLOBs.
/// Decoded images use a bounded NSCache.
final class SourceIconCache {
    static let shared = SourceIconCache()

    private let memory = NSCache<NSString, UIImage>()
    private let state = DispatchQueue(label: "gamestore.icons.state")
    private let disk = DispatchQueue(label: "gamestore.icons.sqlite", qos: .utility)
    private let session: URLSession
    private let root: URL
    private let fileDirectory: URL
    private var db: OpaquePointer?
    private var waiting: [String: [(UIImage?) -> Void]] = [:]
    private var foreground: [URL] = []
    private var background: [URL] = []
    private var active = Set<String>()
    private var checking = Set<String>()
    private var failed = Set<String>()
    private var knownURLs: [URL] = []
    private let downloadLimit = 4
    private let diskLimit = 50 * 1024 * 1024
    private var writesSincePrune = 0

    private init() {
        memory.countLimit = 120
        memory.totalCostLimit = 12 * 1024 * 1024
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameStore/CompactIcons", isDirectory: true)
        fileDirectory = root.appendingPathComponent("data", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        disk.async { self.openDatabase() }
    }

    private func hash(_ key: String) -> String {
        var value: UInt64 = 14695981039346656037
        for byte in key.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
        return String(format: "%016llx", value)
    }

    private func openDatabase() {
        guard db == nil else { return }
        let path = root.appendingPathComponent("manifest.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            if db != nil { sqlite3_close(db); db = nil }
            return
        }
        sqlite3_busy_timeout(db, 3000)
        exec("PRAGMA journal_mode=WAL")
        exec("CREATE TABLE IF NOT EXISTS manifest (key TEXT PRIMARY KEY, filename TEXT, size INTEGER NOT NULL, inline_data BLOB, last_access_time INTEGER NOT NULL)")
        exec("CREATE INDEX IF NOT EXISTS idx_access ON manifest(last_access_time)")
        migrateFileEntries()
    }

    /// Upgrade existing file-backed entries without losing cached images.
    /// Called only by the serial SQLite queue.
    private func migrateFileEntries() {
        guard let stmt = prepare("SELECT key,filename FROM manifest WHERE filename IS NOT NULL") else { return }
        var entries: [(String, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let k = sqlite3_column_text(stmt, 0), let f = sqlite3_column_text(stmt, 1) {
                entries.append((String(cString: k), String(cString: f)))
            }
        }
        sqlite3_finalize(stmt)
        for (key, name) in entries {
            let path = fileDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: path) else { continue }
            guard let update = prepare("UPDATE manifest SET filename=NULL, inline_data=?,size=? WHERE key=?") else { continue }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            _ = data.withUnsafeBytes {
                sqlite3_bind_blob(update, 1, $0.baseAddress, Int32(data.count), transient)
            }
            sqlite3_bind_int64(update, 2, Int64(data.count))
            bindText(key, to: update, at: 3)
            let saved = sqlite3_step(update) == SQLITE_DONE
            sqlite3_finalize(update)
            if saved { try? FileManager.default.removeItem(at: path) }
        }
        // Remove unreferenced old blobs only after every referenced item migrated.
        let remaining = prepare("SELECT COUNT(*) FROM manifest WHERE filename IS NOT NULL")
        let hasPending = remaining != nil && sqlite3_step(remaining) == SQLITE_ROW && sqlite3_column_int(remaining, 0) > 0
        sqlite3_finalize(remaining)
        if !hasPending {
            try? FileManager.default.removeItem(at: fileDirectory)
            // The original URL-hash cache is no longer read after the SQLite upgrade.
            let legacy = root.deletingLastPathComponent().appendingPathComponent("Icons", isDirectory: true)
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    private func exec(_ sql: String) {
        _ = sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard db != nil else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            if statement != nil { sqlite3_finalize(statement) }
            return nil
        }
        return statement
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func read(_ url: URL) -> Data? {
        let key = url.absoluteString
        guard let stmt = prepare("SELECT filename, inline_data FROM manifest WHERE key=?") else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(key, to: stmt, at: 1)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        var bytes: Data?
        if let pointer = sqlite3_column_blob(stmt, 1) {
            bytes = Data(bytes: pointer, count: Int(sqlite3_column_bytes(stmt, 1)))
        } else if let filename = sqlite3_column_text(stmt, 0) {
            let name = String(cString: filename)
            bytes = try? Data(contentsOf: fileDirectory.appendingPathComponent(name))
        }
        if bytes != nil {
            if let update = prepare("UPDATE manifest SET last_access_time=? WHERE key=?") {
                sqlite3_bind_int64(update, 1, Int64(Date().timeIntervalSince1970))
                bindText(key, to: update, at: 2)
                _ = sqlite3_step(update)
                sqlite3_finalize(update)
            }
        }
        return bytes
    }

    private func store(_ data: Data, for url: URL) {
        guard let stmt = prepare("INSERT OR REPLACE INTO manifest(key,filename,size,inline_data,last_access_time) VALUES(?,NULL,?,?,?)") else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(url.absoluteString, to: stmt, at: 1)
        sqlite3_bind_int64(stmt, 2, Int64(data.count))
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = data.withUnsafeBytes {
            sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(data.count), transient)
        }
        sqlite3_bind_int64(stmt, 4, Int64(Date().timeIntervalSince1970))
        if sqlite3_step(stmt) == SQLITE_DONE {
            writesSincePrune += 1
            if writesSincePrune >= 32 { writesSincePrune = 0; prune() }
        }
    }

    /// Evict least-recently-used records; count SQLite storage as part of the budget.
    private func prune() {
        guard let stmt = prepare("SELECT key,filename,size FROM manifest ORDER BY last_access_time ASC") else { return }
        var records: [(String, String?, Int)] = []
        var total = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let keyPointer = sqlite3_column_text(stmt, 0) else { continue }
            let key = String(cString: keyPointer)
            let filename = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let size = Int(sqlite3_column_int64(stmt, 2))
            records.append((key, filename, size))
            total += size
        }
        sqlite3_finalize(stmt)
        guard total > diskLimit else { return }
        for (key, filename, size) in records where total > diskLimit {
            if let stmt = prepare("DELETE FROM manifest WHERE key=?") {
                bindText(key, to: stmt, at: 1)
                _ = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            if let filename = filename {
                try? FileManager.default.removeItem(at: fileDirectory.appendingPathComponent(filename))
            }
            total -= size
        }
        exec("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    private func thumbnail(_ bytes: Data) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(bytes as CFData, options) else { return nil }
        let settings: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 120,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, settings as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private func imageCost(_ image: UIImage) -> Int {
        Int(image.size.width * image.size.height * image.scale * image.scale * 4)
    }

    func cachedMemoryImage(for url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        if let cached = cachedMemoryImage(for: url) {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        state.async {
            let key = url.absoluteString
            if self.waiting[key] != nil {
                self.waiting[key]?.append(completion)
                return
            }
            self.waiting[key] = [completion]
            self.foreground.insert(url, at: 0)
            self.background.removeAll { $0.absoluteString == key }
            self.checkDisk(url)
        }
    }

    private func checkDisk(_ url: URL) {
        let key = url.absoluteString
        guard checking.insert(key).inserted else { return }
        disk.async {
            let image = self.read(url).flatMap(self.thumbnail)
            self.state.async {
                self.checking.remove(key)
                if let image = image {
                    self.foreground.removeAll { $0.absoluteString == key }
                    self.finish(url, image: image)
                } else {
                    self.runQueue()
                }
            }
        }
    }

    private func finish(_ url: URL, image: UIImage?) {
        let key = url.absoluteString
        if let image = image {
            memory.setObject(image, forKey: key as NSString, cost: imageCost(image))
        }
        let handlers = waiting.removeValue(forKey: key) ?? []
        DispatchQueue.main.async { handlers.forEach { $0(image) } }
    }

    private func runQueue() {
        while active.count < downloadLimit {
            let url: URL
            if !foreground.isEmpty {
                url = foreground.removeFirst()
            } else if !background.isEmpty {
                url = background.removeFirst()
            } else {
                return
            }
            let key = url.absoluteString
            if active.contains(key) || checking.contains(key) || failed.contains(key) { continue }
            active.insert(key)
            session.dataTask(with: url) { data, response, error in
                var image: UIImage?
                var encoded: Data?
                if error == nil, let http = response as? HTTPURLResponse,
                   (200...299).contains(http.statusCode),
                   let bytes = data, bytes.count <= 5 * 1024 * 1024 {
                    image = self.thumbnail(bytes)
                    if let image = image { encoded = image.pngData() }
                }
                self.disk.async {
                    if let encoded = encoded { self.store(encoded, for: url) }
                    self.state.async {
                        self.active.remove(key)
                        if image == nil { self.failed.insert(key) }
                        self.finish(url, image: image)
                        self.runQueue()
                    }
                }
            }.resume()
        }
    }

    func prefetch(_ urls: [URL]) {
        state.async {
            self.knownURLs = urls
            self.failed.removeAll()
            let visible = Set(self.foreground.map { $0.absoluteString })
            self.background = urls.filter {
                !visible.contains($0.absoluteString) &&
                !self.active.contains($0.absoluteString)
            }
            // Avoid network work for entries already saved to SQLite.
            let candidates = self.background
            self.background.removeAll()
            self.disk.async {
                let missing = candidates.filter { self.read($0) == nil }
                self.state.async {
                    self.background = missing.filter {
                        !self.active.contains($0.absoluteString) &&
                        !self.checking.contains($0.absoluteString) &&
                        !self.foreground.contains($0)
                    }
                    self.runQueue()
                }
            }
        }
    }
}
