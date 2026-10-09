import Foundation
import Security
import Combine

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
        var decoded: CFArray?
        let status = SecPKCS12Import(p12 as CFData,
                                    [kSecImportExportPassphrase as String: password] as CFDictionary,
                                    &decoded)
        guard status == errSecSuccess else { throw CertificateImportError.p12Invalid(status) }
        guard let identities = decoded as? [[String: Any]],
              identities.contains(where: { $0[kSecImportItemIdentity as String] != nil }) else {
            throw CertificateImportError.identityMissing
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
            let name = sourceP12.deletingPathExtension().lastPathComponent
            let item = DeviceCertificate(id: id, name: name, p12URL: p12URL, mobileProvisionURL: profileURL)
            certificates.append(item)
            try persist()
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
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(certificates)
        try data.write(to: manifest, options: .atomic)
    }
}

enum CertificateImportError: LocalizedError {
    case invalidFileType, emptyFile, p12Invalid(OSStatus), identityMissing
    var errorDescription: String? {
        switch self {
        case .invalidFileType: return "请选择 .p12 证书和 .mobileprovision 描述文件"
        case .emptyFile: return "导入文件为空"
        case .p12Invalid(let status):
            let detail = (SecCopyErrorMessageString(status, nil) as String?) ?? "未知 Security 错误"
            if status == errSecAuthFailed { return "P12 验证失败（可能是密码错误或证书加密格式不受系统支持），状态码：\(status)，\(detail)" }
            if status == errSecDecode { return "P12 解析失败（可能是证书文件损坏或加密格式不兼容），状态码：\(status)，\(detail)" }
            return "P12 导入失败，Security 状态码：\(status)，\(detail)"
        case .identityMissing: return "P12 内未找到签名身份"
        }
    }
}
