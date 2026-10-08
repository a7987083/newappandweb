import Foundation
import Combine

final class AppStoreViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var searchText = ""
    @Published var selectedSort: SortOption = .default
    @Published var currentPage = 1
    @Published var totalPages = 1
    @Published var isLoading = false
    @Published var errorMessage: String?

    let downloadCenter = DownloadCenter()
    let udidService = UDIDService.shared

    private let sourceStore = SoftwareSourceStore.shared
    private var cancellables: Set<AnyCancellable> = []

    init(api: APIClient = APIService.shared) {
        sourceStore.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                self?.apps = apps
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
    }

    var featuredApps: [AppItem] {
        Array(apps.prefix(5))
    }

    var filteredApps: [AppItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return apps
        }

        let needle = trimmed.lowercased()
        return apps.filter {
            $0.name.lowercased().contains(needle)
            || ($0.developer?.lowercased().contains(needle) ?? false)
            || ($0.summary?.lowercased().contains(needle) ?? false)
        }
    }

    func reload() {
        sourceStore.reloadAll()
    }

    func fetchPage(_ page: Int, replacing: Bool) {
        sourceStore.reloadAll()
    }
}
