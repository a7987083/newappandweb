import Foundation

struct AppItem: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let developer: String?
    let version: String?
    let iconURL: URL?
    let downloadURL: URL?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case developer
        case version
        case iconURL = "icon"
        case downloadURL = "download_url"
        case summary = "description"
    }
}

struct AppListResponse: Codable {
    let apps: [AppItem]

    enum CodingKeys: String, CodingKey {
        case apps
        case results
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let apps = try? container.decode([AppItem].self, forKey: .apps) {
            self.apps = apps
        } else if let apps = try? container.decode([AppItem].self, forKey: .results) {
            self.apps = apps
        } else if let apps = try? container.decode([AppItem].self, forKey: .data) {
            self.apps = apps
        } else {
            self.apps = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(apps, forKey: .apps)
    }
}
