import Foundation
import Combine

/// Registration-only source manager. Validation must succeed before persistence.
final class SoftwareSourceStore: ObservableObject {
    static let shared = SoftwareSourceStore()
    private static let storageKey = "zonoe.sources"
    private static let identitiesKey = "zonoe.sourceIdentities"
    private static let namesKey = "zonoe.sourceNames"

    @Published private(set) var sources: [String]
    @Published private(set) var isLoading = false
    @Published fileprivate(set) var catalogApps: [SourceCatalogApp] = []
    @Published fileprivate(set) var isCatalogLoading = false
    @Published fileprivate(set) var catalogError: String?
    @Published private(set) var sourceNames: [String: String]

    private var registeredIdentities: [String: String] = [:]
    private var pendingURLs = Set<String>()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        sources = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        registeredIdentities = UserDefaults.standard.dictionary(forKey: Self.identitiesKey) as? [String: String] ?? [:]
        sourceNames = UserDefaults.standard.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
    }

    func remove(_ value: String) {
        guard let index = sources.firstIndex(of: value) else { return }
        sources.remove(at: index)
        registeredIdentities.removeValue(forKey: value)
        sourceNames.removeValue(forKey: value)
        UserDefaults.standard.set(sources, forKey: Self.storageKey)
        UserDefaults.standard.set(registeredIdentities, forKey: Self.identitiesKey)
        UserDefaults.standard.set(sourceNames, forKey: Self.namesKey)
        catalogApps.removeAll { $0.sourceURL == value }
    }

    func add(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty else {
            completion(.failure(RegistrationError.invalidURL))
            return
        }

        let key = url.absoluteString
        guard !sources.contains(key), !pendingURLs.contains(key) else {
            completion(.failure(RegistrationError.duplicate))
            return
        }
        pendingURLs.insert(key)
        isLoading = true

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let currentUDID = UDIDService.shared.udid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !currentUDID.isEmpty {
            var items = components?.queryItems ?? []
            items.removeAll { $0.name.caseInsensitiveCompare("udid") == .orderedSame }
            items.append(URLQueryItem(name: "udid", value: currentUDID))
            components?.queryItems = items
        }

        var request = URLRequest(url: components?.url ?? url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error { self?.finish(key, result: .failure(error), completion: completion); return }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data = data, !data.isEmpty else {
                self?.finish(key, result: .failure(RegistrationError.badResponse), completion: completion)
                return
            }
            QNQSourcePayloadDecoder.decode(data) { result in
                do {
                    let decoded = try result.get()
                    guard let dictionary = try JSONSerialization.jsonObject(with: decoded) as? [String: Any] else {
                        throw RegistrationError.badResponse
                    }
                    let root = (dictionary["repository"] as? [String: Any])
                        ?? (dictionary["repo"] as? [String: Any])
                        ?? dictionary
                    guard root["apps"] is [Any] || root["applications"] is [Any] else {
                        throw RegistrationError.unsupported
                    }
                    let rawID = (root["identifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let id = rawID?.isEmpty == false ? rawID! : key
                    let rawName = (root["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = rawName?.isEmpty == false ? rawName! : (url.host ?? "软件源")
                    self?.finish(key, result: .success((id, name)), completion: completion)
                } catch {
                    self?.finish(key, result: .failure(error), completion: completion)
                }
            }
        }.resume()
    }

    private func finish(
        _ url: String,
        result: Result<(String, String), Error>,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            self.pendingURLs.remove(url)
            self.isLoading = !self.pendingURLs.isEmpty
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let (identity, name)):
                guard !self.sources.contains(url),
                      !self.registeredIdentities.contains(where: { $0.value == identity && $0.key != url }) else {
                    completion(.failure(RegistrationError.duplicate))
                    return
                }
                self.sources.append(url)
                self.registeredIdentities[url] = identity
                self.sourceNames[url] = name
                UserDefaults.standard.set(self.sources, forKey: Self.storageKey)
                UserDefaults.standard.set(self.registeredIdentities, forKey: Self.identitiesKey)
                UserDefaults.standard.set(self.sourceNames, forKey: Self.namesKey)
                self.refreshCatalog()
                completion(.success(()))
            }
        }
    }
}

private enum RegistrationError: LocalizedError {
    case invalidURL, duplicate, badResponse, unsupported
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入有效的 HTTP 或 HTTPS 软件源地址。"
        case .duplicate: return "该软件源已经添加。"
        case .badResponse: return "软件源网络响应无效。"
        case .unsupported: return "该地址未返回有效的软件源仓库数据。"
        }
    }
}


struct SourceCatalogApp: Identifiable {
    let id: String
    let sourceURL: String
    let name: String
    let bundleIdentifier: String
    let version: String
    let category: String
    let description: String
    let iconURL: URL?
    let downloadURL: URL?
    let developer: String
}

extension SoftwareSourceStore {
    // Decode and publish complete catalogs, not just registration metadata.
    func refreshCatalog() {
        let registered = sources
        guard !registered.isEmpty else {
            catalogApps = []
            catalogError = nil
            return
        }
        isCatalogLoading = true
        catalogError = nil
        let group = DispatchGroup()
        let lock = NSLock()
        var collected = [SourceCatalogApp]()
        var failures = [String]()
        for source in registered {
            guard let originalURL = URL(string: source) else { continue }
            group.enter()
            var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
            let udid = UDIDService.shared.udid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !udid.isEmpty {
                var items = components?.queryItems ?? []
                items.removeAll { $0.name.caseInsensitiveCompare("udid") == .orderedSame }
                items.append(URLQueryItem(name: "udid", value: udid))
                components?.queryItems = items
            }
            var request = URLRequest(url: components?.url ?? originalURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 40)
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            session.dataTask(with: request) { data, response, error in
                defer { group.leave() }
                guard error == nil, let response = response as? HTTPURLResponse,
                      (200...299).contains(response.statusCode), let data = data else {
                    lock.lock(); failures.append(source); lock.unlock()
                    return
                }
                let decodeGroup = DispatchSemaphore(value: 0)
                QNQSourcePayloadDecoder.decode(data) { result in
                    defer { decodeGroup.signal() }
                    do {
                        let decoded = try result.get()
                        let entries = try Self.parseCatalog(decoded, source: source, baseURL: originalURL)
                        lock.lock(); collected.append(contentsOf: entries); lock.unlock()
                    } catch {
                        lock.lock(); failures.append(source + ": " + error.localizedDescription); lock.unlock()
                    }
                }
                // Legacy decoding may perform async key retrieval; never wait on main.
                decodeGroup.wait()
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // Ignore responses from a previous refresh when registration changed.
            self.catalogApps = collected.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.catalogError = failures.isEmpty ? nil : "\(failures.count) 个软件源加载失败，可下拉刷新重试"
            self.isCatalogLoading = false
        }
    }

    private static func parseCatalog(_ data: Data, source: String, baseURL: URL) throws -> [SourceCatalogApp] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let normalized = ZonoeSourceURLNormalizer.normalizeURLs(json)
        guard let normalizedJSON = normalized as? [String: Any] else { return [] }
        let root = (normalizedJSON["repository"] as? [String: Any]) ?? (normalizedJSON["repo"] as? [String: Any]) ?? normalizedJSON
        let entries = (root["apps"] as? [[String: Any]]) ?? (root["applications"] as? [[String: Any]]) ?? []
        return entries.enumerated().compactMap { index, app in
            func value(_ dictionary: [String: Any], _ keys: [String]) -> String {
                for key in keys {
                    if let s = dictionary[key] as? String,
                       !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
                    if let n = dictionary[key] as? NSNumber { return n.stringValue }
                }
                return ""
            }
            func resolvedURL(_ raw: String) -> URL? {
                guard let normalized = ZonoeSourceURLNormalizer.tolerantURLString(raw),
                      let url = URL(string: normalized, relativeTo: baseURL)?.absoluteURL,
                      let scheme = url.scheme?.lowercased(),
                      (scheme == "http" || scheme == "https"),
                      url.host != nil else { return nil }
                return url
            }
            // AltStore-style repositories expose the link on the app;
            // some source protocols expose it on each version instead.
            let urlKeys = ["downloadURL", "downloadUrl", "download_url",
                           "downloadLink", "download_link", "download",
                           "ipaURL", "ipaUrl", "ipa_url", "ipa", "url"]
            let versions = app["versions"] as? [[String: Any]] ?? []
            let preferredVersion = value(app, ["version", "versionName", "shortVersion", "versionCode"])
            let matchingVersion = versions.first {
                !preferredVersion.isEmpty &&
                value($0, ["version", "versionName", "versionCode"]) == preferredVersion
            }
            let latest = matchingVersion ?? versions.first
            let nestedDownload = latest.map { value($0, urlKeys) } ?? ""
            let topDownload = value(app, urlKeys)
            let download = resolvedURL(nestedDownload) ?? resolvedURL(topDownload)
            let name = value(app, ["name", "title", "appName"])
            guard !name.isEmpty else { return nil }
            let bundle = value(app, ["bundleIdentifier", "bundleID", "bundleId", "identifier"])
            let versionString = latest.map { value($0, ["version", "versionName", "versionCode"]) } ?? ""
            let icon = value(app, ["iconURL", "icon", "iconUrl", "icon_url"])
            return SourceCatalogApp(
                id: source + "#" + (bundle.isEmpty ? String(index) : bundle),
                sourceURL: source,
                name: name,
                bundleIdentifier: bundle,
                version: preferredVersion.isEmpty ? versionString : preferredVersion,
                category: value(app, ["category", "categoryName", "type"]),
                description: value(app, ["localizedDescription", "description", "desc", "subtitle"]),
                iconURL: resolvedURL(icon),
                downloadURL: download,
                developer: value(app, ["developerName", "developer", "author", "sellerName"])
            )
        }
    }
}

 
// Ported from zonoe v3.0.0 SourceRepositoryLoader URL normalization pipeline.
private enum ZonoeSourceURLNormalizer {
    static func normalizeURLs(_ value: Any, key: String? = nil, path: String = "") -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                let childPath = path.isEmpty ? pair.key : "\(path).\(pair.key)"
                result[pair.key] = normalizeURLs(pair.value, key: pair.key, path: childPath)
            }
        }
        if let array = value as? [Any] {
            let normalized = array.enumerated().map {
                normalizeURLs($0.element, key: key, path: "\(path)[\($0.offset)]")
            }
            return isURLKey(key) ? normalized.filter { !($0 is NSNull) } : normalized
        }
        guard let string = value as? String, isURLKey(key) else { return value }
        return tolerantURLString(string) ?? NSNull() as Any
    }

    private static func isURLKey(_ key: String?) -> Bool {
        key?.range(of: "url", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func tolerantURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme, !scheme.isEmpty,
           let url = components.url {
            return url.absoluteString
        }
        guard let repaired = repairURLString(trimmed),
              let components = URLComponents(string: repaired),
              let scheme = components.scheme, !scheme.isEmpty,
              let url = components.url else { return nil }
        return url.absoluteString
    }

    private static func repairURLString(_ raw: String) -> String? {
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let scheme = String(raw[..<colon])
        guard scheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil else { return nil }
        var remainder = String(raw[raw.index(after: colon)...])
        var fragment: String?
        if let hash = remainder.firstIndex(of: "#") {
            fragment = String(remainder[remainder.index(after: hash)...])
            remainder = String(remainder[..<hash])
        }
        var query: String?
        if let question = remainder.firstIndex(of: "?") {
            query = String(remainder[remainder.index(after: question)...])
            remainder = String(remainder[..<question])
        }
        var repaired = scheme + ":"
        if remainder.hasPrefix("//") {
            let hierarchical = String(remainder.dropFirst(2))
            let slash = hierarchical.firstIndex(of: "/")
            let authority = slash.map { String(hierarchical[..<$0]) } ?? hierarchical
            let path = slash.map { String(hierarchical[$0...]) } ?? ""
            guard !authority.isEmpty else { return nil }
            repaired += "//" + percentEncode(authority, allowed: authorityAllowed)
            repaired += percentEncode(path, allowed: pathAllowed)
        } else {
            repaired += percentEncode(remainder, allowed: pathAllowed)
        }
        if let query = query { repaired += "?" + percentEncode(query, allowed: queryAllowed) }
        if let fragment = fragment { repaired += "#" + percentEncode(fragment, allowed: fragmentAllowed) }
        return repaired
    }

    private static var authorityAllowed: CharacterSet {
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@[]")
    }
    private static var pathAllowed: CharacterSet {
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/")
    }
    private static var queryAllowed: CharacterSet {
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/?")
    }
    private static var fragmentAllowed: CharacterSet { queryAllowed }
    private static func percentEncode(_ value: String, allowed: CharacterSet) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "%" {
                let first = value.index(after: index)
                if first < value.endIndex {
                    let second = value.index(after: first)
                    if second < value.endIndex,
                       "0123456789abcdefABCDEF".contains(value[first]),
                       "0123456789abcdefABCDEF".contains(value[second]) {
                        result.append(contentsOf: value[index...second])
                        index = value.index(after: second)
                        continue
                    }
                }
            }
            let next = value.index(after: index)
            let token = String(value[index..<next])
            result += token.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            index = next
        }
        return result
    }
}
