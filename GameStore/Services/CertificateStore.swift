import Foundation
import Combine
import Security

/// Certificate files are copied into the app sandbox. P12 passwords are never persisted.
final class CertificateStore: ObservableObject {
    static let shared = CertificateStore()
    @Published private(set) var certificates: [DeviceCertificate] = []
    private let fm = FileManager.default
    private var root: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SigningCertificates", isDirectory: true)
    }
    private var manifest: URL { root.appendingPathComponent("certificates.json") }

    private init() { reload() }

    func reload() {
        guard let data = try? Data(contentsOf: manifest),
              let loaded = try? JSONDecoder().decode([DeviceCertificate].self, from: data) else {
            certificates = []
            return
        }
        certificates = loaded.filter {
            guard let p12 = $0.p12URL, let profile = $0.mobileProvisionURL else { return false }
            return fm.fileExists(atPath: p12.path) && fm.fileExists(atPath: profile.path)
        }
    }

    // Display metadata only: never use the prefix as certificate identity or signing trust.
    private static func displayName(profileData: Data, fallback: String) -> String {
        guard let bytes = ProvisioningPayload.extract(from: profileData),
              let plist = try? PropertyListSerialization.propertyList(from: bytes, format: nil),
              let info = plist as? [String: Any] else { return fallback }
        func first(_ key: String) -> String? {
            let value = (info[key] as? [String])?.first ??
                (info[key] as? String)
            guard let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !clean.isEmpty else { return nil }
            return clean
        }
        return first("TeamIdentifier") ?? first("ApplicationIdentifierPrefix") ?? fallback
    }

    func add(p12 sourceP12: URL, provision sourceProvision: URL, password: String) throws {
        guard sourceP12.pathExtension.lowercased() == "p12",
              sourceProvision.pathExtension.lowercased() == "mobileprovision" else {
            throw CertificateImportError.invalidFileType
        }
        let p12Access = sourceP12.startAccessingSecurityScopedResource()
        let provisionAccess = sourceProvision.startAccessingSecurityScopedResource()
        defer {
            if p12Access { sourceP12.stopAccessingSecurityScopedResource() }
            if provisionAccess { sourceProvision.stopAccessingSecurityScopedResource() }
        }
        let p12 = try Data(contentsOf: sourceP12)
        let profile = try Data(contentsOf: sourceProvision)
        guard !p12.isEmpty && !profile.isEmpty else { throw CertificateImportError.emptyFile }
        // Match zonoe v3.0.0's native OpenSSL PKCS12 verification pipeline.
        guard NativeP12Verifier.verify(p12: sourceP12, provision: sourceProvision, password: password) else {
            throw CertificateImportError.p12PasswordRejected
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        let id = UUID().uuidString
        let dir = root.appendingPathComponent(id, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        do {
            let p12URL = dir.appendingPathComponent("certificate.p12")
            let profileURL = dir.appendingPathComponent("profile.mobileprovision")
            try p12.write(to: p12URL, options: .atomic)
            try profile.write(to: profileURL, options: .atomic)
            // Do not expose certificate material through device backups.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var folder = dir
            try folder.setResourceValues(values)
            let name = Self.displayName(profileData: profile, fallback: sourceP12.deletingPathExtension().lastPathComponent)
            let item = DeviceCertificate(id: id, name: name, p12URL: p12URL, mobileProvisionURL: profileURL)
            try CertificatePasswordKeychain.save(password, for: id)
            certificates.append(item)
            do { try persist() } catch {
                certificates.removeAll { $0.id == id }
                CertificatePasswordKeychain.delete(for: id)
                throw error
            }
        } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
    }

    func remove(_ item: DeviceCertificate) throws {
        let updated = certificates.filter { $0.id != item.id }
        let old = certificates
        certificates = updated
        do { try persist() } catch { certificates = old; throw error }
        let dir = root.appendingPathComponent(item.id, isDirectory: true)
        try? fm.removeItem(at: dir)
        CertificatePasswordKeychain.delete(for: item.id)
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(certificates)
        try data.write(to: manifest, options: .atomic)
    }
}


// Narrow ASN.1 DER reader for the encapsulated content of CMS SignedData.
// Used only to read display metadata, never to establish signature validity.
// The imported P12/profile pair is still validated by NativeP12Verifier.
private enum ProvisioningPayload {
    private struct Field {
        let tag: UInt8
        let content: Range<Int>
        let end: Int
    }

    private static func field(_ data: Data, at start: Int, within limit: Int) -> Field? {
        guard start >= 0, start < limit, limit <= data.count else { return nil }
        let tag = data[start]
        let lengthByteAt = start + 1
        guard lengthByteAt < limit else { return nil }
        let marker = data[lengthByteAt]
        var length = 0
        var cursor = lengthByteAt + 1
        if marker & 0x80 == 0 {
            length = Int(marker)
        } else {
            let width = Int(marker & 0x7f)
            guard width > 0, width <= 4, width <= limit - cursor else { return nil }
            for _ in 0..<width {
                guard length <= (Int.max >> 8) else { return nil }
                length = (length << 8) | Int(data[cursor])
                cursor += 1
            }
        }
        guard length <= limit - cursor else { return nil }
        return Field(tag: tag, content: cursor..<(cursor + length), end: cursor + length)
    }

    private static func children(_ data: Data, of parent: Field) -> [Field]? {
        var result: [Field] = []
        var cursor = parent.content.lowerBound
        while cursor < parent.content.upperBound {
            guard result.count < 16,
                  let child = field(data, at: cursor, within: parent.content.upperBound) else { return nil }
            result.append(child)
            cursor = child.end
        }
        return result
    }

    static func extract(from data: Data) -> Data? {
        guard data.count >= 32, data.count <= 8 * 1024 * 1024,
              let outer = field(data, at: 0, within: data.count),
              outer.tag == 0x30, outer.end == data.count,
              let contentInfo = children(data, of: outer), contentInfo.count == 2,
              contentInfo[0].tag == 0x06,
              // CMS signedData: 1.2.840.113549.1.7.2
              Data(data[contentInfo[0].content]) == Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02]),
              contentInfo[1].tag == 0xa0,
              let signedContainer = children(data, of: contentInfo[1]),
              signedContainer.count == 1, signedContainer[0].tag == 0x30,
              let signed = children(data, of: signedContainer[0]), signed.count >= 3,
              signed[2].tag == 0x30,
              let encapsulated = children(data, of: signed[2]),
              encapsulated.count == 2, encapsulated[0].tag == 0x06,
              encapsulated[1].tag == 0xa0,
              let payloadContainer = children(data, of: encapsulated[1]),
              payloadContainer.count == 1, payloadContainer[0].tag == 0x04 else { return nil }
        return Data(data[payloadContainer[0].content])
    }
}

enum CertificateImportError: LocalizedError {
    case invalidFileType, emptyFile, p12PasswordRejected
    var errorDescription: String? {
        switch self {
        case .invalidFileType: return "请选择 .p12 证书和 .mobileprovision 描述文件"
        case .emptyFile: return "导入文件为空"
        case .p12PasswordRejected: return "Zsign P12 校验未通过：请检查密码或证书格式"
        }
    }
}

// C ABI bridge implemented in the pinned Zsign openssl_tools.mm source.
@_silgen_name("zn_p12_verify")
private func zn_p12_verify(_ p12: UnsafePointer<CChar>, _ provision: UnsafePointer<CChar>, _ password: UnsafePointer<CChar>) -> Bool

enum NativeP12Verifier {
    static func verify(p12: URL, provision: URL, password: String) -> Bool {
        return p12.path.withCString { p12Path in
            provision.path.withCString { profilePath in
                password.withCString { pass in
                    zn_p12_verify(p12Path, profilePath, pass)
                }
            }
        }
    }
}

enum CertificatePasswordKeychain {
    private static let service = "com.gamestore.signing.p12"
    static func read(for id: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ password: String, for id: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status: OSStatus
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var entry = query
            attributes.forEach { entry[$0.key] = $0.value }
            status = SecItemAdd(entry as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "无法安全保存证书密码（Keychain：\(status)）"])
        }
    }
    static func delete(for id: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
        SecItemDelete(query as CFDictionary)
    }
}
