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
        case .invalidApp: return "IPA 缺少 Payload/*.app/Info.plist"
        case .oversizedEntry: return "IPA 内部文件超出安全解析限制"
        case .unsupportedCompression: return "IPA 含不支持的压缩方式"
        case .invalidPlist: return "IPA Info.plist 格式或必需字段无效"
        }
    }
}

/// Read-only IPA inspection. Never extracts archives onto the filesystem.
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
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 22, size <= 4_294_967_295 else {
            throw IPAInspectionError.invalidArchive
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.count >= 22 else { throw IPAInspectionError.invalidArchive }

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
        guard let e = endRecord, let count = u16(data, e + 10),
              let centralSize = u32(data, e + 12),
              let offset = u32(data, e + 16),
              offset <= data.count, centralSize <= data.count - offset,
              count > 0, count < 100_000 else {
            throw IPAInspectionError.invalidArchive
        }

        var cursor = offset
        var plistBytes: Data?
        for _ in 0..<count {
            guard u32(data, cursor) == 0x02014b50,
                  let flags = u16(data, cursor + 8),
                  let method = u16(data, cursor + 10),
                  let expectedCRC = u32(data, cursor + 16),
                  let packed = u32(data, cursor + 20),
                  let unpacked = u32(data, cursor + 24),
                  let nameLength = u16(data, cursor + 28),
                  let extraLength = u16(data, cursor + 30),
                  let commentLength = u16(data, cursor + 32),
                  let localOffset = u32(data, cursor + 42) else {
                throw IPAInspectionError.invalidArchive
            }
            let headerSize = 46 + nameLength + extraLength + commentLength
            guard headerSize <= data.count - cursor,
                  let name = String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameLength),
                                    encoding: .utf8) else {
                throw IPAInspectionError.invalidArchive
            }
            cursor += headerSize
            // Exactly one top-level app; ignore nested frameworks and plugins.
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 3, parts[0] == "Payload",
               parts[1].hasSuffix(".app"), parts[2] == "Info.plist" {
                guard plistBytes == nil else { throw IPAInspectionError.invalidApp }
                guard flags & 1 == 0, unpacked <= 2_097_152,
                      packed <= 2_097_152 else { throw IPAInspectionError.oversizedEntry }
                guard u32(data, localOffset) == 0x04034b50,
                      let ln = u16(data, localOffset + 26),
                      let le = u16(data, localOffset + 28) else {
                    throw IPAInspectionError.invalidArchive
                }
                let start = localOffset + 30 + ln + le
                guard start <= data.count, packed <= data.count - start else {
                    throw IPAInspectionError.invalidArchive
                }
                let compressed = data.subdata(in: start..<start + packed)
                let raw: Data
                if method == 0 {
                    raw = compressed
                } else if method == 8 {
                    raw = try decodeDeflate(compressed, expectedLength: unpacked)
                } else {
                    throw IPAInspectionError.unsupportedCompression
                }
                guard raw.count == unpacked,
                      raw.withUnsafeBytes({ buffer in
                          Int(crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress,
                                    uInt(buffer.count)))
                      }) == expectedCRC else {
                    throw IPAInspectionError.invalidArchive
                }
                plistBytes = raw
            }
        }
        guard let plist = plistBytes,
              let properties = try PropertyListSerialization.propertyList(
                from: plist, options: [], format: nil
              ) as? [String: Any],
              let bundle = properties["CFBundleIdentifier"] as? String,
              !bundle.isEmpty else { throw IPAInspectionError.invalidPlist }
        let name = (properties["CFBundleDisplayName"] as? String)
            ?? (properties["CFBundleName"] as? String) ?? file.deletingPathExtension().lastPathComponent
        let version = (properties["CFBundleShortVersionString"] as? String)
            ?? (properties["CFBundleVersion"] as? String) ?? "未知"
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return IPAInspection(bundleID: bundle, displayName: name,
                             version: version, size: size, sha256: digest)
    }

    private static func decodeDeflate(_ input: Data, expectedLength: Int) throws -> Data {
        guard expectedLength >= 0, expectedLength <= 2_097_152 else {
            throw IPAInspectionError.oversizedEntry
        }
        var output = Data(count: expectedLength)
        let status = input.withUnsafeBytes { source -> Int32 in
            output.withUnsafeMutableBytes { destination -> Int32 in
                var stream = z_stream()
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(source.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(destination.count)
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION,
                                    Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                    return Z_STREAM_ERROR
                }
                defer { inflateEnd(&stream) }
                let result = inflate(&stream, Z_FINISH)
                return result == Z_STREAM_END && Int(stream.total_out) == expectedLength
                    ? Z_OK : Z_DATA_ERROR
            }
        }
        guard status == Z_OK else { throw IPAInspectionError.invalidArchive }
        return output
    }
}
