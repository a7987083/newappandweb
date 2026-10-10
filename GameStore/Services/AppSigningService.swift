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

    /// Structural verification of every thin/FAT Mach-O inside nested code bundles.
    /// Zsign remains the only signer; this checks the resulting signature slots, not trust.
    private func verifyNestedSignatures(in app: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: app,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }

        func number(_ data: [UInt8], _ at: Int, _ width: Int, _ big: Bool) -> UInt64? {
            guard at >= 0, width > 0, at <= data.count - width else { return nil }
            var result: UInt64 = 0
            if big {
                for n in at..<(at + width) { result = (result << 8) | UInt64(data[n]) }
            } else {
                for n in (at..<(at + width)).reversed() { result = (result << 8) | UInt64(data[n]) }
            }
            return result
        }

        func slices(_ data: [UInt8]) -> [(Int, Int, Bool)]? {
            guard let magic = number(data, 0, 4, true) else { return nil }
            if magic == 0xfeedfacf || magic == 0xfeedface { return [(0, data.count, true)] }
            if magic == 0xcffaedfe || magic == 0xcefaedfe { return [(0, data.count, false)] }
            let big = magic == 0xcafebabe || magic == 0xcafebabf
            let little = magic == 0xbebafeca || magic == 0xbfbafeca
            guard big || little, let count = number(data, 4, 4, big), count > 0, count <= 64 else { return nil }
            let is64 = magic == 0xcafebabf || magic == 0xbfbafeca
            let stride = is64 ? 32 : 20
            var found: [(Int, Int, Bool)] = []
            for n in 0..<Int(count) {
                let base = 8 + n * stride
                let startAt = base + 8
                let lengthAt = base + (is64 ? 16 : 12)
                guard let start = number(data, startAt, is64 ? 8 : 4, big),
                      let length = number(data, lengthAt, is64 ? 8 : 4, big),
                      length >= 28, start <= UInt64(data.count),
                      length <= UInt64(data.count) - start else { return nil }
                found.append((Int(start), Int(length), true))
            }
            return found
        }

        func check(_ data: [UInt8], slice: (Int, Int, Bool), file: String) throws {
            let base = slice.0, length = slice.1
            guard let magic = number(data, base, 4, true) else { throw SigningServiceError.nativeSigningFailed("Mach-O 无效：" + file) }
            let is64 = magic == 0xfeedfacf || magic == 0xcffaedfe
            let big = magic == 0xfeedface || magic == 0xfeedfacf
            guard is64 || magic == 0xfeedface || magic == 0xcefaedfe else {
                throw SigningServiceError.nativeSigningFailed("Mach-O 架构无效：" + file)
            }
            let header = is64 ? 32 : 28
            guard length >= header, let ncmd = number(data, base + 16, 4, big),
                  let cmdsSize = number(data, base + 20, 4, big),
                  ncmd <= 4096, cmdsSize <= UInt64(length - header) else {
                throw SigningServiceError.nativeSigningFailed("Mach-O Load Commands 无效：" + file)
            }
            var cursor = base + header
            let limit = cursor + Int(cmdsSize)
            var found = false
            for _ in 0..<Int(ncmd) {
                guard cursor + 8 <= limit,
                      let cmd = number(data, cursor, 4, big),
                      let bytes = number(data, cursor + 4, 4, big),
                      bytes >= 8, bytes <= UInt64(limit - cursor) else {
                    throw SigningServiceError.nativeSigningFailed("Mach-O Load Command 损坏：" + file)
                }
                if cmd == 0x1d && bytes >= 16,
                   let offset = number(data, cursor + 8, 4, big),
                   let size = number(data, cursor + 12, 4, big),
                   size > 0, offset <= UInt64(length),
                   size <= UInt64(length) - offset { found = true }
                cursor += Int(bytes)
            }
            if !found { throw SigningServiceError.nativeSigningFailed("嵌套 Mach-O 缺少签名区段：" + file) }
        }

        for case let file as URL in enumerator {
            let relative = String(file.path.dropFirst(app.path.count))
            guard relative.contains("/Frameworks/") || relative.contains("/PlugIns/") ||
                  relative.contains("/Watch/") || relative.contains("/XPCServices/") else { continue }
            guard let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue,
                  size >= 28, size <= 500 * 1024 * 1024 else { continue }
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            let bytes = [UInt8](data)
            guard let magic = number(bytes, 0, 4, true) else { continue }
            let supported: Set<UInt64> = [0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe,
                                           0xcafebabe, 0xcafebabf, 0xbebafeca, 0xbfbafeca]
            guard supported.contains(magic) else { continue }
            guard let sections = slices(bytes) else {
                throw SigningServiceError.nativeSigningFailed("Fat Mach-O 结构错误：" + relative)
            }
            for section in sections { try check(bytes, slice: section, file: relative) }
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
