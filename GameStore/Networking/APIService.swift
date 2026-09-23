import Foundation

enum SortOption: String, CaseIterable {
    case recent
    case exclusive
    case `default`

    /// Target buildURL maps enum tags to backend sort keys.
    var backendValue: String {
        switch self {
        case .recent:
            return "updated_at"
        case .exclusive:
            return "exclusive"
        case .default:
            return "id"
        }
    }
}

protocol APIClient {
    func fetchApps(
        page: Int,
        sortBy: SortOption,
        searchQuery: String?,
        completion: @escaping (Result<AppListResponse, Error>) -> Void
    )
    func checkUDID(_ udid: String, completion: @escaping (Result<Bool, Error>) -> Void)
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

    func fetchApps(
        page: Int = 1,
        sortBy: SortOption = .default,
        searchQuery: String? = nil,
        completion: @escaping (Result<AppListResponse, Error>) -> Void
    ) {
        guard let url = buildAppsURL(page: page, sortBy: sortBy, searchQuery: searchQuery) else {
            completion(.failure(APIError.invalidResponse))
            return
        }

        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60)
        request.httpMethod = "GET"

        // These values are reconstructed from the target fetchApps implementation.
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6", forHTTPHeaderField: "Accept-Language")
        request.setValue("u=1, i", forHTTPHeaderField: "Priority")
        request.setValue("https://www.iosgame.tech/apps/applist/", forHTTPHeaderField: "Referer")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        session.dataTask(with: request) { [decoder] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            do {
                try self.validate(response)
                guard let data = data else {
                    throw APIError.invalidResponse
                }
                completion(.success(try decoder.decode(AppListResponse.self, from: data)))
            } catch let apiError as APIError {
                completion(.failure(apiError))
            } catch {
                completion(.failure(APIError.decoding(error)))
            }
        }.resume()
    }

    private func buildAppsURL(page: Int, sortBy: SortOption, searchQuery: String?) -> URL? {
        var components = URLComponents(
            string: Self.baseURL.absoluteString + "/apps/api/app-list/"
        )

        let timestampMilliseconds = Int(Date().timeIntervalSince1970 * 1000)
        var items = [
            URLQueryItem(name: "page_number", value: String(page)),
            URLQueryItem(name: "sort_by", value: sortBy.backendValue),
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "_", value: String(timestampMilliseconds))
        ]

        if let searchQuery = searchQuery,
           !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "search_query", value: searchQuery))
        }

        components?.queryItems = items
        return components?.url
    }

    func checkUDID(_ udid: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("device/check-udid/"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "udid", value: udid)]
        guard let url = components.url else {
            completion(.failure(APIError.invalidResponse))
            return
        }

        session.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            do {
                try self.validate(response)
                guard let data = data else {
                    throw APIError.invalidResponse
                }
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let valid = (object["valid"] as? Bool)
                        ?? (object["success"] as? Bool)
                        ?? false
                    completion(.success(valid))
                } else {
                    completion(.success(false))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func validate(_ response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverStatus(http.statusCode)
        }
    }
}
