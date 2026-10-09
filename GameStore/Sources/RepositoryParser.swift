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
        // UnitXP/AltSourceKit canonical model. Do not duplicate its download/version heuristics.
        let object = try JSONSerialization.jsonObject(with: data)
        guard let raw = object as? [String: Any] else { throw Failure.invalidRoot }
        let root = (raw["repository"] as? [String: Any])
            ?? (raw["repo"] as? [String: Any]) ?? raw
        // Preserve UnitXP SourceRepositoryLoader normalization before ASRepository decoding.
        var normalized = root
        if normalized["iconURL"] == nil, let icon = normalized["sourceicon"] {
            normalized["iconURL"] = icon
        }
        if let apps = normalized["apps"] as? [[String: Any]] {
            normalized["apps"] = apps.map { input -> [String: Any] in
                var app = input
                if app["bundleIdentifier"] == nil {
                    app["bundleIdentifier"] = app["identifier"] ?? "zonoe.source.\\(UUID().uuidString)"
                }
                if app["localizedDescription"] == nil {
                    app["localizedDescription"] = app["description"] ?? app["versionDescription"]
                }
                if let size = app["size"] as? String, let number = Double(size) {
                    app["size"] = Int64(number)
                }
                return app
            }
        }
        let normalizedData = try JSONSerialization.data(withJSONObject: normalized)
        let repository = try JSONDecoder().decode(ASRepository.self, from: normalizedData)
        let identity = repository.id ?? sourceURL.absoluteString
        let name = repository.name ?? sourceURL.host ?? "软件源"
        let apps = repository.apps.map { app -> RepositoryApp in
            let bundle = app.id ?? ""
            let displayName = app.currentName
            return RepositoryApp(
                id: sourceURL.absoluteString + "#" + (bundle.isEmpty ? displayName : bundle),
                sourceURL: sourceURL.absoluteString,
                bundleID: bundle,
                name: displayName,
                version: app.currentVersion ?? "",
                subtitle: app.currentDescription ?? "",
                iconURL: app.iconURL,
                downloadURL: app.currentDownloadUrl
            )
        }
        return ParsedRepository(identity: identity, name: name, apps: apps)
    }
}
