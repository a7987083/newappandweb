import Foundation
import Combine

/// Source registration only. Does not fetch, decode, unlock, or aggregate apps.
final class SoftwareSourceStore: ObservableObject {
    static let shared = SoftwareSourceStore()
    private static let storageKey = "zonoe.sources"

    @Published private(set) var sources: [String]
    @Published private(set) var isLoading = false

    private init() {
        sources = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
    }

    func add(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty else {
            completion(.failure(SoftwareSourceStoreError.invalidURL))
            return
        }
        let value = url.absoluteString
        guard !sources.contains(value) else {
            completion(.failure(SoftwareSourceStoreError.duplicate))
            return
        }
        sources.append(value)
        UserDefaults.standard.set(sources, forKey: Self.storageKey)
        completion(.success(()))
    }
}

enum SoftwareSourceStoreError: LocalizedError {
    case duplicate, invalidURL
    var errorDescription: String? {
        switch self {
        case .duplicate: return "该软件源已经添加。"
        case .invalidURL: return "请输入有效的 HTTP 或 HTTPS 软件源地址。"
        }
    }
}
