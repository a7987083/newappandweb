import Foundation
import SQLite3

/// Compact, normalized application catalog. Source URLs are stored once per
/// source rather than repeated for every app. All writes are serialized.
enum SourceCatalogCache {
    private struct Snapshot: Codable {
        var schemaVersion: Int
        var catalogs: [String: [SourceCatalogApp]]
    }

    private static let writer = DispatchQueue(label: "gamestore.catalog.persistence", qos: .utility)
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameStore", isDirectory: true)
    }
    private static var databaseURL: URL { directory.appendingPathComponent("SourceCatalog-v3.sqlite") }
    private static var previousURL: URL { directory.appendingPathComponent("SourceCatalog-v2.plist") }
    private static var legacyURL: URL { directory.appendingPathComponent("SourceCatalog-v1.json") }

    static var needsMigration: Bool {
        !hasValidDatabase() &&
        (FileManager.default.fileExists(atPath: previousURL.path) ||
         FileManager.default.fileExists(atPath: legacyURL.path))
    }

    private static func openDatabase() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            if let db = db { sqlite3_close(db) }
            return nil
        }
        sqlite3_busy_timeout(db, 3000)
        return db
    }

    private static func sql(_ db: OpaquePointer, _ command: String) -> Bool {
        sqlite3_exec(db, command, nil, nil, nil) == SQLITE_OK
    }

    private static func prepare(_ db: OpaquePointer, _ command: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, command, -1, &statement, nil) == SQLITE_OK else {
            if let statement = statement { sqlite3_finalize(statement) }
            return nil
        }
        return statement
    }

    private static func bind(_ value: String?, to stmt: OpaquePointer, at index: Int32) {
        guard let value = value else { sqlite3_bind_null(stmt, index); return }
        _ = value.withCString { sqlite3_bind_text(stmt, index, $0, -1, transient) }
    }

    private static func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private static func createSchema(_ db: OpaquePointer) -> Bool {
        sql(db, "CREATE TABLE IF NOT EXISTS sources (id INTEGER PRIMARY KEY, url TEXT NOT NULL UNIQUE)") &&
        sql(db, """
            CREATE TABLE IF NOT EXISTS apps (
                source_id INTEGER NOT NULL,
                position INTEGER NOT NULL,
                app_id TEXT NOT NULL,
                name TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                version TEXT NOT NULL,
                category TEXT NOT NULL,
                description TEXT NOT NULL,
                icon_url TEXT,
                download_url TEXT,
                developer TEXT NOT NULL,
                size_bytes INTEGER,
                updated_at REAL,
                release_notes TEXT NOT NULL,
                PRIMARY KEY (source_id, position)
            )
            """) &&
        sql(db, "CREATE INDEX IF NOT EXISTS idx_apps_name ON apps(name)")
    }

    private static func hasValidDatabase() -> Bool {
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              let db = openDatabase() else { return false }
        defer { sqlite3_close(db) }
        guard let statement = prepare(db, "PRAGMA user_version") else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 3
    }

    private static func loadDatabase() -> [String: [SourceCatalogApp]]? {
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              let db = openDatabase() else { return nil }
        defer { sqlite3_close(db) }
        guard let marker = prepare(db, "PRAGMA user_version") else { return nil }
        let valid = sqlite3_step(marker) == SQLITE_ROW && sqlite3_column_int(marker, 0) == 3
        sqlite3_finalize(marker)
        guard valid, let statement = prepare(db, """
                SELECT s.url,a.app_id,a.name,a.bundle_id,a.version,a.category,
                       a.description,a.icon_url,a.download_url,a.developer,
                       a.size_bytes,a.updated_at,a.release_notes
                FROM apps AS a JOIN sources AS s ON s.id=a.source_id
                ORDER BY a.source_id,a.position
                """) else { return nil }
        defer { sqlite3_finalize(statement) }
        var catalogs: [String: [SourceCatalogApp]] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { return nil }
            let source = string(statement, 0)
            let icon = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : URL(string: string(statement, 7))
            let download = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : URL(string: string(statement, 8))
            let size = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 10)
            let updated = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 11))
            catalogs[source, default: []].append(SourceCatalogApp(
                id: string(statement, 1), sourceURL: source, name: string(statement, 2),
                bundleIdentifier: string(statement, 3), version: string(statement, 4),
                category: string(statement, 5), description: string(statement, 6),
                iconURL: icon, downloadURL: download, developer: string(statement, 9),
                sizeBytes: size, updatedAt: updated, releaseNotes: string(statement, 12),
                requiresUnlock: nil, unlockURL: nil
            ))
        }
        // Preserve registered-but-empty catalogs.
        if let sources = prepare(db, "SELECT url FROM sources") {
            defer { sqlite3_finalize(sources) }
            while sqlite3_step(sources) == SQLITE_ROW {
                let source = string(sources, 0)
                if catalogs[source] == nil { catalogs[source] = [] }
            }
        }
        return catalogs
    }

    static func load() -> [String: [SourceCatalogApp]] {
        if let catalogs = loadDatabase() { return catalogs }
        if let data = try? Data(contentsOf: previousURL),
           let snapshot = try? PropertyListDecoder().decode(Snapshot.self, from: data),
           snapshot.schemaVersion == 2 { return snapshot.catalogs }
        if let data = try? Data(contentsOf: legacyURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
           snapshot.schemaVersion == 1 { return snapshot.catalogs }
        return [:]
    }

    private static func write(_ catalogs: [String: [SourceCatalogApp]]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        guard let db = openDatabase() else { throw storeError("无法打开目录数据库") }
        defer { sqlite3_close(db) }
        guard createSchema(db), sql(db, "BEGIN IMMEDIATE TRANSACTION") else {
            throw storeError("无法启动目录事务")
        }
        var committed = false
        defer { if !committed { _ = sql(db, "ROLLBACK") } }
        guard sql(db, "DELETE FROM apps"), sql(db, "DELETE FROM sources"),
              let sourceStatement = prepare(db, "INSERT INTO sources(url) VALUES (?)"),
              let appStatement = prepare(db, """
                INSERT INTO apps(source_id,position,app_id,name,bundle_id,version,category,
                                 description,icon_url,download_url,developer,size_bytes,updated_at,release_notes)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """) else { throw storeError("准备目录写入失败") }
        defer { sqlite3_finalize(sourceStatement); sqlite3_finalize(appStatement) }
        for (url, apps) in catalogs.sorted(by: { $0.key < $1.key }) {
            sqlite3_reset(sourceStatement)
            sqlite3_clear_bindings(sourceStatement)
            bind(url, to: sourceStatement, at: 1)
            guard sqlite3_step(sourceStatement) == SQLITE_DONE else { throw storeError("软件源写入失败") }
            let sourceID = sqlite3_last_insert_rowid(db)
            for (index, app) in apps.enumerated() {
                sqlite3_reset(appStatement)
                sqlite3_clear_bindings(appStatement)
                sqlite3_bind_int64(appStatement, 1, sourceID)
                sqlite3_bind_int64(appStatement, 2, Int64(index))
                bind(app.id, to: appStatement, at: 3)
                bind(app.name, to: appStatement, at: 4)
                bind(app.bundleIdentifier, to: appStatement, at: 5)
                bind(app.version, to: appStatement, at: 6)
                bind(app.category, to: appStatement, at: 7)
                bind(app.description, to: appStatement, at: 8)
                bind(app.iconURL?.absoluteString, to: appStatement, at: 9)
                bind(app.downloadURL?.absoluteString, to: appStatement, at: 10)
                bind(app.developer, to: appStatement, at: 11)
                if let size = app.sizeBytes { sqlite3_bind_int64(appStatement, 12, size) }
                else { sqlite3_bind_null(appStatement, 12) }
                if let date = app.updatedAt { sqlite3_bind_double(appStatement, 13, date.timeIntervalSince1970) }
                else { sqlite3_bind_null(appStatement, 13) }
                bind(app.releaseNotes, to: appStatement, at: 14)
                guard sqlite3_step(appStatement) == SQLITE_DONE else { throw storeError("应用目录写入失败") }
            }
        }
        guard sql(db, "PRAGMA user_version=3"), sql(db, "COMMIT") else { throw storeError("目录事务提交失败") }
        committed = true
        // Only remove old snapshots after a complete successful transaction.
        try? FileManager.default.removeItem(at: previousURL)
        try? FileManager.default.removeItem(at: legacyURL)
    }

    private static func storeError(_ message: String) -> NSError {
        NSError(domain: "GameStore.SourceCatalogCache", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func save(_ catalogs: [String: [SourceCatalogApp]]) throws {
        try writer.sync { try write(catalogs) }
    }

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
