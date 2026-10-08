import Foundation
import CryptoKit

final class SourceRepositoryLoader {
    static let shared = SourceRepositoryLoader()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(
        from url: URL,
        completion: @escaping (Result<SourceRepository, Error>) -> Void
    ) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            completion(.failure(SourceLoaderError.invalidURL))
            return
        }

        let requestURL = Self.sourceRequestURL(from: url)

        var request = URLRequest(
            url: requestURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("zonoe/0.2", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let http = response as? HTTPURLResponse else {
                completion(.failure(SourceLoaderError.invalidResponse))
                return
            }

            guard (200...299).contains(http.statusCode) else {
                completion(.failure(SourceLoaderError.httpStatus(http.statusCode)))
                return
            }

            guard let data = data, !data.isEmpty else {
                completion(.failure(SourceLoaderError.emptyResponse))
                return
            }

            QNQSourcePayloadDecoder.decode(data) { decodedResult in
                switch decodedResult {
                case .success(let decodedData):
                    do {
                        completion(.success(try Self.decode(decodedData, sourceURL: url)))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    private static func sourceRequestURL(from sourceURL: URL) -> URL {
        let udid = UserDefaults.standard.string(forKey: "zonoe.deviceUDID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !udid.isEmpty,
              var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return sourceURL
        }

        var items = components.queryItems ?? []
        items.removeAll { $0.name.caseInsensitiveCompare("udid") == .orderedSame }
        items.append(URLQueryItem(name: "udid", value: udid))
        components.queryItems = items
        return components.url ?? sourceURL
    }

    static func decode(_ data: Data, sourceURL: URL) throws -> SourceRepository {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            if looksLikeHTML(data) {
                throw SourceLoaderError.htmlResponse
            }
            throw SourceLoaderError.invalidJSON(error.localizedDescription)
        }

        guard let root = repositoryDictionary(from: object) else {
            throw SourceLoaderError.unsupportedFormat
        }

        if root["appstore"] is String || root["appstore_v2"] is String {
            throw SourceLoaderError.encryptedPayloadRequiresDecoder
        }

        let rawApps = appDictionaries(from: root)
        let sourceName = firstString(root, keys: ["name", "title", "repoName", "sourceName"])
            ?? sourceURL.host
            ?? "软件源"
        let identifier = firstString(root, keys: ["identifier", "id", "bundleIdentifier"])
            ?? sourceURL.absoluteString
        let iconURL = firstURL(root, keys: ["iconURL", "icon", "sourceicon", "sourceIcon"])

        let legacy = root["legacy"] as? [String: Any]
        let payURL = firstURL(root, keys: ["payURL", "payUrl", "pay_url"])
            ?? legacy.flatMap { firstURL($0, keys: ["pay", "payURL", "url_pay"]) }
        let unlockURL = firstURL(root, keys: ["unlockURL", "unlockUrl", "unlock_url"])
            ?? legacy.flatMap { firstURL($0, keys: ["url", "unlock", "unlockURL"]) }
        let legacyKey = legacy.flatMap {
            firstString($0, keys: ["key", "legacyKey"])
        }

        let access = SourceAccessMetadata(
            payURL: payURL,
            unlockURL: unlockURL,
            legacyKey: legacyKey
        )

        let apps = rawApps.compactMap { app in
            decodeApp(app, sourceURL: sourceURL)
        }

        return SourceRepository(
            sourceURL: sourceURL,
            identifier: identifier,
            name: sourceName,
            iconURL: iconURL,
            access: access,
            apps: apps
        )
    }

    private static func repositoryDictionary(from object: Any) -> [String: Any]? {
        if let dictionary = object as? [String: Any] {
            if dictionary["apps"] != nil
                || dictionary["applications"] != nil
                || dictionary["appstore"] != nil
                || dictionary["appstore_v2"] != nil {
                return dictionary
            }

            for key in ["repository", "repo", "data", "result"] {
                if let nested = dictionary[key] as? [String: Any],
                   nested["apps"] != nil || nested["applications"] != nil {
                    return nested
                }
            }

            return dictionary
        }
        return nil
    }

    private static func appDictionaries(from root: [String: Any]) -> [[String: Any]] {
        for key in ["apps", "applications", "items"] {
            if let apps = root[key] as? [[String: Any]] {
                return apps
            }
        }

        if let data = root["data"] as? [[String: Any]] {
            return data
        }

        return []
    }

    private static func decodeApp(_ app: [String: Any], sourceURL: URL) -> SourceApp? {
        let name = firstString(app, keys: [
            "name", "localizedName", "appName", "app_name", "title"
        ])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !name.isEmpty else { return nil }

        let identifier = firstString(app, keys: [
            "bundleIdentifier", "identifier", "bundle_id", "bundleID", "packageName", "package_name", "id"
        ]) ?? stableFallbackIdentifier(name: name, sourceURL: sourceURL)

        let currentVersion = firstVersionDictionary(in: app)

        let version = currentVersion.flatMap {
            firstString($0, keys: ["version", "versionCode", "versionName"])
        } ?? firstString(app, keys: [
            "version", "versionCode", "versionName", "current_version", "app_version"
        ])

        let size = currentVersion.flatMap {
            firstInt64($0, keys: ["size", "fileSize", "file_size"])
        } ?? firstInt64(app, keys: [
            "size", "fileSize", "file_size"
        ])

        let downloadURL = currentVersion.flatMap {
            firstURL($0, keys: [
                "downloadURL", "downloadUrl", "download_url", "url", "ipa", "ipaURL",
                "alist_url", "store_url"
            ])
        } ?? firstURL(app, keys: [
            "downloadURL", "downloadUrl", "download_url", "url", "ipa", "ipaURL",
            "alist_url", "store_url"
        ])

        let releaseNotes = currentVersion.flatMap {
            firstString($0, keys: [
                "localizedDescription", "versionDescription", "releaseNotes",
                "release_notes", "whatsNew", "description"
            ])
        } ?? firstString(app, keys: [
            "versionDescription", "releaseNotes", "release_notes", "whatsNew"
        ])

        let summary = firstString(app, keys: [
            "localizedDescription", "description", "desc", "summary", "mod_description"
        ]) ?? releaseNotes

        let minimumOSVersion = currentVersion.flatMap {
            firstString($0, keys: [
                "minOSVersion", "minimumOSVersion", "min_iOS", "support"
            ])
        } ?? firstString(app, keys: [
            "minimumOSVersion", "minOSVersion", "min_iOS", "support"
        ])

        let updatedAt = currentVersion.flatMap {
            firstDate($0, keys: [
                "date", "versionDate", "updatedAt", "updated_at"
            ])
        } ?? firstDate(app, keys: [
            "versionDate", "updatedAt", "updated_at", "date", "mod_update_time"
        ])

        return SourceApp(
            identifier: identifier,
            name: name,
            version: version,
            size: size,
            iconURL: firstURL(app, keys: [
                "iconURL", "icon", "iconUrl", "icon_url", "artworkURL", "artworkUrl"
            ]),
            downloadURL: downloadURL,
            summary: summary,
            releaseNotes: releaseNotes,
            developer: firstString(app, keys: [
                "developerName", "developer", "author", "sellerName", "seller", "package_name"
            ]),
            minimumOSVersion: minimumOSVersion,
            updatedAt: updatedAt,
            access: SourceAppAccessMetadata(
                isNeedLock: firstBool(app, keys: ["isNeedlock", "isNeedLock", "lock"]),
                appType: firstInt(app, keys: ["appType"])
            )
        )
    }

    private static func firstVersionDictionary(in app: [String: Any]) -> [String: Any]? {
        if let versions = app["versions"] as? [[String: Any]], let first = versions.first {
            return first
        }

        if let versions = app["versions"] as? [Any] {
            return versions.compactMap { $0 as? [String: Any] }.first
        }

        return nil
    }

    private static func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key], !(value is NSNull) else { continue }

            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func firstBool(_ dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            guard let value = dictionary[key], !(value is NSNull) else { continue }

            if let bool = value as? Bool { return bool }
            if let number = value as? NSNumber { return number.intValue != 0 }
            if let string = value as? String {
                switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "1", "true", "yes": return true
                case "0", "false", "no": return false
                default: continue
                }
            }
        }
        return nil
    }

    private static func firstInt(_ dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = dictionary[key], !(value is NSNull) else { continue }
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String,
               let number = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return number
            }
        }
        return nil
    }

    private static func firstInt64(_ dictionary: [String: Any], keys: [String]) -> Int64? {
        for key in keys {
            guard let value = dictionary[key], !(value is NSNull) else { continue }

            if let number = value as? NSNumber {
                return Int64(number.doubleValue)
            }

            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if let number = Double(trimmed) {
                    return Int64(number)
                }
            }
        }
        return nil
    }

    private static func firstURL(_ dictionary: [String: Any], keys: [String]) -> URL? {
        guard var value = firstString(dictionary, keys: keys) else { return nil }
        value = value.replacingOccurrences(of: "\\/", with: "/")
        return URL(string: value)
    }

    private static func firstDate(_ dictionary: [String: Any], keys: [String]) -> Date? {
        guard let value = firstString(dictionary, keys: keys) else { return nil }

        if let unix = Double(value) {
            let seconds = unix > 10_000_000_000 ? unix / 1000 : unix
            return Date(timeIntervalSince1970: seconds)
        }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private static func stableFallbackIdentifier(name: String, sourceURL: URL) -> String {
        let seed = sourceURL.absoluteString + "|" + name
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return "zonoe.source." + String(hash, radix: 16)
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(512), encoding: .utf8)?.lowercased() else {
            return false
        }
        return text.contains("<!doctype html") || text.contains("<html")
    }
}

final class SourceUnlockService {
    static let shared = SourceUnlockService()

    private init() {}

    func hasGrant(sourceURL: URL, appIdentifier: String?, appName: String, udid: String) -> Bool {
        guard !udid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return UserDefaults.standard.bool(
            forKey: grantKey(
                sourceURL: sourceURL,
                appIdentifier: appIdentifier,
                appName: appName,
                udid: udid
            )
        )
    }

    func unlock(
        sourceURL: URL,
        unlockURL: URL,
        appIdentifier: String?,
        appName: String,
        udid: String,
        code: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let cleanUDID = udid.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanUDID.isEmpty else {
            completion(.failure(UnlockError.missingUDID))
            return
        }
        guard !cleanCode.isEmpty else {
            completion(.failure(UnlockError.emptyCode))
            return
        }

        guard let activationURL = replacingQueryItems(
            in: unlockURL,
            replacements: [
                URLQueryItem(name: "udid", value: cleanUDID),
                URLQueryItem(name: "code", value: cleanCode)
            ]
        ) else {
            completion(.failure(UnlockError.invalidEndpoint))
            return
        }

        URLSession.shared.dataTask(with: activationURL) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                completion(.failure(UnlockError.http(http.statusCode)))
                return
            }

            guard let data = data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(UnlockError.invalidResponse))
                return
            }

            let message = (object["msg"] as? String)
                ?? (object["message"] as? String)
                ?? ""

            guard message == "ok，解锁成功" else {
                completion(.failure(UnlockError.server(
                    message.isEmpty ? "解锁服务器没有返回有效数据" : message
                )))
                return
            }

            self.verifyGrant(udid: cleanUDID) { verifyResult in
                switch verifyResult {
                case .success:
                    UserDefaults.standard.set(
                        true,
                        forKey: self.grantKey(
                            sourceURL: sourceURL,
                            appIdentifier: appIdentifier,
                            appName: appName,
                            udid: cleanUDID
                        )
                    )
                    completion(.success(()))

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    private func verifyGrant(
        udid: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let endpoint = URL(string: "https://app.zonoeios.xyz/index/index/apiface"),
              let url = replacingQueryItems(
                in: endpoint,
                replacements: [URLQueryItem(name: "udid", value: udid)]
              ) else {
            completion(.failure(UnlockError.invalidEndpoint))
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                completion(.failure(UnlockError.http(http.statusCode)))
                return
            }

            guard let data = data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(UnlockError.invalidResponse))
                return
            }

            let code = Self.intValue(object["code"])
            let message = (object["msg"] as? String) ?? ""
            let expire = Self.doubleValue(object["expire"])

            guard code == 1,
                  message == "ok",
                  let expire = expire,
                  expire > Date().timeIntervalSince1970 else {
                let reason: String
                if let expire = expire, expire <= Date().timeIntervalSince1970 {
                    reason = "解锁授权已过期"
                } else {
                    reason = message.isEmpty ? "解锁状态校验失败" : message
                }
                completion(.failure(UnlockError.server(reason)))
                return
            }

            completion(.success(()))
        }.resume()
    }

    private func grantKey(
        sourceURL: URL,
        appIdentifier: String?,
        appName: String,
        udid: String
    ) -> String {
        let identity: String
        if let appIdentifier = appIdentifier, !appIdentifier.isEmpty {
            identity = "id:\(appIdentifier)"
        } else {
            identity = "name:\(appName)"
        }

        let normalizedSource = sourceURL.absoluteString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = "\(normalizedSource)\n\(udid)\n\(identity)"
        let digest = SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "zonoe.sourceUnlock.\(digest)"
    }

    private func replacingQueryItems(
        in url: URL,
        replacements: [URLQueryItem]
    ) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let names = Set(replacements.map { $0.name.lowercased() })
        var items = (components.queryItems ?? []).filter {
            !names.contains($0.name.lowercased())
        }
        items.append(contentsOf: replacements)
        components.queryItems = items
        return components.url
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> TimeInterval? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return TimeInterval(value) }
        return nil
    }

    enum UnlockError: LocalizedError {
        case missingUDID
        case emptyCode
        case invalidEndpoint
        case invalidResponse
        case http(Int)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingUDID:
                return "请先获取本机 UDID"
            case .emptyCode:
                return "请输入解锁码"
            case .invalidEndpoint:
                return "软件源解锁地址无效"
            case .invalidResponse:
                return "解锁服务器返回了无效数据"
            case .http(let code):
                return "解锁服务器返回 HTTP \(code)"
            case .server(let message):
                return message
            }
        }
    }
}

enum SourceLoaderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case emptyResponse
    case invalidJSON(String)
    case htmlResponse
    case unsupportedFormat
    case encryptedPayloadRequiresDecoder

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "软件源地址无效"
        case .invalidResponse:
            return "软件源返回了无效响应"
        case .httpStatus(let code):
            return "软件源服务器返回 HTTP \(code)"
        case .emptyResponse:
            return "软件源没有返回数据"
        case .invalidJSON(let message):
            return "软件源 JSON 无效：\(message)"
        case .htmlResponse:
            return "服务器返回了网页，而不是软件源 JSON"
        case .unsupportedFormat:
            return "不支持的软件源格式"
        case .encryptedPayloadRequiresDecoder:
            return "该软件源使用 QNQ/全能签加密格式，需下一阶段解码器"
        }
    }
}
