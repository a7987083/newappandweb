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
    let currentPage: Int?
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case apps
        case items
        case results
        case data
        case currentPage = "current_page"
        case totalPages = "total_pages"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try? container.decode([AppItem].self, forKey: .items) {
            apps = value
        } else if let value = try? container.decode([AppItem].self, forKey: .apps) {
            apps = value
        } else if let value = try? container.decode([AppItem].self, forKey: .results) {
            apps = value
        } else if let value = try? container.decode([AppItem].self, forKey: .data) {
            apps = value
        } else {
            apps = []
        }

        currentPage = try? container.decode(Int.self, forKey: .currentPage)
        totalPages = try? container.decode(Int.self, forKey: .totalPages)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(apps, forKey: .items)
        try container.encodeIfPresent(currentPage, forKey: .currentPage)
        try container.encodeIfPresent(totalPages, forKey: .totalPages)
    }
}
