import Foundation
import Zip
import ZIPFoundation

/// Zip/minizip controls the DEFLATE level. ZIPFoundation restores the entry
/// types that Zip.zipFiles does not emit, then we preserve Unix permissions.
enum IPAArchivePackager {
    enum Failure: LocalizedError {
        case invalidArchive(String)
        var errorDescription: String? {
            switch self {
            case .invalidArchive(let message): return "IPA 压缩结构错误：" + message
            }
        }
    }

    static func pack(root: URL, output: URL, preset: IPACompressionPreset) throws {
        let payload = root.appendingPathComponent("Payload", isDirectory: true)
        let compression: ZipCompression
        switch preset {
        case .fast: compression = .BestSpeed
        case .balanced: compression = .DefaultCompression
        case .maximum: compression = .BestCompression
        }
        // Zip.zipFiles preserves the Payload/ prefix but emits ordinary files only.
        // Never publish its raw result as an IPA.
        let temporary = output.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Zip.zipFiles(paths: [payload], zipFilePath: temporary,
                         password: nil, compression: compression, progress: nil)
        try restoreSpecialEntries(archiveURL: temporary, root: root)
        try restoreUnixAttributes(archiveURL: temporary, root: root)
        try FileManager.default.moveItem(at: temporary, to: output)
    }

    private static func restoreSpecialEntries(archiveURL: URL, root: URL) throws {
        let fm = FileManager.default
        let archive = try Archive(url: archiveURL, accessMode: .update, pathEncoding: .utf8)
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys:
            [.isDirectoryKey, .isSymbolicLinkKey], options: []) else {
            throw Failure.invalidArchive("无法枚举签名后目录")
        }
        var special: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isDirectory == true || values.isSymbolicLink == true {
                special.append(String(url.path.dropFirst(root.path.count + 1)))
            }
        }
        // A symlink to a directory must not be enumerated recursively.
        // Re-create explicit entries without changing the content compression level.
        for relative in special.sorted() {
            let source = root.appendingPathComponent(relative)
            let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isLink = values.isSymbolicLink == true
            let entryName = isLink ? relative : relative + "/"
            if isLink, let existing = archive[relative] {
                try archive.remove(existing)
            }
            if archive[entryName] == nil {
                try archive.addEntry(with: entryName, relativeTo: root, compressionMethod: .none)
            }
        }
    }

    /// Patch ZIP32 central-directory Unix external attributes from the real files.
    /// Zip.zipFiles otherwise emits external_fa=0, losing executable permissions.
    private static func restoreUnixAttributes(archiveURL: URL, root: URL) throws {
        let fh = try FileHandle(forUpdating: archiveURL)
        defer { fh.closeFile() }
        let length = fh.seekToEndOfFile()
        let window = min(length, UInt64(65_557))
        fh.seek(toFileOffset: length - window)
        let tail = fh.readData(ofLength: Int(window))
        guard tail.count >= 22 else { throw Failure.invalidArchive("ZIP EOCD 不存在") }
        func u16(_ d: Data, _ p: Int) -> Int {
            Int(d[p]) | (Int(d[p+1]) << 8)
        }
        func u32(_ d: Data, _ p: Int) -> Int {
            u16(d,p) | (u16(d,p+2) << 16)
        }
        var eocd: Int?
        for i in stride(from: tail.count - 22, through: 0, by: -1) {
            if u32(tail,i) == 0x06054b50 && i+22+u16(tail,i+20) == tail.count {
                eocd = i
                break
            }
        }
        guard let end = eocd else { throw Failure.invalidArchive("ZIP EOCD 无效") }
        let count = u16(tail,end+10)
        let offset = u32(tail,end+16)
        guard count != 0xffff && offset != 0xffffffff else {
            throw Failure.invalidArchive("暂不支持 ZIP64 回包")
        }
        var cursor = UInt64(offset)
        let fm = FileManager.default
        for _ in 0..<count {
            fh.seek(toFileOffset: cursor)
            let header = fh.readData(ofLength: 46)
            guard header.count == 46, u32(header,0) == 0x02014b50 else {
                throw Failure.invalidArchive("ZIP Central Directory 条目无效")
            }
            let nameLen = u16(header,28)
            let extraLen = u16(header,30)
            let commentLen = u16(header,32)
            let nameData = fh.readData(ofLength: nameLen)
            guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else {
                throw Failure.invalidArchive("ZIP 文件名无法以 UTF-8 解码")
            }
            let rawName = name.hasSuffix("/") ? String(name.dropLast()) : name
            let url = root.appendingPathComponent(rawName)
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint32Value ?? 0o644
            let mode: UInt32 = (values.isSymbolicLink == true ? 0o120000 :
                (values.isDirectory == true ? 0o040000 : 0o100000)) | (permissions & 0o7777)
            let external = mode << 16
            fh.seek(toFileOffset: cursor + 4)
            fh.write(Data([20, 3])) // ZIP 2.0, Unix creator
            fh.seek(toFileOffset: cursor + 38)
            fh.write(Data([UInt8(external & 255), UInt8((external >> 8) & 255),
                           UInt8((external >> 16) & 255), UInt8((external >> 24) & 255)]))
            cursor += UInt64(46 + nameLen + extraLen + commentLen)
        }
    }
}
