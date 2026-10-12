import Foundation
import Combine

enum SigningState: String, Codable, CaseIterable {
    case idle = "signing_status_idle"
    case prepareContext = "signing_status_prepare_context"
    case verifyCertificate = "signing_status_verify_cert"
    case prepareIPA = "signing_status_prepare_ipa"
    case extracting = "signing_status_extracting"
    case signing = "signing_status_signing"
    case repacking = "signing_status_repacking"
    case verifySignature = "signing_status_verify_sign"
    case waitingForSystemInstall = "signing_status_wait_system_install"
    case installComplete = "signing_status_install_complete"
    case failed = "signing_status_failed"
}

struct DeviceCertificate: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let p12URL: URL?
    let mobileProvisionURL: URL?
}

struct SigningRequest {
    let ipaURL: URL
    let certificate: DeviceCertificate
    let password: String
    var editing: SigningAppEditing = SigningAppEditing()
    var injectedPlugins: [URL] = []
    var removedLoadPaths: [String] = []
    var automaticBuiltIn: Bool = SigningInjectionPreferences.automaticBuiltIn
    var injectionUseRpath: Bool = SigningInjectionPreferences.useRpath
    var injectionFrameworks: Bool = SigningInjectionPreferences.useFrameworksFolder
}

enum IPACompressionPreset: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "快速"
        case .balanced: return "标准"
        case .maximum: return "极限"
        }
    }
}

struct SigningAppEditing {
    var displayName: String? = nil
    var bundleIdentifier: String? = nil
    var version: String? = nil
    var minimumOS: String? = nil
    var removeURLSchemes = false
    var outputFormat: String = "ipa"
    var compressionPreset: IPACompressionPreset = .balanced
    var replacementIconPNG: Data? = nil
}

struct SignedArtifact {
    let ipaURL: URL
    let bundleIdentifier: String
    let displayName: String
    let version: String
}


enum SigningPackagingRule: String, Codable, CaseIterable, Identifiable {
    case standardIPA = "standard_ipa"
    case preserveOriginalFilename = "preserve_original_filename"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standardIPA:
            return "标准 IPA"
        case .preserveOriginalFilename:
            return "保留原文件名"
        }
    }
}

struct SigningOptions: Codable, Equatable {
    var forceLocalization: Bool
    var fileSharing: Bool
    var itunesFileSharing: Bool
    var proMotion: Bool
    var gameMode: Bool
    var ipadFullscreen: Bool

    /// Ad-hoc signing mode; stored with the legacy key for settings compatibility.
    var temporarySigning: Bool

    var autoInstallAfterSigning: Bool
    var registerCallback: Bool
    var packagingRule: SigningPackagingRule

    static let defaultOptions = SigningOptions(
        forceLocalization: false,
        fileSharing: false,
        itunesFileSharing: false,
        proMotion: false,
        gameMode: false,
        ipadFullscreen: false,
        temporarySigning: false,
        autoInstallAfterSigning: false,
        registerCallback: false,
        packagingRule: .standardIPA
    )
}

final class SigningOptionsStore: ObservableObject {
    static let shared = SigningOptionsStore()

    @Published var options: SigningOptions {
        didSet { save() }
    }

    private static let storageKey = "zonoe.signingOptions.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(SigningOptions.self, from: data) {
            self.options = decoded
        } else {
            self.options = .defaultOptions
        }
    }

    func resetToDefaults() {
        options = .defaultOptions
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

// Global persistent injection preferences, independent of legacy SigningOptions decoding.
enum SigningInjectionPreferences {
    private static let pathKey = "zonoe.injection.path.v1"
    private static let folderKey = "zonoe.injection.folder.v1"
    private static let autoKey = "zonoe.injection.builtin.v1"
    static var automaticBuiltIn: Bool {
        get { UserDefaults.standard.bool(forKey: autoKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoKey) }
    }
    static var useRpath: Bool {
        get { UserDefaults.standard.bool(forKey: pathKey) }
        set { UserDefaults.standard.set(newValue, forKey: pathKey) }
    }
    static var useFrameworksFolder: Bool {
        get { UserDefaults.standard.bool(forKey: folderKey) }
        set { UserDefaults.standard.set(newValue, forKey: folderKey) }
    }
}
