import Foundation
import Zip

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

    static func preparedDirectory(for ipa: URL) throws -> URL? {
        let fm = FileManager.default
        let downloads = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zonoeDownloads", isDirectory: true)
        guard ipa.standardizedFileURL.deletingLastPathComponent() == downloads.standardizedFileURL else { return nil }
        let mapping = try loadMap()
        guard let identifier = mapping[ipa.lastPathComponent], validIdentifier(identifier) else { return nil }
        let directory = downloads.deletingLastPathComponent()
            .appendingPathComponent("zonoeunzipIPa", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        let attributes = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard attributes?.isDirectory == true, attributes?.isSymbolicLink != true else { return nil }
        let payload = directory.appendingPathComponent("Payload", isDirectory: true)
        let apps = (try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let validApps = apps.filter { $0.pathExtension.lowercased() == "app" &&
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard validApps.count == 1,
              let plist = NSDictionary(contentsOf: validApps[0].appendingPathComponent("Info.plist")),
              let bundle = plist["CFBundleIdentifier"] as? String, !bundle.isEmpty else { return nil }
        return directory
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
            if try preparedDirectory(for: ipa) != nil { return }
            // An incomplete mapped directory must not be reused.
            try fm.removeItem(at: destination)
        }
        let staging = root.appendingPathComponent(".staging-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var published = false
        defer { if !published { try? fm.removeItem(at: staging) } }

        // Match the signing pipeline: SC_Info entries in some IPA archives
        // fail the strict IPAArchiveIntegrity preflight despite being unpackable.
        Zip.addCustomFileExtension("ipa")
        Zip.addCustomFileExtension("tipa")
        try Zip.unzipFile(ipa, destination: staging, overwrite: true, password: nil)
        let payload = staging.appendingPathComponent("Payload", isDirectory: true)
        let applications = (try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let verifiedApps = applications.filter { candidate in
            candidate.pathExtension.lowercased() == "app" &&
            (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
            fm.fileExists(atPath: candidate.appendingPathComponent("Info.plist").path)
        }
        guard verifiedApps.count == 1,
              let plist = NSDictionary(contentsOf: verifiedApps[0].appendingPathComponent("Info.plist")),
              let bundle = plist["CFBundleIdentifier"] as? String, !bundle.isEmpty else {
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

    /// Rename the extraction mapping after promoting a hidden, validated download.
    static func promote(from staged: URL, to final: URL) throws {
        let fm = FileManager.default
        var mapping = try loadMap()
        guard let directory = mapping[staged.lastPathComponent], validIdentifier(directory) else {
            throw NSError(domain: "GameStore.IPAExtractor", code: 9,
                userInfo: [NSLocalizedDescriptionKey: "暂存文件没有有效解压映射"])
        }
        guard mapping[final.lastPathComponent] == nil else {
            throw NSError(domain: "GameStore.IPAExtractor", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "安装包映射已存在"])
        }
        try fm.moveItem(at: staged, to: final)
        mapping.removeValue(forKey: staged.lastPathComponent)
        mapping[final.lastPathComponent] = directory
        do { try saveMap(mapping) }
        catch {
            try? fm.moveItem(at: final, to: staged)
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
