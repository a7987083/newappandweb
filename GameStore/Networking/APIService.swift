import Foundation

protocol APIClient {
    func fetchApps() async throws -> [AppItem]
    func checkUDID(_ udid: String) async throws -> Bool
}

enum APIError: Error {
    case invalidResponse
    case serverStatus(Int)
    case decoding(Error)
}

final class APIService: APIClient {
    static let shared = APIService()
    static let baseURL = URL(string: "https://new.iosgame.vip")!

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchApps() async throws -> [AppItem] {
        let url = Self.baseURL.appendingPathComponent("apps/api/app-list/")
        let (data, response) = try await session.data(from: url)
        try validate(response)
        do {
            if let direct = try? decoder.decode([AppItem].self, from: data) {
                return direct
            }
            return try decoder.decode(AppListResponse.self, from: data).apps
        } catch {
            throw APIError.decoding(error)
        }
    }

    func checkUDID(_ udid: String) async throws -> Bool {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("device/check-udid/"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "udid", value: udid)]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response)

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return (object["valid"] as? Bool)
                ?? (object["success"] as? Bool)
                ?? false
        }
        return false
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverStatus(http.statusCode)
        }
    }
}
