import Foundation

struct RepositoryApp: Codable, Identifiable {
    let id: String
    let sourceURL: String
    let bundleID: String
    let name: String
    let version: String
    let subtitle: String
    let iconURL: URL?
    let downloadURL: URL?
}

struct ParsedRepository {
    let identity: String
    let name: String
    let apps: [RepositoryApp]
}

enum RepositoryParser {
    enum Failure: LocalizedError {
        case invalidRoot, missingApps
        var errorDescription: String? {
            switch self {
            case .invalidRoot: return "软件源 JSON 顶层格式无效"
            case .missingApps: return "未发现有效的 apps 或 applications 字段"
            }
        }
    }

    static func parse(_ data: Data, sourceURL: URL) throws -> ParsedRepository {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.invalidRoot
        }
        let root = (object["repository"] as? [String: Any])
            ?? (object["repo"] as? [String: Any]) ?? object
        guard let rawApps = (root["apps"] as? [Any]) ?? (root["applications"] as? [Any]) else {
            throw Failure.missingApps
        }
        let identity = string(root, ["identifier", "id"]) ?? sourceURL.absoluteString
        let name = string(root, ["name", "title"]) ?? sourceURL.host ?? "软件源"
        var apps: [RepositoryApp] = []
        var seen = Set<String>()
        for value in rawApps {
            guard let item = value as? [String: Any] else { continue }
            let bundle = string(item, ["bundleIdentifier", "bundleID", "bundleId", "identifier", "packageName"]) ?? ""
            let appName = string(item, ["name", "title", "appName"]) ?? bundle
            guard !appName.isEmpty else { continue }
            let versionObject = (item["versions"] as? [[String: Any]])?.first
            let version = string(item, ["version", "versionName"]) ?? versionObject.flatMap { string($0, ["version", "versionName"]) } ?? ""
            let link = string(item, ["downloadURL", "downloadUrl", "download", "url", "ipaURL", "ipa"]) ??
                versionObject.flatMap { string($0, ["downloadURL", "downloadUrl", "download", "url"]) }
            let icon = string(item, ["iconURL", "iconUrl", "icon", "iconPath", "image"])
            let key = bundle.isEmpty ? appName : bundle
            guard seen.insert(key).inserted else { continue }
            apps.append(RepositoryApp(
                id: sourceURL.absoluteString + "#" + key,
                sourceURL: sourceURL.absoluteString,
                bundleID: bundle,
                name: appName,
                version: version,
                subtitle: string(item, ["subtitle", "description", "summary"]) ?? "",
                iconURL: resolve(icon, against: sourceURL),
                downloadURL: resolve(link, against: sourceURL)
            ))
        }
        return ParsedRepository(identity: identity, name: name, apps: apps)
    }

    private static func string(_ object: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { return clean }
            }
        }
        return nil
    }

    private static func resolve(_ raw: String?, against source: URL) -> URL? {
        guard let raw = raw, let url = URL(string: raw, relativeTo: source)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}
