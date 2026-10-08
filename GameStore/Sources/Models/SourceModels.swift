import Foundation

struct SourceAccessMetadata: Equatable {
    let payURL: URL?
    let unlockURL: URL?
    let legacyKey: String?
}

struct SourceAppAccessMetadata: Equatable {
    let isNeedLock: Bool?
    let appType: Int?
}

struct SourceRepository: Equatable {
    let sourceURL: URL
    let identifier: String
    let name: String
    let iconURL: URL?
    let access: SourceAccessMetadata
    let apps: [SourceApp]
}

struct SourceApp: Equatable {
    let identifier: String
    let name: String
    let version: String?
    let size: Int64?
    let iconURL: URL?
    let downloadURL: URL?
    let summary: String?
    let releaseNotes: String?
    let developer: String?
    let minimumOSVersion: String?
    let updatedAt: Date?
    let access: SourceAppAccessMetadata
}
