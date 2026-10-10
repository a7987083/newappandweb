import Foundation
import ZIPFoundation
import Zip
import CryptoKit

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
    /// User-visible diagnostics. Never include passwords, private keys or certificate bytes.
    var onReport: ((String) -> Void)?

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onReport?(message) }
    }
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
            self.report("开始处理 IPA：" + request.ipaURL.lastPathComponent)
            do {
                let options = SigningOptionsStore.shared.options
                if !options.temporarySigning {
                    emit(.verifyCertificate)
                    self.report("验证 P12 与描述文件是否可读取")
                    try self.validateCertificate(request.certificate, password: request.password)
                }
                emit(.prepareIPA)
                let source = try IPAInspector.inspect(request.ipaURL)
                self.report("原始 IPA 解析成功：\(source.bundleID) · \(source.version)")
                let result = try self.signIPA(request: request, emit: emit)
                self.report("签名与打包流程完成；注意：尚未验证 iOS 系统能否安装")
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                self.report("失败：" + error.localizedDescription)
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
        // Match Zonoe/Ksign's default "Zip" extraction engine (minizip),
        // rather than forcing ZIPFoundation's UTF-8 path decoding.
        // Keep ZIPFoundation for IPA repacking and inspection.
        try Zip.unzipFile(request.ipaURL, destination: payloadRoot, overwrite: true, password: nil)
        report("IPA 解压完成（Zonoe Zip/minizip）")
        let payload = payloadRoot.appendingPathComponent("Payload", isDirectory: true)
        let apps = (try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey]))
            .filter { $0.pathExtension.lowercased() == "app" }
        guard apps.count == 1, let app = apps.first else { throw SigningServiceError.malformedPayload }
        report("定位主 App：" + app.lastPathComponent)

        let options = SigningOptionsStore.shared.options
        try applyZonoeInfoOptions(options, editing: request.editing, to: app)
        report("Info.plist 选项已处理")
        if let png = request.editing.replacementIconPNG {
            report("正在替换应用图标")
            try IPAIconReplacement.apply(png: png, to: app)
        }
        // Match zonoe300 pre-sign preparation: discard the old main-app seal
        // and embedded profile before Zsign writes the new signing identity.
        let oldSeal = app.appendingPathComponent("_CodeSignature", isDirectory: true)
        let oldProfile = app.appendingPathComponent("embedded.mobileprovision")
        if fm.fileExists(atPath: oldSeal.path) {
            try fm.removeItem(at: oldSeal)
            report("已移除主 App 旧 _CodeSignature")
        } else { report("主 App 无旧 _CodeSignature") }
        if fm.fileExists(atPath: oldProfile.path) {
            try fm.removeItem(at: oldProfile)
            report("已移除主 App 旧 embedded.mobileprovision")
        } else { report("主 App 无旧 embedded.mobileprovision") }

        let beforeNested = nestedDiagnosticSnapshot(in: app, phase: "签名前")

        emit(.signing)
        let mode: ZNZsignKit.Mode
        if options.temporarySigning {
            mode = .adhoc
        } else {
            guard let p12 = request.certificate.p12URL,
                  let provision = request.certificate.mobileProvisionURL else {
                throw SigningServiceError.missingCertificateFile
            }
            mode = .certificate(p12: p12, provision: provision, password: request.password)
        }
        try ZNZsignKit.sign(.init(
            app: app,
            mode: mode,
            bundleIdentifier: request.editing.bundleIdentifier,
            displayName: request.editing.displayName,
            version: request.editing.version,
            entitlements: nil
        ), report: report)
        if !options.temporarySigning {
            let embedded = app.appendingPathComponent("embedded.mobileprovision")
            guard fm.fileExists(atPath: embedded.path) else {
                throw SigningServiceError.outputValidationFailed
            }
        }
        let afterNested = nestedDiagnosticSnapshot(in: app, phase: "签名后")
        compareNestedSnapshots(before: beforeNested, after: afterNested)
        emit(.repacking)
        report("开始压缩输出 IPA")
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
            report("输出 IPA 结构解析成功：" + output.lastPathComponent)
            guard fm.fileExists(atPath: output.path) else { throw SigningServiceError.outputValidationFailed }
            return SignedArtifact(ipaURL: output, bundleIdentifier: inspected.bundleID,
                                  displayName: inspected.displayName, version: inspected.version)
        } catch {
            try? fm.removeItem(at: output)
            throw error
        }
    }

    // Diagnostics only; this does NOT determine cryptographic signing validity.
    private func nestedDiagnosticSnapshot(in app: URL, phase: String) -> [String: String] {
        let fm = FileManager.default
        var snapshot: [String: String] = [:]
        var machOCount = 0
        var notMachO = 0
        var unreadable = 0
        guard let files = fm.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                        options: []) else {
            report("[\(phase)] 无法枚举 App 文件")
            return snapshot
        }
        let prefixes = ["/Frameworks/", "/PlugIns/", "/Watch/", "/XPCServices/"]
        for case let file as URL in files {
            let relative = String(file.path.dropFirst(app.path.count))
            guard prefixes.contains(where: { relative.contains($0) }) else { continue }
            let type = (try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
            if type?.isSymbolicLink == true {
                report("[\(phase)] 符号链接：\(relative)")
                continue
            }
            guard type?.isRegularFile == true else { continue }
            guard let handle = try? FileHandle(forReadingFrom: file) else {
                unreadable += 1
                report("[\(phase)] 无法读取：\(relative)")
                continue
            }
            let header = handle.readData(ofLength: 4)
            handle.closeFile()
            let magic = header.map { String(format: "%02x", $0) }.joined()
            let magics: Set<String> = ["feedfacf", "feedface", "cffaedfe", "cefaedfe",
                                       "cafebabe", "cafebabf", "bebafeca", "bfbafeca"]
            guard magics.contains(magic) else {
                notMachO += 1
                if relative.hasSuffix(".dylib") || relative.hasSuffix(".so") {
                    report("[\(phase)] 疑似动态库但非 Mach-O：\(relative) magic=\(magic)")
                }
                continue
            }
            machOCount += 1
            let size = ((try? fm.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value ?? -1
            // Size-limited diagnostics avoid reading huge UnityFramework binaries into RAM.
            if size >= 0 && size <= 128 * 1024 * 1024,
               let data = try? Data(contentsOf: file, options: .mappedIfSafe) {
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                snapshot[relative] = hash
                report("[\(phase)] Mach-O：\(relative) · \(size) bytes · SHA256 \(hash.prefix(16))…")
            } else {
                snapshot[relative] = "未计算 SHA256"
                report("[\(phase)] Mach-O：\(relative) · \(size) bytes · 跳过哈希（文件过大或读取失败）")
            }
        }
        report("[\(phase)] 汇总：Mach-O=\(machOCount)，非Mach-O资源=\(notMachO)，不可读取=\(unreadable)")
        if machOCount == 0 {
            report("[\(phase)] 提示：标准嵌套目录没有发现 Mach-O；并不表示签名成功")
        }
        return snapshot
    }

    private func compareNestedSnapshots(before: [String: String], after: [String: String]) {
        let removed = Set(before.keys).subtracting(after.keys).sorted()
        let added = Set(after.keys).subtracting(before.keys).sorted()
        let changed = before.keys.filter {
            guard let old = before[$0], let new = after[$0] else { return false }
            return old != "未计算 SHA256" && new != "未计算 SHA256" && old != new
        }.sorted()
        let unchanged = before.keys.filter {
            guard let old = before[$0], let new = after[$0] else { return false }
            return old != "未计算 SHA256" && old == new
        }.count
        report("[签名前后对比] 内容变化=\(changed.count)，未变化=\(unchanged)，新增=\(added.count)，消失=\(removed.count)")
        for path in changed { report("[内容变化] " + path) }
        for path in removed { report("[文件消失] " + path) }
        for path in added { report("[新增文件] " + path) }
        report("注意：哈希变化只表示文件内容变化，不代表签名身份或密码学验签通过")
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
