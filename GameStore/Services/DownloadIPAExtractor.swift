import Foundation
import ZIPFoundation

/// Extracts each completed IPA into Documents/zonoeunzipIPa/<IPA filename without extension>.
/// Work is staged and atomically published so partial archives never look extracted.
enum DownloadIPAExtractor {
    static func extract(_ ipa: URL) throws {
        let fm = FileManager.default
        let root = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zonoeunzipIPa", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let folder = ipa.deletingPathExtension().lastPathComponent
        let destination = root.appendingPathComponent(folder, isDirectory: true)
        let staging = root.appendingPathComponent(".staging-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var published = false
        defer { if !published { try? fm.removeItem(at: staging) } }

        guard let archive = Archive(url: ipa, accessMode: .read, pathEncoding: .utf8) else {
            throw NSError(domain: "GameStore.IPAExtractor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "IPA 压缩文件无法打开"])
        }
        var hasApp = false
        var entries = 0
        var expanded: Int64 = 0
        for entry in archive {
            let path = entry.path
            let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path
            let parts = normalized.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.hasPrefix("/"), !path.contains("\\"),
                  !parts.contains(".."), !parts.contains("."),
                  !parts.contains(""), !path.contains(":"),
                  entry.type != .symlink else {
                throw NSError(domain: "GameStore.IPAExtractor", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "IPA 包含不安全的文件路径"])
            }
            entries += 1
            guard entries <= 200_000 else {
                throw NSError(domain: "GameStore.IPAExtractor", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "IPA 文件条目过多"])
            }
            let size = Int64(entry.uncompressedSize)
            guard size >= 0, expanded <= 12_000_000_000 - size else {
                throw NSError(domain: "GameStore.IPAExtractor", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "IPA 解压容量超过限制"])
            }
            expanded += size
            if path.hasPrefix("Payload/") && path.contains(".app/") { hasApp = true }
            let target = staging.appendingPathComponent(path)
            if entry.type == .directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                _ = try archive.extract(entry, to: target)
            }
        }
        guard hasApp else {
            throw NSError(domain: "GameStore.IPAExtractor", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "IPA 缺少 Payload 应用目录"])
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: staging, to: destination)
        published = true
    }

    static func removeExtraction(for ipa: URL) throws {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zonoeunzipIPa", isDirectory: true)
        let folder = ipa.deletingPathExtension().lastPathComponent
        let destination = root.appendingPathComponent(folder, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
    }
}
