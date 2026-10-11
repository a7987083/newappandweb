import Foundation

/// Extracts IPA files into unique unsign_########## directories.
/// Work is staged and atomically published so partial archives never look extracted.
enum DownloadIPAExtractor {
    private static var mapURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zonoe-extraction-map.json")
    }

    private static func loadMap() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: mapURL.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: mapURL))
    }

    private static func saveMap(_ mapping: [String: String]) throws {
        try FileManager.default.createDirectory(at: mapURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(mapping).write(to: mapURL, options: .atomic)
    }

    private static func validIdentifier(_ value: String) -> Bool {
        value.count == 17 && value.hasPrefix("unsign_") &&
        value.dropFirst(7).allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static func nextIdentifier(used: Set<String>) -> String {
        while true {
            let value = "unsign_" + (0..<10).map { _ in String(Int.random(in: 0...9)) }.joined()
            if !used.contains(value) { return value }
        }
    }

    static func extract(_ ipa: URL) throws {
        let fm = FileManager.default
        let root = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zonoeunzipIPa", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var mapping = try loadMap()
        let filename = ipa.lastPathComponent
        let existing = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        let occupied = Set(mapping.values).union(existing)
        let identifier: String
        if let previous = mapping[filename], validIdentifier(previous) {
            identifier = previous
        } else {
            identifier = nextIdentifier(used: occupied)
        }
        let destination = root.appendingPathComponent(identifier, isDirectory: true)
        if mapping[filename] == identifier && fm.fileExists(atPath: destination.path) {
            // Idempotent retry: keep the original folder and mapping.
            return
        }
        let staging = root.appendingPathComponent(".staging-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var published = false
        defer { if !published { try? fm.removeItem(at: staging) } }

        // Reuse the existing signing pipeline's ZIP inspection and extraction.
        // It validates ZIP entry types and checks the resulting filesystem.
        _ = try IPAArchiveIntegrity.extract(ipa, to: staging, report: { _ in })
        let payload = staging.appendingPathComponent("Payload", isDirectory: true)
        let applications = (try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        guard applications.contains(where: { candidate in
            candidate.pathExtension.lowercased() == "app" &&
            (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }) else {
            throw NSError(domain: "GameStore.IPAExtractor", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "IPA 缺少 Payload 应用目录"])
        }
        // Publish a complete extraction, then commit its stable IPA mapping.
        // Never overwrite a directory belonging to a different archive.
        guard !fm.fileExists(atPath: destination.path) else {
            throw NSError(domain: "GameStore.IPAExtractor", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "解压目录已存在，拒绝覆盖"])
        }
        try fm.moveItem(at: staging, to: destination)
        published = true
        do {
            mapping[filename] = identifier
            try saveMap(mapping)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    static func removeExtraction(for ipa: URL) throws {
        let fm = FileManager.default
        var mapping = try loadMap()
        let filename = ipa.lastPathComponent
        guard let identifier = mapping[filename], validIdentifier(identifier) else { return }
        guard mapping.filter({ $0.key != filename }).values.contains(identifier) == false else {
            throw NSError(domain: "GameStore.IPAExtractor", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "解压目录映射冲突"])
        }
        let root = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zonoeunzipIPa", isDirectory: true)
        let destination = root.appendingPathComponent(identifier, isDirectory: true)
        // Protect against unexpected symlink replacement.
        let values = try? destination.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else {
            throw NSError(domain: "GameStore.IPAExtractor", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "不安全的解压目录"])
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        mapping.removeValue(forKey: filename)
        try saveMap(mapping)
    }
}
