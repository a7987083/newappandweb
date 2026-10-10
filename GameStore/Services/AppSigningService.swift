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
        if let png = request.editing.replacementIconPNG {
            try IPAIconReplacement.apply(png: png, to: app)
        }
        if options.temporarySigning {
            emit(.signing)
            var callbackError: Error?
            _ = Zsign.sign(
                appPath: app.path,
                entitlementsPath: "",
                customIdentifier: request.editing.bundleIdentifier ?? "",
                customName: request.editing.displayName ?? "",
                customVersion: request.editing.version ?? "",
                adhoc: true,
                removeProvision: false,
                completion: { _, error in callbackError = error }
            )
            if let error = callbackError {
                throw SigningServiceError.nativeSigningFailed(error.localizedDescription)
            }
            let signature = app.appendingPathComponent("_CodeSignature/CodeResources")
            guard fm.fileExists(atPath: signature.path) else {
                throw SigningServiceError.outputValidationFailed
            }
        } else {
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
        try verifyNestedSignatures(in: app)
        emit(.repacking)
        let outDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signed", isDirectory: true)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true, attributes: nil)
        let baseName = request.ipaURL.deletingPathExtension().lastPathComponent
        let outputName: String
        switch options.packagingRule {
        case .preserveOriginalFilename: outputName = baseName + ".ipa"
        case .standardIPA: outputName = baseName + (options.temporarySigning ? "-adhoc-" : "-signed-") + String(UUID().uuidString.prefix(8)) + ".ipa"
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

    /// Reject nested dylibs/framework executables lacking a Mach-O code-signature command.
    /// This is a structural sanity check, not cryptographic signature verification.
    private func verifyNestedSignatures(in app: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: app,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        for case let file as URL in enumerator {
            let relative = String(file.path.dropFirst(app.path.count))
            guard relative.contains("/Frameworks/") || relative.contains("/PlugIns/") else { continue }
            guard let attributes = try? fm.attributesOfItem(atPath: file.path),
                  let size = attributes[.size] as? NSNumber, size.intValue >= 32 else { continue }
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            let data = handle.readData(ofLength: 64)
            handle.closeFile()
            guard data.count >= 28 else { continue }
            let bytes = [UInt8](data)
            let magic = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 |
                        UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            // Only inspect little-endian thin Mach-O. FAT slices require their own audit.
            guard magic == 0xfeedface || magic == 0xfeedfacf else { continue }
            let headerSize = magic == 0xfeedfacf ? 32 : 28
            let commands = Int(UInt32(bytes[16]) | UInt32(bytes[17]) << 8 |
                               UInt32(bytes[18]) << 16 | UInt32(bytes[19]) << 24)
            let commandsSize = Int(UInt32(bytes[20]) | UInt32(bytes[21]) << 8 |
                                   UInt32(bytes[22]) << 16 | UInt32(bytes[23]) << 24)
            guard commands >= 0, commands < 4096, commandsSize >= 0,
                  commandsSize <= size.intValue - headerSize else {
                throw SigningServiceError.nativeSigningFailed("Mach-O 头损坏：" + relative)
            }
            guard let reader = try? FileHandle(forReadingFrom: file) else { continue }
            reader.seek(toFileOffset: UInt64(headerSize))
            let commandData = [UInt8](reader.readData(ofLength: commandsSize))
            reader.closeFile()
            var offset = 0
            var hasSignature = false
            for _ in 0..<commands {
                guard offset + 8 <= commandData.count else { break }
                func read(_ n: Int) -> UInt32 {
                    UInt32(commandData[n]) | UInt32(commandData[n+1]) << 8 |
                    UInt32(commandData[n+2]) << 16 | UInt32(commandData[n+3]) << 24
                }
                let cmd = read(offset)
                let length = Int(read(offset + 4))
                guard length >= 8, offset + length <= commandData.count else { break }
                if cmd == 0x1d && length >= 16 {
                    let blobOffset = Int(read(offset + 8))
                    let blobSize = Int(read(offset + 12))
                    if blobSize > 0 && blobOffset >= headerSize && blobOffset <= size.intValue - blobSize {
                        hasSignature = true
                    }
                }
                offset += length
            }
            guard hasSignature else {
                throw SigningServiceError.nativeSigningFailed("嵌套 Mach-O 缺少有效签名区段：" + relative)
            }
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
        if options.registerCallback {
            let marker = "zonoe.udid.callback"
            let previous = info["ZonoeUDIDCallbackScheme"] as? String
            var urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
            urlTypes.removeAll { item in
                if item["CFBundleURLName"] as? String == marker { return true }
                guard let previous = previous else { return false }
                return (item["CFBundleURLSchemes"] as? [String])?.contains(previous) == true
            }
            let rawIdentifier = editing.bundleIdentifier ?? (info["CFBundleIdentifier"] as? String ?? "unknown")
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+.-")
            let sanitized = rawIdentifier.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }
                .joined().trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyyMMddHHmm"
            let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let scheme = "zonoe-\(sanitized.isEmpty ? "unknown" : sanitized)-\(formatter.string(from: Date()))-\(nonce)"
            urlTypes.append(["CFBundleURLName": marker, "CFBundleURLSchemes": [scheme]])
            info["CFBundleURLTypes"] = urlTypes
            info["ZonoeUDIDCallbackScheme"] = scheme
            info["ZonoeUDIDCallbackHost"] = "udid-callback"
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
