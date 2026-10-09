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
