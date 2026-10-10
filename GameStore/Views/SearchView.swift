import SwiftUI

struct SearchView: View {
    @ObservedObject private var sources = SoftwareSourceStore.shared
    @State private var query = ""

    private var matches: [SourceCatalogApp] {
        guard !query.isEmpty else { return [] }
        return sources.catalogApps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(query) ||
            $0.category.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("搜索软件、Bundle ID 或分类", text: $query)
                        .autocapitalization(.none)
                }
                Section(header: Text("搜索结果 · \(matches.count)")) {
                    ForEach(matches) { app in
                        NavigationLink(destination: SourceAppDetailView(app: app)) {
                            SourceAppRow(app: app)
                        }
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .navigationBarTitle("搜索")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
