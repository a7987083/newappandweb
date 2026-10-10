import Foundation
import ZsignSwift
import Zsign
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
    case certificatePasswordRejected
    case provisionInvalid
    case malformedPayload
    case nativeSigningFailed(String)
    case outputValidationFailed
    case implementationPending

    var errorDescription: String? {
        switch self {
        case .missingCertificateFile: return "P12 证书不存在或不可读取"
        case .missingProvisionFile: return "mobileprovision 不存在或不可读取"
        case .certificatePasswordRejected: return "Zsign 原生 P12 密码验证失败"
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
                let options = SigningOptionsStore.shared.options
                if !options.temporarySigning {
                    emit(.verifyCertificate)
                    try self.validateCertificate(request.certificate, password: request.password)
                }
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

        let options = SigningOptionsStore.shared.options
        try applyZonoeInfoOptions(options, editing: request.editing, to: app)
        if !options.temporarySigning {
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
            customIdentifier: request.editing.bundleIdentifier ?? "",
            customName: request.editing.displayName ?? "",
            customVersion: request.editing.version ?? "",
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

        }
        emit(.repacking)
        let outDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signed", isDirectory: true)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true, attributes: nil)
        let baseName = request.ipaURL.deletingPathExtension().lastPathComponent
        let outputName: String
        switch options.packagingRule {
        case .preserveOriginalFilename: outputName = baseName + ".ipa"
        case .standardIPA: outputName = baseName + (options.temporarySigning ? "-modified-" : "-signed-") + String(UUID().uuidString.prefix(8)) + ".ipa"
        }
        let ext = request.editing.outputFormat == "zip" ? "zip" : (request.editing.outputFormat == "tipa" ? "tipa" : "ipa")
        let destinationName = (outputName as NSString).deletingPathExtension + "." + ext
        let output = outDir.appendingPathComponent(destinationName)
        do {
            if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
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

    // Matches zonoe/Ksign SigningHandler._modifyDict for these five switches.
    private func applyZonoeInfoOptions(_ options: SigningOptions, editing: SigningAppEditing, to app: URL) throws {
        let url = app.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: url)
        guard var info = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw SigningServiceError.malformedPayload
        }
        if let name = editing.displayName, !name.isEmpty { info["CFBundleDisplayName"] = name }
        if let bundle = editing.bundleIdentifier, !bundle.isEmpty { info["CFBundleIdentifier"] = bundle }
        if let version = editing.version, !version.isEmpty { info["CFBundleShortVersionString"] = version }
        if let minimum = editing.minimumOS, !minimum.isEmpty { info["MinimumOSVersion"] = minimum }
        if editing.removeURLSchemes { info.removeValue(forKey: "CFBundleURLTypes") }
        if options.forceLocalization, let name = editing.displayName, !name.isEmpty {
            let localeDirs = (try? FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)) ?? []
            for directory in localeDirs where directory.pathExtension == "lproj" {
                let stringsURL = directory.appendingPathComponent("InfoPlist.strings")
                guard FileManager.default.fileExists(atPath: stringsURL.path),
                      let stringsData = try? Data(contentsOf: stringsURL),
                      let parsed = try? PropertyListSerialization.propertyList(from: stringsData, options: [], format: nil) as? [String: Any] else { continue }
                var localized = parsed
                localized["CFBundleDisplayName"] = name
                let updated = try PropertyListSerialization.data(fromPropertyList: localized, format: .binary, options: 0)
                try updated.write(to: stringsURL, options: .atomic)
            }
        }
        if options.fileSharing { info["UISupportsDocumentBrowser"] = true }
        if options.itunesFileSharing { info["UIFileSharingEnabled"] = true }
        if options.proMotion { info["CADisableMinimumFrameDurationOnPhone"] = true }
        if options.gameMode { info["GCSupportsGameMode"] = true }
        if options.ipadFullscreen { info["UIRequiresFullScreen"] = true }
        let modified = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
        try modified.write(to: url, options: .atomic)
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
        // Revalidate using the same native OpenSSL path as certificate import.
        guard NativeP12Verifier.verify(p12: p12URL, provision: provisionURL, password: password) else {
            throw SigningServiceError.certificatePasswordRejected
        }
        // Provision CMS, entitlement consistency and Mach-O signatures are
        // validated by the native signing pipeline when integrated.
    }
}
