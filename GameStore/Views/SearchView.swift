import SwiftUI

struct SearchView: View {
    @ObservedObject private var sourceStore = SoftwareSourceStore.shared
    @EnvironmentObject private var store: AppStoreViewModel
    @State private var query = ""

    private var results: [RepositoryApp] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty { return sourceStore.allApps }
        return sourceStore.allApps.filter {
            $0.name.localizedCaseInsensitiveContains(keyword) ||
            $0.bundleID.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜索名称或 Bundle ID", text: $query)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .padding()
                List {
                    ForEach(results) { app in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(app.name).font(.headline)
                                Text(app.bundleID).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if let url = app.downloadURL {
                                Button("获取") { self.store.downloadCenter.enqueue(url) }
                                    .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                }
            }
            .navigationBarTitle("搜索")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
