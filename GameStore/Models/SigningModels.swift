import Foundation

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
}

struct SignedArtifact {
    let ipaURL: URL
    let bundleIdentifier: String
    let displayName: String
    let version: String
}
