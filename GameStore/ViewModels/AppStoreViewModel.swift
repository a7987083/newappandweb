import Foundation

@MainActor
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

    var filteredApps: [AppItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return apps
        }
        let needle = searchText.lowercased()
        return apps.filter {
            $0.name.lowercased().contains(needle)
            || ($0.developer?.lowercased().contains(needle) ?? false)
        }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            apps = try await api.fetchApps()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
