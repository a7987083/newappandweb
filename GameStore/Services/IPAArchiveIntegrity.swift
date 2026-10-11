import Foundation
import ZIPFoundation
import Zip

/// Lossless type checks around IPA extraction and repacking.
/// The original archive is read-only; entries are never silently coerced.
enum IPAArchiveIntegrity {
    enum Kind: String {
        case directory, symlink, file
    }

    enum Failure: LocalizedError {
        case invalidEntry(String)
        case typeChanged(String, expected: Kind, actual: Kind?)
        case missingEntry(String)
        case archiveOpen(String)

        var errorDescription: String? {
            switch self {
            case .invalidEntry(let path): return "ZIP 条目冲突或路径不安全：" + path
            case .typeChanged(let path, let expected, let actual):
                return "ZIP 类型变化：\(path)，原为 \(expected.rawValue)，现为 \(actual?.rawValue ?? "不存在")"
            case .missingEntry(let path): return "ZIP 缺少原始目录或符号链接：" + path
            case .archiveOpen(let detail): return "ZIP 无法读取：" + detail
            }
        }
    }

    struct Baseline {
        let specialEntries: [String: Kind]
    }

    private static func kind(_ entry: Entry) -> Kind {
        switch entry.type {
        case .directory: return .directory
        case .symlink: return .symlink
        case .file: return .file
        }
    }

    private static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") &&
        !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private static func archive(at url: URL) throws -> Archive {
        guard let archive = Archive(url: url, accessMode: .read, pathEncoding: .utf8) else {
            throw Failure.archiveOpen(url.lastPathComponent)
        }
        return archive
    }

    /// Inspect explicit entry types, and detect file/directory path conflicts.
    private static func entries(at archiveURL: URL) throws -> [String: Kind] {
        let archive = try archive(at: archiveURL)
        var result: [String: Kind] = [:]
        for entry in archive {
            let raw = entry.path(using: .utf8)
            guard safePath(raw) else { throw Failure.invalidEntry(raw) }
            let normalized = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            guard !normalized.isEmpty else { throw Failure.invalidEntry(raw) }
            let type = kind(entry)
            if type == .file && raw.hasSuffix("/") { throw Failure.invalidEntry(raw) }
            if result.updateValue(type, forKey: normalized) != nil {
                throw Failure.invalidEntry(normalized)
            }
        }
        for (path, _) in result {
            var components = path.split(separator: "/")
            while components.count > 1 {
                components.removeLast()
                let parent = components.joined(separator: "/")
                if let parentType = result[parent], parentType != .directory {
                    throw Failure.invalidEntry(parent)
                }
            }
        }
        return result
    }

    static func extract(_ input: URL, to destination: URL, report: (String) -> Void) throws -> Baseline {
        let manifest = try entries(at: input)
        let special = manifest.filter { $0.value != .file }
        report("ZIP 原始条目：\(manifest.count)，目录及符号链接：\(special.count)")
        // ZIPFoundation preserves Unix directory and symlink types, while the
        // legacy Zip/minizip Swift wrapper only distinguishes paths ending in '/'.
        if special.values.contains(.symlink) {
            // The legacy Zip wrapper writes link entries as ordinary files.
            // ZIPFoundation supports symlink extraction with containment checks.
            try FileManager.default.unzipItem(at: input, to: destination, pathEncoding: .utf8)
            report("ZIP 含符号链接，使用 ZIPFoundation 安全解压")
        } else {
            Zip.addCustomFileExtension("ipa")
            Zip.addCustomFileExtension("tipa")
            try Zip.unzipFile(input, destination: destination, overwrite: true, password: nil)
            report("ZIP 使用 Zonoe Zip/minizip 解压")
        }
        try checkFilesystem(root: destination, baseline: special)
        report("ZIP 解压类型核对通过：\(special.count)")
        return Baseline(specialEntries: special)
    }

    static func checkFilesystem(root: URL, baseline: [String: Kind]) throws {
        let fm = FileManager.default
        for (path, expected) in baseline {
            let target = root.appendingPathComponent(path)
            let values = try? target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
            let actual: Kind? = values?.isSymbolicLink == true ? .symlink
                : (values?.isDirectory == true ? .directory
                    : (values?.isRegularFile == true ? .file : nil))
            guard actual == expected else {
                throw Failure.typeChanged(path, expected: expected, actual: actual)
            }
            // The unpacker must not resolve symlinks outside the destination.
            if expected == .symlink {
                let link = try fm.destinationOfSymbolicLink(atPath: target.path)
                if link.hasPrefix("/") { throw Failure.invalidEntry(path) }
            }
        }
    }

    static func verifyOutput(_ output: URL, baseline: Baseline) throws {
        let final = try entries(at: output)
        for (path, expected) in baseline.specialEntries {
            // Signing replaces old code-signing metadata by design.
            if path.split(separator: "/").contains("_CodeSignature") { continue }
            guard let actual = final[path] else { throw Failure.missingEntry(path) }
            guard actual == expected else {
                throw Failure.typeChanged(path, expected: expected, actual: actual)
            }
        }
    }
}
