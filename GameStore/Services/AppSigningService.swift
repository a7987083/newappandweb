import Foundation
import Security
import ZsignSwift
import ZIPFoundation

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
    case malformedPayload
    case nativeSigningFailed(String)
    case outputValidationFailed
    case implementationPending

    var errorDescription: String? {
        switch self {
        case .missingCertificateFile: return "P12 证书不存在或不可读取"
        case .missingProvisionFile: return "mobileprovision 不存在或不可读取"
        case .certificateInvalid(let status): return "P12 证书校验失败（Security 状态：\(status)）"
        case .certificateIdentityMissing: return "P12 不包含可用的签名身份"
        case .provisionInvalid: return "mobileprovision 文件为空或无效"
        case .malformedPayload: return "IPA 解包后未找到唯一的 Payload/*.app"
        case .nativeSigningFailed(let detail): return "Zsign 签名失败：" + detail
        case .outputValidationFailed: return "签名产物检查失败，未生成有效 IPA"
        case .implementationPending: return "签名引擎未完成初始化"
        }
    }
}

final class AppSigningService: AppSigning {
    func sign(
        request: SigningRequest,
        progress: @escaping (SigningState) -> Void,
        completion: @escaping (Result<SignedArtifact, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let emit: (SigningState) -> Void = { state in
                DispatchQueue.main.async { progress(state) }
            }
            emit(.prepareContext)
            do {
                emit(.verifyCertificate)
                try self.validateCertificate(request.certificate, password: request.password)
                emit(.prepareIPA)
                _ = try IPAInspector.inspect(request.ipaURL)
                let result = try self.signIPA(request: request, emit: emit)
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                emit(.failed)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func signIPA(request: SigningRequest, emit: (SigningState) -> Void) throws -> SignedArtifact {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("zonoe-sign-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true, attributes: nil)
        defer { try? fm.removeItem(at: work) }
        let payloadRoot = work.appendingPathComponent("archive", isDirectory: true)
        try fm.createDirectory(at: payloadRoot, withIntermediateDirectories: true, attributes: nil)

        emit(.extracting)
        try fm.unzipItem(at: request.ipaURL, to: payloadRoot)
        let payload = payloadRoot.appendingPathComponent("Payload", isDirectory: true)
        let apps = (try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey]))
            .filter { $0.pathExtension.lowercased() == "app" }
        guard apps.count == 1, let app = apps.first else { throw SigningServiceError.malformedPayload }

        guard let p12 = request.certificate.p12URL,
              let provision = request.certificate.mobileProvisionURL else {
            throw SigningServiceError.missingCertificateFile
        }

        emit(.signing)
        var callbackError: Error?
        let signed = Zsign.sign(
            appPath: app.path,
            provisionPath: provision.path,
            p12Path: p12.path,
            p12Password: request.password,
            entitlementsPath: "",
            customIdentifier: "",
            customName: "",
            customVersion: "",
            removeProvision: false,
            completion: { _, error in
                callbackError = error
            }
        )
        _ = signed
        if let error = callbackError {
            throw SigningServiceError.nativeSigningFailed(error.localizedDescription)
        }

        // Do not report success unless the app has both a signature resource
        // and the embedded provisioning profile required for installation.
        let signature = app.appendingPathComponent("_CodeSignature/CodeResources")
        let embedded = app.appendingPathComponent("embedded.mobileprovision")
        guard fm.fileExists(atPath: signature.path),
              fm.fileExists(atPath: embedded.path) else {
            throw SigningServiceError.outputValidationFailed
        }

        emit(.repacking)
        let outDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signed", isDirectory: true)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true, attributes: nil)
        let output = outDir.appendingPathComponent(
            request.ipaURL.deletingPathExtension().lastPathComponent + "-signed-" +
            UUID().uuidString.prefix(8) + ".ipa")
        do {
            try fm.zipItem(at: payloadRoot, to: output, shouldKeepParent: false, compressionMethod: .deflate)
            emit(.verifySignature)
            let inspected = try IPAInspector.inspect(output)
            guard fm.fileExists(atPath: output.path) else { throw SigningServiceError.outputValidationFailed }
            return SignedArtifact(ipaURL: output, bundleIdentifier: inspected.bundleID,
                                  displayName: inspected.displayName, version: inspected.version)
        } catch {
            try? fm.removeItem(at: output)
            throw error
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
