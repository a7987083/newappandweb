import Foundation
import Combine

/// Single owner of source snapshots and their derived App list.
/// All state transitions happen on main; background loader results carry an epoch.
final class SoftwareSourceStore: ObservableObject {
    static let shared = SoftwareSourceStore()
    private static let storageKey = "zonoe.sources"
    static let sourceUnlocked = Notification.Name("zonoe.sourceUnlocked")

    @Published private(set) var sources: [String]
    @Published private(set) var repositories: [SourceRepository] = []
    @Published private(set) var apps: [AppItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let loader: SourceRepositoryLoader
    private var snapshots: [String: SourceRepository] = [:]
    private var sourceEpochs: [String: Int] = [:]
    private var pending = Set<String>()
    private var observer: NSObjectProtocol?

    init(loader: SourceRepositoryLoader = .shared) {
        self.loader = loader
        sources = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        observer = NotificationCenter.default.addObserver(
            forName: Self.sourceUnlocked, object: nil, queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            self?.reload(sourceURL: url)
        }
        reloadAll()
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    func add(_ url: URL, completion: @escaping (Result<SourceRepository, Error>) -> Void) {
        let key = url.absoluteString
        guard !sources.contains(key) else {
            completion(.failure(SoftwareSourceStoreError.duplicate))
            return
        }
        fetch(url, requireRegistered: false) { [weak self] result in
            guard let self = self else { return }
            if case .success(let repository) = result, !self.sources.contains(key) {
                self.sources.append(key)
                UserDefaults.standard.set(self.sources, forKey: Self.storageKey)
                self.snapshots[key] = repository
                self.publishSnapshots()
            }
            completion(result)
        }
    }

    func remove(at offsets: IndexSet) {
        let removed = offsets.compactMap { sources.indices.contains($0) ? sources[$0] : nil }
        sources.remove(atOffsets: offsets)
        UserDefaults.standard.set(sources, forKey: Self.storageKey)
        for key in removed {
            sourceEpochs[key, default: 0] &+= 1
            snapshots.removeValue(forKey: key)
            pending.remove(key)
        }
        isLoading = !pending.isEmpty
        errorMessage = nil
        publishSnapshots()
    }

    func reloadAll() {
        for key in sources {
            guard let url = URL(string: key) else { continue }
            fetch(url, requireRegistered: true, completion: nil)
        }
        if sources.isEmpty {
            snapshots.removeAll()
            pending.removeAll()
            isLoading = false
            errorMessage = nil
            publishSnapshots()
        }
    }

    /// A successful unlock only refreshes the originating source.
    func reload(sourceURL: URL) {
        guard sources.contains(sourceURL.absoluteString) else { return }
        fetch(sourceURL, requireRegistered: true, completion: nil)
    }

    private func fetch(
        _ url: URL,
        requireRegistered: Bool,
        completion: ((Result<SourceRepository, Error>) -> Void)?
    ) {
        let key = url.absoluteString
        sourceEpochs[key, default: 0] &+= 1
        let epoch = sourceEpochs[key]!
        pending.insert(key)
        isLoading = true
        errorMessage = nil

        loader.fetch(from: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.sourceEpochs[key] == epoch else { return }
                self.pending.remove(key)
                self.isLoading = !self.pending.isEmpty
                if requireRegistered && !self.sources.contains(key) { return }

                switch result {
                case .success(let repository):
                    if requireRegistered {
                        self.snapshots[key] = repository
                        self.publishSnapshots()
                    }
                case .failure(let error):
                    // Retain the last successful snapshot; never replace it with an empty one.
                    self.errorMessage = error.localizedDescription
                }
                completion?(result)
            }
        }
    }

    private func publishSnapshots() {
        repositories = sources.compactMap { snapshots[$0] }
        var seen = Set<String>()
        var mapped: [AppItem] = []
        for repository in repositories {
            for app in repository.apps {
                let identity = repository.sourceURL.absoluteString + "\n" + app.identifier.lowercased()
                guard seen.insert(identity).inserted else { continue }
                mapped.append(Self.makeAppItem(from: app, repository: repository))
            }
        }
        mapped.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        apps = mapped
    }

    private static func makeAppItem(from app: SourceApp, repository: SourceRepository) -> AppItem {
        AppItem(
            appID: stableIntegerID(repository.sourceURL.absoluteString + "\n" + app.identifier.lowercased()),
            appName: app.name,
            modDescription: app.summary ?? app.releaseNotes,
            icon: app.iconURL?.absoluteString,
            storeURL: app.downloadURL?.absoluteString,
            appStoreURL: nil,
            packageName: app.identifier,
            currentVersion: app.version,
            appVersion: app.version,
            modUpdateTime: app.updatedAt.map { ISO8601DateFormatter().string(from: $0) },
            fileSize: app.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
            screenshots: [],
            alistURL: app.downloadURL?.absoluteString,
            isPermanentVIPOnly: false,
            isHot: false,
            sourceURL: repository.sourceURL.absoluteString,
            sourcePayURL: repository.access.payURL?.absoluteString,
            sourceUnlockURL: repository.access.unlockURL?.absoluteString,
            sourceNeedsUnlock: app.access.isNeedLock,
            sourceAppType: app.access.appType
        )
    }

    private static func stableIntegerID(_ value: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return Int(hash & 0x7fff_ffff)
    }
}

enum SoftwareSourceStoreError: LocalizedError {
    case duplicate
    var errorDescription: String? { "该软件源已经添加。" }
}
