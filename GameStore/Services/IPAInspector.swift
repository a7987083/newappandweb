import Foundation
import CryptoKit
import zlib

struct IPAInspection {
    let bundleID: String
    let displayName: String
    let version: String
    let size: Int64
    let sha256: String
}

enum IPAInspectionError: LocalizedError {
    case invalidArchive, invalidApp, oversizedEntry, unsupportedCompression, invalidPlist
    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "IPA ZIP 结构无效或已损坏"
        case .invalidApp: return "IPA 缺少唯一的 Payload/*.app/Info.plist"
        case .oversizedEntry: return "IPA 内部文件超出安全解析限制"
        case .unsupportedCompression: return "IPA 含不支持的压缩方式"
        case .invalidPlist: return "IPA Info.plist 格式或必需字段无效"
        }
    }
}

/// Read-only verifier for ordinary ZIP32 IPA archives. ZIP64 and encryption
/// are deliberately rejected rather than partially interpreted.
enum IPAInspector {
    private static func u16(_ data: Data, _ p: Int) -> Int? {
        guard p >= 0, p <= data.count - 2 else { return nil }
        return Int(data[p]) | (Int(data[p + 1]) << 8)
    }
    private static func u32(_ data: Data, _ p: Int) -> Int? {
        guard p >= 0, p <= data.count - 4 else { return nil }
        return Int(data[p]) | (Int(data[p + 1]) << 8)
            | (Int(data[p + 2]) << 16) | (Int(data[p + 3]) << 24)
    }

    static func inspect(_ file: URL) throws -> IPAInspection {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let byteCount = values.fileSize,
              byteCount >= 22, byteCount <= Int(UInt32.max) else {
            throw IPAInspectionError.invalidArchive
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.count == byteCount else { throw IPAInspectionError.invalidArchive }

        let begin = max(0, data.count - 65_557)
        var endRecord: Int?
        for p in stride(from: data.count - 22, through: begin, by: -1) {
            if u32(data, p) == 0x06054b50,
               let comment = u16(data, p + 20),
               p + 22 + comment == data.count {
                endRecord = p
                break
            }
        }
        guard let end = endRecord,
              u16(data, end + 4) == 0, u16(data, end + 6) == 0,
              let count = u16(data, end + 10), count > 0,
              count == u16(data, end + 8), count != 0xffff,
              let centralLength = u32(data, end + 12),
              let centralOffset = u32(data, end + 16),
              centralLength != Int(UInt32.max), centralOffset != Int(UInt32.max),
              centralOffset <= end, centralLength <= end - centralOffset,
              centralOffset + centralLength == end else {
            throw IPAInspectionError.invalidArchive
        }

        var cursor = centralOffset
        let centralEnd = end
        var infoPlist: Data?
        var names = Set<String>()
        var appDirectory: String?
        for _ in 0..<count {
            guard cursor <= centralEnd - 46,
                  u32(data, cursor) == 0x02014b50,
                  let flags = u16(data, cursor + 8),
                  let method = u16(data, cursor + 10),
                  let crc = u32(data, cursor + 16),
                  let packed = u32(data, cursor + 20),
                  let unpacked = u32(data, cursor + 24),
                  let nameLen = u16(data, cursor + 28),
                  let extraLen = u16(data, cursor + 30),
                  let commentLen = u16(data, cursor + 32),
                  let diskStart = u16(data, cursor + 34),
                  let localOffset = u32(data, cursor + 42),
                  diskStart == 0, localOffset != Int(UInt32.max),
                  packed != Int(UInt32.max), unpacked != Int(UInt32.max),
                  flags & 0x0001 == 0, flags & 0x0040 == 0,
                  method == 0 || method == 8 else {
                throw IPAInspectionError.invalidArchive
            }
            let length = 46 + nameLen + extraLen + commentLen
            guard length <= centralEnd - cursor,
                  let name = String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameLen),
                                    encoding: .utf8),
                  !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"),
                  !name.split(separator: "/").contains(".."),
                  names.insert(name).inserted else {
                throw IPAInspectionError.invalidArchive
            }
            cursor += length

            guard localOffset <= centralOffset - 30,
                  u32(data, localOffset) == 0x04034b50,
                  let localFlags = u16(data, localOffset + 6),
                  let localMethod = u16(data, localOffset + 8),
                  let localNameLen = u16(data, localOffset + 26),
                  let localExtraLen = u16(data, localOffset + 28),
                  flags == localFlags, method == localMethod,
                  localNameLen == nameLen else {
                throw IPAInspectionError.invalidArchive
            }
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            guard dataStart <= centralOffset, packed <= centralOffset - dataStart,
                  data.subdata(in: localOffset + 30..<localOffset + 30 + localNameLen)
                    == Data(name.utf8) else {
                throw IPAInspectionError.invalidArchive
            }
            // For entries without data descriptors, local sizes and CRC must match.
            if flags & 0x0008 == 0 {
                guard u32(data, localOffset + 14) == crc,
                      u32(data, localOffset + 18) == packed,
                      u32(data, localOffset + 22) == unpacked else {
                    throw IPAInspectionError.invalidArchive
                }
            }

            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            let isPlist = parts.count == 3 && parts[0] == "Payload"
                && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
            if isPlist {
                guard infoPlist == nil, unpacked <= 2_097_152,
                      packed <= 2_097_152 else {
                    throw IPAInspectionError.invalidApp
                }
                let currentApp = String(parts[1])
                guard appDirectory == nil || appDirectory == currentApp else {
                    throw IPAInspectionError.invalidApp
                }
                appDirectory = currentApp
            }

            // Verify every ZIP entry's uncompressed length and CRC, in bounded
            // chunks. Only the small Info.plist is retained in memory.
            let raw = try verifyEntry(data, start: dataStart, packed: packed,
                                      unpacked: unpacked, crc: crc,
                                      method: method, collect: isPlist)
            if isPlist { infoPlist = raw }
        }
        guard cursor == centralEnd else { throw IPAInspectionError.invalidArchive }
        guard let plist = infoPlist else { throw IPAInspectionError.invalidApp }
        guard let dict = try PropertyListSerialization.propertyList(
            from: plist, options: [], format: nil
        ) as? [String: Any],
        let bundle = dict["CFBundleIdentifier"] as? String, !bundle.isEmpty else {
            throw IPAInspectionError.invalidPlist
        }
        let name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? file.deletingPathExtension().lastPathComponent
        let version = (dict["CFBundleShortVersionString"] as? String)
            ?? (dict["CFBundleVersion"] as? String) ?? "未知"
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return IPAInspection(bundleID: bundle, displayName: name,
                             version: version, size: Int64(byteCount), sha256: hash)
    }

    private static func verifyEntry(
        _ archive: Data, start: Int, packed: Int, unpacked: Int,
        crc: Int, method: Int, collect: Bool
    ) throws -> Data {
        let chunkSize = 64 * 1024
        var output = Data()
        if collect { output.reserveCapacity(unpacked) }
        var checksum: uLong = crc32(0, nil, 0)
        var produced = 0
        if method == 0 {
            guard packed == unpacked else { throw IPAInspectionError.invalidArchive }
            for offset in stride(from: 0, to: packed, by: chunkSize) {
                let count = min(chunkSize, packed - offset)
                let piece = archive.subdata(in: start + offset..<start + offset + count)
                checksum = piece.withUnsafeBytes {
                    crc32(checksum, $0.bindMemory(to: Bytef.self).baseAddress, uInt(count))
                }
                if collect { output.append(piece) }
                produced += count
            }
        } else {
            let compressed = archive.subdata(in: start..<start + packed)
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            var status: Int32 = Z_OK
            try compressed.withUnsafeBytes { input in
                var stream = z_stream()
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: input.bindMemory(to: Bytef.self).baseAddress
                )
                stream.avail_in = uInt(input.count)
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION,
                                    Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                    throw IPAInspectionError.invalidArchive
                }
                defer { inflateEnd(&stream) }
                repeat {
                    let previousOut = stream.total_out
                    status = buffer.withUnsafeMutableBufferPointer { target in
                        stream.next_out = target.baseAddress
                        stream.avail_out = uInt(target.count)
                        return inflate(&stream, Z_NO_FLUSH)
                    }
                    let count = Int(stream.total_out - previousOut)
                    guard status == Z_OK || status == Z_STREAM_END,
                          count <= unpacked - produced else {
                        throw IPAInspectionError.invalidArchive
                    }
                    if count > 0 {
                        checksum = buffer.withUnsafeBufferPointer {
                            crc32(checksum, $0.baseAddress, uInt(count))
                        }
                        if collect { output.append(contentsOf: buffer.prefix(count)) }
                        produced += count
                    }
                    if status == Z_OK && count == 0 && stream.avail_in == 0 {
                        throw IPAInspectionError.invalidArchive
                    }
                } while status != Z_STREAM_END
                guard Int(stream.total_in) == packed else {
                    throw IPAInspectionError.invalidArchive
                }
            }
        }
        guard produced == unpacked, Int(checksum) == crc else {
            throw IPAInspectionError.invalidArchive
        }
        return output
    }
}
