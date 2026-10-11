import Foundation

/// Compact binary property-list snapshot with legacy JSON migration.
/// Only complete catalogs are persisted; UI displays cached data immediately.
enum SourceCatalogCache {
    private struct Snapshot: Codable {
        var schemaVersion: Int
        var catalogs: [String: [SourceCatalogApp]]
    }

    private static let writer = DispatchQueue(label: "gamestore.catalog.persistence", qos: .utility)

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameStore", isDirectory: true)
    }

    private static var location: URL {
        directory.appendingPathComponent("SourceCatalog-v2.plist")
    }

    private static var legacyLocation: URL {
        directory.appendingPathComponent("SourceCatalog-v1.json")
    }

    static func load() -> [String: [SourceCatalogApp]] {
        if let data = try? Data(contentsOf: location),
           let snapshot = try? PropertyListDecoder().decode(Snapshot.self, from: data),
           snapshot.schemaVersion == 2 {
            return snapshot.catalogs
        }
        // Keep existing installations populated during the format upgrade.
        guard let data = try? Data(contentsOf: legacyLocation),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.schemaVersion == 1 else { return [:] }
        return snapshot.catalogs
    }

    private static func write(_ catalogs: [String: [SourceCatalogApp]]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(Snapshot(schemaVersion: 2, catalogs: catalogs))
        try data.write(to: location, options: .atomic)
        // Delete the old format only after the new file is safely written.
        try? FileManager.default.removeItem(at: legacyLocation)
    }

    /// Called for explicit source removal; serialization is ordered after queued updates.
    static func save(_ catalogs: [String: [SourceCatalogApp]]) throws {
        try writer.sync { try write(catalogs) }
    }

    /// Don't block the main thread encoding thousands of apps after refresh.
    static func saveAsync(_ catalogs: [String: [SourceCatalogApp]],
                          completion: @escaping (Error?) -> Void) {
        writer.async {
            let failure: Error?
            do { try write(catalogs); failure = nil }
            catch { failure = error }
            DispatchQueue.main.async { completion(failure) }
        }
    }
}
