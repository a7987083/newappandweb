import Foundation
import Combine

final class AppStoreViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    let downloadCenter = DownloadCenter()
    let udidService = UDIDService.shared

    private let api: APIClient

    init(api: APIClient = APIService.shared) {
        self.api = api
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
        guard !isLoading else { return }
        isLoading = true

        api.fetchApps { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                switch result {
                case .success(let apps):
                    self.apps = apps
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = String(describing: error)
                }
            }
        }
    }
}
