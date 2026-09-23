import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("游戏、应用、开发者", text: $store.searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding()

                List(store.filteredApps) { app in
                    NavigationLink(destination: AppDetailView(app: app)) {
                        Text(app.name)
                    }
                }
            }
            .navigationBarTitle("搜索")
        }
    }
}
