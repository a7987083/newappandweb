import Foundation

/// Versioned, atomic local catalog snapshot; never stores credentials.
enum SourceCatalogCache {
    private struct Snapshot: Codable {
        var schemaVersion: Int
        var catalogs: [String: [SourceCatalogApp]]
    }
    private static var location: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("GameStore/SourceCatalog-v1.json")
    }
    static func load() -> [String: [SourceCatalogApp]] {
        guard let data = try? Data(contentsOf: location),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.schemaVersion == 1 else { return [:] }
        return snapshot.catalogs
    }
    static func save(_ catalogs: [String: [SourceCatalogApp]]) throws {
        let url = location
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true, attributes: nil)
        let data = try JSONEncoder().encode(Snapshot(schemaVersion: 1, catalogs: catalogs))
        try data.write(to: url, options: .atomic)
    }
}
