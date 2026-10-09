import Foundation
import Combine

final class AppStoreViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var searchText = ""
    @Published private(set) var searchResults: [AppItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let downloadCenter = DownloadCenter()
    let udidService = UDIDService.shared

    private let sourceStore = SoftwareSourceStore.shared
    private var cancellables: Set<AnyCancellable> = []
    private var searchGeneration = 0

    init() {
        sourceStore.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                guard let self = self else { return }
                self.apps = apps
                self.scheduleSearch()
            }
            .store(in: &cancellables)

        sourceStore.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                self?.isLoading = loading
            }
            .store(in: &cancellables)

        sourceStore.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)

        udidService.$udid
            .dropFirst()
            .map { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            .removeDuplicates()
            .filter { !$0.isEmpty }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.sourceStore.reloadAll()
            }
            .store(in: &cancellables)

        $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(280), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSearch()
            }
            .store(in: &cancellables)
    }

    var featuredApps: [AppItem] {
        Array(apps.prefix(5))
    }

    var filteredApps: [AppItem] {
        searchResults
    }

    func reload() {
        sourceStore.reloadAll()
    }

    private func scheduleSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration &+= 1
        let generation = searchGeneration
        let snapshot = apps

        guard !query.isEmpty else {
            searchResults = []
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let needle = query.lowercased()
            let results = snapshot.filter { app in
                app.name.lowercased().contains(needle)
                    || (app.developer?.lowercased().contains(needle) ?? false)
                    || (app.summary?.lowercased().contains(needle) ?? false)
            }

            DispatchQueue.main.async {
                guard let self = self, generation == self.searchGeneration else { return }
                self.searchResults = results
            }
        }
    }
}
