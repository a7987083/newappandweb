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

    private let api: APIClient

    init(api: APIClient = APIService.shared) {
        self.api = api
    }

    var featuredApps: [AppItem] {
        let hot = apps.filter { $0.isHot }
        return Array((hot.isEmpty ? apps : hot).prefix(5))
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
        fetchPage(1, replacing: true)
    }

    func fetchPage(_ page: Int, replacing: Bool) {
        guard !isLoading else { return }
        isLoading = true

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        api.fetchApps(
            page: page,
            sortBy: selectedSort,
            searchQuery: trimmedSearch.isEmpty ? nil : trimmedSearch
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                switch result {
                case .success(let response):
                    self.apps = replacing ? response.data : self.apps + response.data
                    self.currentPage = response.currentPage
                    self.totalPages = response.totalPages
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = String(describing: error)
                }
            }
        }
    }
}
