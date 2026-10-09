import Foundation
import Security

protocol AppSigning {
    func sign(
        request: SigningRequest,
        progress: @escaping (SigningState) -> Void,
        completion: @escaping (Result<SignedArtifact, Error>) -> Void
    )
}

enum SigningServiceError: LocalizedError {
    case missingCertificateFile
    case missingProvisionFile
    case certificateInvalid(OSStatus)
    case certificateIdentityMissing
    case provisionInvalid
    case implementationPending

    var errorDescription: String? {
        switch self {
        case .missingCertificateFile: return "P12 证书不存在或不可读取"
        case .missingProvisionFile: return "mobileprovision 不存在或不可读取"
        case .certificateInvalid(let status): return "P12 证书校验失败（Security 状态：\(status)）"
        case .certificateIdentityMissing: return "P12 不包含可用的签名身份"
        case .provisionInvalid: return "mobileprovision 文件为空或无效"
        case .implementationPending: return "Zsign 原生签名引擎尚未接入，未生成签名 IPA"
        }
    }
}

final class AppSigningService: AppSigning {
    func sign(
        request: SigningRequest,
        progress: @escaping (SigningState) -> Void,
        completion: @escaping (Result<SignedArtifact, Error>) -> Void
    ) {
        // Signing is explicitly unavailable until the native Zsign engine is linked.
        // Preflight verifies inputs but never claims that an IPA was signed.
        progress(.prepareContext)
        progress(.verifyCertificate)
        do {
            try validateCertificate(request.certificate, password: request.password)
            progress(.prepareIPA)
            _ = try IPAInspector.inspect(request.ipaURL)
            completion(.failure(SigningServiceError.implementationPending))
        } catch {
            progress(.failed)
            completion(.failure(error))
        }
    }

    private func validateCertificate(_ certificate: DeviceCertificate, password: String) throws {
        guard let p12URL = certificate.p12URL,
              p12URL.isFileURL,
              let p12 = try? Data(contentsOf: p12URL), !p12.isEmpty else {
            throw SigningServiceError.missingCertificateFile
        }
        guard let provisionURL = certificate.mobileProvisionURL,
              provisionURL.isFileURL,
              let values = try? provisionURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? 0) > 0 else {
            throw SigningServiceError.missingProvisionFile
        }
        var decoded: CFArray?
        let status = SecPKCS12Import(
            p12 as CFData,
            [kSecImportExportPassphrase as String: password] as CFDictionary,
            &decoded
        )
        guard status == errSecSuccess else {
            throw SigningServiceError.certificateInvalid(status)
        }
        guard let identities = decoded as? [[String: Any]],
              identities.contains(where: { $0[kSecImportItemIdentity as String] != nil }) else {
            throw SigningServiceError.certificateIdentityMissing
        }
        // Provision CMS, entitlement consistency and Mach-O signatures are
        // validated by the native signing pipeline when integrated.
    }
}
