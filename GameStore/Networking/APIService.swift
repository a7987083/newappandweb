import Foundation

protocol APIClient {
    func fetchApps(completion: @escaping (Result<[AppItem], Error>) -> Void)
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

    func fetchApps(completion: @escaping (Result<[AppItem], Error>) -> Void) {
        let url = Self.baseURL.appendingPathComponent("apps/api/app-list/")
        session.dataTask(with: url) { [decoder] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            do {
                try self.validate(response)
                guard let data = data else {
                    throw APIError.invalidResponse
                }
                if let direct = try? decoder.decode([AppItem].self, from: data) {
                    completion(.success(direct))
                    return
                }
                completion(.success(try decoder.decode(AppListResponse.self, from: data).apps))
            } catch let apiError as APIError {
                completion(.failure(apiError))
            } catch {
                completion(.failure(APIError.decoding(error)))
            }
        }.resume()
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
