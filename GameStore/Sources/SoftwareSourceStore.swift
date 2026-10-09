import Foundation
import Combine

/// Registration-only source manager. Validation must succeed before persistence.
final class SoftwareSourceStore: ObservableObject {
    static let shared = SoftwareSourceStore()
    private static let storageKey = "zonoe.sources"
    private static let identitiesKey = "zonoe.sourceIdentities"
    private static let namesKey = "zonoe.sourceNames"
    private static let catalogKey = "zonoe.sourceCatalog.v1"

    @Published private(set) var sources: [String]
    @Published private(set) var isLoading = false
    @Published private(set) var sourceNames: [String: String]
    @Published private(set) var catalogs: [String: [RepositoryApp]] = [:]
    @Published private(set) var errors: [String: String] = [:]

    private var registeredIdentities: [String: String] = [:]
    private var pendingURLs = Set<String>()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        sources = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        registeredIdentities = UserDefaults.standard.dictionary(forKey: Self.identitiesKey) as? [String: String] ?? [:]
        sourceNames = UserDefaults.standard.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        if let stored = UserDefaults.standard.data(forKey: Self.catalogKey),
           let decoded = try? JSONDecoder().decode([String: [RepositoryApp]].self, from: stored) {
            catalogs = decoded.filter { sources.contains($0.key) }
        }
    }

    func remove(_ value: String) {
        guard let index = sources.firstIndex(of: value) else { return }
        sources.remove(at: index)
        registeredIdentities.removeValue(forKey: value)
        sourceNames.removeValue(forKey: value)
        catalogs.removeValue(forKey: value)
        errors.removeValue(forKey: value)
        saveCatalog()
        UserDefaults.standard.set(sources, forKey: Self.storageKey)
        UserDefaults.standard.set(registeredIdentities, forKey: Self.identitiesKey)
        UserDefaults.standard.set(sourceNames, forKey: Self.namesKey)
    }

    var allApps: [RepositoryApp] {
        sources.flatMap { catalogs[$0] ?? [] }
    }

    private func saveCatalog() {
        if let data = try? JSONEncoder().encode(catalogs) {
            UserDefaults.standard.set(data, forKey: Self.catalogKey)
        }
    }

    func refreshAll() {
        for raw in sources {
            guard let url = URL(string: raw) else { continue }
            load(url) { _ in }
        }
    }

    func load(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        fetch(url, registering: false, completion: completion)
    }

    func add(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        fetch(url, registering: true, completion: completion)
    }

    private func fetch(_ url: URL, registering: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty else {
            completion(.failure(RegistrationError.invalidURL))
            return
        }

        let key = url.absoluteString
        guard (!registering || !sources.contains(key)), !pendingURLs.contains(key) else {
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
            if let error = error { self?.finish(key, result: .failure(error), registering: registering, completion: completion); return }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data = data, !data.isEmpty else {
                self?.finish(key, result: .failure(RegistrationError.badResponse), registering: registering, completion: completion)
                return
            }
            QNQSourcePayloadDecoder.decode(data) { result in
                do {
                    let decoded = try result.get()
                    let parsed = try RepositoryParser.parse(decoded, sourceURL: url)
                    self?.finish(key, result: .success(parsed), registering: registering, completion: completion)
                } catch {
                    self?.finish(key, result: .failure(error), registering: registering, completion: completion)
                }
            }
        }.resume()
    }

    private func finish(
        _ url: String,
        result: Result<ParsedRepository, Error>,
        registering: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            self.pendingURLs.remove(url)
            self.isLoading = !self.pendingURLs.isEmpty
            switch result {
            case .failure(let error):
                self.errors[url] = error.localizedDescription
                completion(.failure(error))
            case .success(let parsed):
                self.errors.removeValue(forKey: url)
                if !registering {
                    guard self.sources.contains(url) else { completion(.failure(RegistrationError.invalidURL)); return }
                    self.sourceNames[url] = parsed.name
                    self.catalogs[url] = parsed.apps
                    self.saveCatalog()
                    UserDefaults.standard.set(self.sourceNames, forKey: Self.namesKey)
                    completion(.success(()))
                    return
                }
                let identity = parsed.identity
                let name = parsed.name
                guard !self.sources.contains(url),
                      !self.registeredIdentities.contains(where: { $0.value == identity && $0.key != url }) else {
                    completion(.failure(RegistrationError.duplicate))
                    return
                }
                self.sources.append(url)
                self.registeredIdentities[url] = identity
                self.sourceNames[url] = name
                self.catalogs[url] = parsed.apps
                self.saveCatalog()
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
