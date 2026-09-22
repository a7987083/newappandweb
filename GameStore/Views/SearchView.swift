import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            List(store.filteredApps) { app in
                NavigationLink(app.name, destination: AppDetailView(app: app))
            }
            .searchable(text: $store.searchText, prompt: "游戏、应用、开发者")
            .navigationTitle("搜索")
        }
    }
}
