import Foundation

/// Clean-room protocol model for the target `/apps/api/app-list/` payload.
///
/// Static target evidence identifies the server keys below. UI-facing computed
/// properties keep the rest of the app decoupled from the wire schema.
struct AppItem: Identifiable, Codable, Hashable {
    let appID: Int
    let appName: String
    let modDescription: String?
    let icon: String?
    let storeURL: String?
    let appStoreURL: String?
    let packageName: String?
    let currentVersion: String?
    let appVersion: String?
    let modUpdateTime: String?
    let fileSize: String?
    let screenshots: [String]
    let alistURL: String?
    let isPermanentVIPOnly: Bool
    let isHot: Bool

    var id: Int { appID }

    // UI-facing compatibility surface.
    var name: String { appName }
    var developer: String? { packageName }
    var version: String? { currentVersion ?? appVersion }
    var iconURL: URL? { Self.cleanURL(icon) }
    var downloadURL: URL? { Self.cleanURL(alistURL ?? storeURL) }
    var summary: String? { modDescription }

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case legacyID = "id"
        case appName = "app_name"
        case modDescription = "mod_description"
        case icon
        case storeURL = "store_url"
        case appStoreURL = "appstore_url"
        case packageName = "package_name"
        case currentVersion = "current_version"
        case appVersion = "app_version"
        case modUpdateTime = "mod_update_time"
        case fileSize = "file_size"
        case screenshots
        case alistURL = "alist_url"
        case isPermanentVIPOnly = "is_permanent_vip_only"
        case isHot = "is_hot"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = Self.decodeInt(container, key: .appID)
            ?? Self.decodeInt(container, key: .legacyID) {
            appID = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.appID,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Both app_id and id are missing."
                )
            )
        }

        appName = (try? container.decode(String.self, forKey: .appName)) ?? ""
        modDescription = Self.decodeString(container, key: .modDescription)
        icon = Self.decodeString(container, key: .icon)
        storeURL = Self.decodeString(container, key: .storeURL)
        appStoreURL = Self.decodeString(container, key: .appStoreURL)
        packageName = Self.decodeString(container, key: .packageName)
        currentVersion = Self.decodeString(container, key: .currentVersion)
        appVersion = Self.decodeString(container, key: .appVersion)
        modUpdateTime = Self.decodeString(container, key: .modUpdateTime)
        fileSize = Self.decodeString(container, key: .fileSize)
        screenshots = (try? container.decode([String].self, forKey: .screenshots)) ?? []
        alistURL = Self.decodeString(container, key: .alistURL)
        isPermanentVIPOnly = Self.decodeBool(container, key: .isPermanentVIPOnly) ?? false
        isHot = Self.decodeBool(container, key: .isHot) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appID, forKey: .appID)
        try container.encode(appName, forKey: .appName)
        try container.encodeIfPresent(modDescription, forKey: .modDescription)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(storeURL, forKey: .storeURL)
        try container.encodeIfPresent(appStoreURL, forKey: .appStoreURL)
        try container.encodeIfPresent(packageName, forKey: .packageName)
        try container.encodeIfPresent(currentVersion, forKey: .currentVersion)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        try container.encodeIfPresent(modUpdateTime, forKey: .modUpdateTime)
        try container.encodeIfPresent(fileSize, forKey: .fileSize)
        try container.encode(screenshots, forKey: .screenshots)
        try container.encodeIfPresent(alistURL, forKey: .alistURL)
        try container.encode(isPermanentVIPOnly, forKey: .isPermanentVIPOnly)
        try container.encode(isHot, forKey: .isHot)
    }

    private static func decodeInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    private static func decodeBool(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Bool? {
        if let value = try? container.decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? container.decode(String.self, forKey: key) {
            switch value.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }

    private static func cleanURL(_ value: String?) -> URL? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        value = value.replacingOccurrences(of: "\\/", with: "/")
        return URL(string: value)
    }
}

struct AppListResponse: Codable {
    let data: [AppItem]
    let currentPage: Int
    let totalPages: Int

    var apps: [AppItem] { data }

    enum CodingKeys: String, CodingKey {
        case data
        case currentPage = "current_page"
        case totalPages = "total_pages"
    }
}
