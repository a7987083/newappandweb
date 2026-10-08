import Foundation
import Combine

final class SoftwareSourceStore: ObservableObject {
    static let shared = SoftwareSourceStore()

    private static let storageKey = "zonoe.sources"

    @Published private(set) var sources: [String]
    @Published private(set) var repositories: [SourceRepository] = []
    @Published private(set) var apps: [AppItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let loader: SourceRepositoryLoader
    private var loadGeneration = 0

    init(loader: SourceRepositoryLoader = .shared) {
        self.loader = loader
        self.sources = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        reloadAll()
    }

    func add(
        _ url: URL,
        completion: @escaping (Result<SourceRepository, Error>) -> Void
    ) {
        let normalized = url.absoluteString
        guard !sources.contains(normalized) else {
            completion(.failure(SoftwareSourceStoreError.duplicate))
            return
        }

        isLoading = true
        errorMessage = nil

        loader.fetch(from: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                switch result {
                case .success(let repository):
                    var updatedSources = self.sources
                    updatedSources.append(normalized)
                    self.sources = updatedSources
                    UserDefaults.standard.set(updatedSources, forKey: Self.storageKey)

                    var updatedRepositories = self.repositories
                    updatedRepositories.append(repository)
                    self.repositories = updatedRepositories
                    self.rebuildApps(from: updatedRepositories)
                    self.errorMessage = nil
                    completion(.success(repository))

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    func remove(at offsets: IndexSet) {
        let removedURLs = offsets.compactMap { index in
            sources.indices.contains(index) ? sources[index] : nil
        }

        var updated = sources
        updated.remove(atOffsets: offsets)
        sources = updated
        UserDefaults.standard.set(updated, forKey: Self.storageKey)

        repositories.removeAll { removedURLs.contains($0.sourceURL.absoluteString) }
        rebuildApps(from: repositories)
    }

    func reloadAll() {
        let urls = sources.compactMap(URL.init(string:))
        loadGeneration &+= 1
        let generation = loadGeneration

        guard !urls.isEmpty else {
            repositories = []
            apps = []
            isLoading = false
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        let group = DispatchGroup()
        let lock = NSLock()
        var loaded: [SourceRepository] = []
        var firstError: Error?

        for url in urls {
            group.enter()
            loader.fetch(from: url) { result in
                lock.lock()
                switch result {
                case .success(let repository):
                    loaded.append(repository)
                case .failure(let error):
                    if firstError == nil { firstError = error }
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, generation == self.loadGeneration else { return }
            let sortedRepositories = loaded.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            self.repositories = sortedRepositories
            self.rebuildApps(from: sortedRepositories)
            self.isLoading = false
            self.errorMessage = firstError?.localizedDescription
        }
    }

    private func rebuildApps(from repositories: [SourceRepository]) {
        let snapshot = repositories
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var seen = Set<String>()
            var mapped: [AppItem] = []
            mapped.reserveCapacity(snapshot.reduce(0) { $0 + $1.apps.count })

            for repository in snapshot {
                for sourceApp in repository.apps {
                    let identity = sourceApp.identifier.lowercased()
                    guard seen.insert(identity).inserted else { continue }
                    mapped.append(Self.makeAppItem(from: sourceApp))
                }
            }

            mapped.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.apps = mapped
            }
        }
    }

    private static let sourceDateFormatter: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    private static func makeAppItem(from app: SourceApp) -> AppItem {
        AppItem(
            appID: stableIntegerID(app.identifier),
            appName: app.name,
            modDescription: app.summary ?? app.releaseNotes,
            icon: app.iconURL?.absoluteString,
            storeURL: app.downloadURL?.absoluteString,
            appStoreURL: nil,
            packageName: app.identifier,
            currentVersion: app.version,
            appVersion: app.version,
            modUpdateTime: app.updatedAt.map { sourceDateFormatter.string(from: $0) },
            fileSize: app.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
            screenshots: [],
            alistURL: app.downloadURL?.absoluteString,
            isPermanentVIPOnly: false,
            isHot: false
        )
    }

    private static func stableIntegerID(_ value: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Int(hash & 0x7fff_ffff)
    }
}

enum SoftwareSourceStoreError: LocalizedError {
    case duplicate

    var errorDescription: String? {
        switch self {
        case .duplicate:
            return "该软件源已经添加。"
        }
    }
}
