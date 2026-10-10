import Foundation
import ZsignSwift

/// Single GameStore boundary to the pinned Zsign native package.
/// Does not mutate the source IPA or manage the ZIP archive.
enum ZNZsignKit {
    enum Mode {
        case certificate(p12: URL, provision: URL, password: String)
        case adhoc
    }

    struct Request {
        let app: URL
        let mode: Mode
        let bundleIdentifier: String?
        let displayName: String?
        let version: String?
        let entitlements: URL?
    }

    enum Failure: LocalizedError {
        case nativeFailure(String)
        case unsignedMachO(String)
        case missingSignature(String)

        var errorDescription: String? {
            switch self {
            case .nativeFailure(let message): return "Zsign 原生签名失败：" + message
            case .unsignedMachO(let path): return "签名检查未通过：" + path
            case .missingSignature(let path): return "缺少 CodeResources：" + path
            }
        }
    }

    static func sign(_ request: Request, report: (String) -> Void) throws {
        let credentials: (p12: String, provision: String, password: String, adhoc: Bool)
        switch request.mode {
        case .adhoc:
            credentials = ("", "", "", true)
        case .certificate(let p12, let provision, let password):
            credentials = (p12.path, provision.path, password, false)
        }
        let targets = try discoverMachOs(in: request.app)
        report("ZNZsignKit 待签名 Mach-O：\(targets.count)")
        var callbackSuccess = false
        var callbackInvoked = false
        var callbackError: Error?
        let result = Zsign.sign(
            appPath: request.app.path,
            provisionPath: credentials.provision,
            p12Path: credentials.p12,
            p12Password: credentials.password,
            entitlementsPath: request.entitlements?.path ?? "",
            customIdentifier: request.bundleIdentifier ?? "",
            customName: request.displayName ?? "",
            customVersion: request.version ?? "",
            adhoc: credentials.adhoc,
            removeProvision: false,
            completion: { success, error in
                callbackInvoked = true
                callbackSuccess = success
                callbackError = error
            }
        )
        guard result && callbackInvoked && callbackSuccess && callbackError == nil else {
            throw Failure.nativeFailure(callbackError?.localizedDescription ??
                "result=\(result), callback=\(callbackInvoked ? String(callbackSuccess) : "missing")")
        }
        // A native success boolean alone is not proof that every nested binary was signed.
        for path in targets {
            guard FileManager.default.fileExists(atPath: path.path),
                  Zsign.checkSigned(appExecutable: path.path) else {
                throw Failure.unsignedMachO(path.path)
            }
        }
        let rootSignature = request.app.appendingPathComponent("_CodeSignature/CodeResources")
        guard FileManager.default.fileExists(atPath: rootSignature.path) else {
            throw Failure.missingSignature(rootSignature.path)
        }
        report("ZNZsignKit Mach-O 签名检查完成：\(targets.count)")
    }

    /// Scan actual Mach-O magic, not file extensions alone. Avoid treating resources as binaries.
    static func discoverMachOs(in app: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            throw Failure.nativeFailure("无法枚举 App 内容")
        }
        let magic: Set<[UInt8]> = [
            [0xfe, 0xed, 0xfa, 0xce], [0xce, 0xfa, 0xed, 0xfe],
            [0xfe, 0xed, 0xfa, 0xcf], [0xcf, 0xfa, 0xed, 0xfe],
            [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca],
            [0xca, 0xfe, 0xba, 0xbf], [0xbf, 0xba, 0xfe, 0xca]
        ]
        var files: [URL] = []
        for case let path as URL in enumerator {
            let attributes = try path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isSymbolicLink != true, attributes.isRegularFile == true else { continue }
            let handle = try FileHandle(forReadingFrom: path)
            let head = handle.readData(ofLength: 4)
            handle.closeFile()
            if magic.contains(Array(head)) { files.append(path) }
        }
        return files.sorted { $0.path < $1.path }
    }

    static func checkSigned(at macho: URL) -> Bool {
        Zsign.checkSigned(appExecutable: macho.path)
    }

    static func linkedDylibs(in macho: URL) -> [String] {
        Zsign.listDylibs(appExecutable: macho.path)
    }

    static func injectDylib(into macho: URL, loadPath: String, weak: Bool = true) -> Bool {
        Zsign.injectDyLib(appExecutable: macho.path, with: loadPath, weak: weak)
    }

    static func removeDylibs(from macho: URL, loadPaths: [String]) -> Bool {
        Zsign.removeDylibs(appExecutable: macho.path, using: loadPaths)
    }

    static func changeDylibPath(in macho: URL, old: String, new: String) -> Bool {
        Zsign.changeDylibPath(appExecutable: macho.path, for: old, with: new)
    }
}
