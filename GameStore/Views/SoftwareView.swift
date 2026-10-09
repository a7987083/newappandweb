import SwiftUI

struct SoftwareView: View {
    @ObservedObject private var sources = SoftwareSourceStore.shared
    @EnvironmentObject private var appStore: AppStoreViewModel
    @State private var selectedCategory = "全部"

    private var categories: [String] {
        ["全部"] + Array(Set(sources.catalogApps.map { $0.category.isEmpty ? "其他" : $0.category })).sorted()
    }
    private var displayed: [SourceCatalogApp] {
        selectedCategory == "全部" ? sources.catalogApps :
            sources.catalogApps.filter { ($0.category.isEmpty ? "其他" : $0.category) == selectedCategory }
    }

    var body: some View {
        NavigationView {
            List {
                if let error = sources.catalogError {
                    Section { Text(error).font(.footnote).foregroundColor(.orange) }
                }
                if sources.sources.isEmpty {
                    Section {
                        Text("尚未添加软件源，请前往「我的 → 软件源」添加。")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.self) { category in
                                    Button(action: { selectedCategory = category }) {
                                        Text(category)
                                            .font(.subheadline)
                                            .padding(.horizontal, 13)
                                            .padding(.vertical, 8)
                                            .background(selectedCategory == category ? Color.accentColor.opacity(0.16) : Color(UIColor.secondarySystemGroupedBackground))
                                            .cornerRadius(12)
                                    }
                                }
                            }
                        }
                    }
                    Section(header: Text("软件 · \(displayed.count)")) {
                        ForEach(displayed) { app in
                            NavigationLink(destination: SourceAppDetailView(app: app)) {
                                SourceAppRow(app: app)
                            }
                        }
                        if displayed.isEmpty && !sources.isCatalogLoading {
                            Text("此分类暂无软件").foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .navigationBarTitle("精品软件")
            .navigationBarItems(trailing: Button(action: { sources.refreshCatalog() }) {
                Image(systemName: "arrow.clockwise")
            }.disabled(sources.isCatalogLoading))
            .overlay(Group {
                if sources.isCatalogLoading { Text("正在解析软件源…").font(.footnote).padding(12).background(Color(UIColor.secondarySystemBackground)).cornerRadius(12) }
            })
            .onAppear { if sources.catalogApps.isEmpty { sources.refreshCatalog() } }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct SourceAppRow: View {
    let app: SourceCatalogApp
    var body: some View {
        HStack(spacing: 12) {
            SourceAppIcon(url: app.iconURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.headline)
                Text([app.version, app.category].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundColor(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

struct SourceAppIcon: View {
    let url: URL?
    var body: some View {
        Group {
            if #available(iOS 15.0, *), let url = url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "app").resizable().scaledToFit().padding(10)
                }
            } else {
                Image(systemName: "app").resizable().scaledToFit().padding(10)
            }
        }
        .frame(width: 52, height: 52)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .clipped()
    }
}

struct SourceAppDetailView: View {
    let app: SourceCatalogApp
    @EnvironmentObject private var appStore: AppStoreViewModel

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    SourceAppIcon(url: app.iconURL)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(app.name).font(.headline)
                        if !app.version.isEmpty { Text("版本 " + app.version).font(.caption) }
                        if !app.developer.isEmpty { Text(app.developer).font(.caption).foregroundColor(.secondary) }
                    }
                }
                if let url = app.downloadURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    Button("下载 IPA") { appStore.downloadCenter.enqueue(url) }
                } else {
                    Text("此软件未提供有效的下载地址").font(.footnote).foregroundColor(.secondary)
                }
            }
            if !app.description.isEmpty {
                Section(header: Text("软件说明")) {
                    Text(app.description)
                }
            }
            Section(header: Text("信息")) {
                if !app.bundleIdentifier.isEmpty { Text("Bundle ID: " + app.bundleIdentifier) }
                if !app.category.isEmpty { Text("分类: " + app.category) }
                Text("来源: " + (URL(string: app.sourceURL)?.host ?? app.sourceURL))
            }
        }
        .listStyle(GroupedListStyle())
        .navigationBarTitle(app.name)
    }
}
