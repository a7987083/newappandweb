import Foundation
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
        // Match zonoe v3.0.0's native OpenSSL PKCS12 verification pipeline.
        password_check_fix_WHAT_THE_FUCK(sourceProvision.path)
        defer { password_check_fix_WHAT_THE_FUCK_free(sourceProvision.path) }
        guard p12_password_check(sourceP12.path, password) else {
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
    case invalidFileType, emptyFile, p12PasswordRejected
    var errorDescription: String? {
        switch self {
        case .invalidFileType: return "请选择 .p12 证书和 .mobileprovision 描述文件"
        case .emptyFile: return "导入文件为空"
        case .p12PasswordRejected: return "Zsign P12 校验未通过：请检查密码或证书格式"
        }
    }
}
