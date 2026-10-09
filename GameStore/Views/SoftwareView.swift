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
        SourceAppDetailContent(app: app, downloadCenter: appStore.downloadCenter)
    }
}

private struct SourceAppDetailContent: View {
    let app: SourceCatalogApp
    @ObservedObject var downloadCenter: DownloadCenter

    private var downloadItem: DownloadCenter.Item? {
        guard let url = app.downloadURL else { return nil }
        return downloadCenter.item(for: url)
    }

    private var displayedDate: String? {
        guard let date = app.updatedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    SourceAppIcon(url: app.iconURL)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(app.name)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if !app.developer.isEmpty {
                            Text(app.developer).font(.caption).foregroundColor(.secondary)
                        }
                        downloadControl
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 18)
                .padding(.bottom, 20)

                Divider()

                HStack(alignment: .top, spacing: 8) {
                    metadataCell("版本", app.version)
                    Spacer(minLength: 0)
                    if let bytes = app.sizeBytes, bytes > 0 {
                        metadataCell("大小", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        Spacer(minLength: 0)
                    }
                    if let date = displayedDate {
                        metadataCell("更新时间", date)
                    }
                }
                .padding(.vertical, 18)

                if !app.description.isEmpty {
                    Divider()
                    Text("简介").font(.headline).padding(.top, 19)
                    Text(app.description)
                        .font(.body)
                        .padding(.top, 8)
                        .padding(.bottom, 19)
                }
                if !app.releaseNotes.isEmpty {
                    Divider()
                    Text("更新说明").font(.headline).padding(.top, 19)
                    Text(app.releaseNotes)
                        .font(.body)
                        .padding(.top, 8)
                        .padding(.bottom, 19)
                }

                Divider()
                Text("信息").font(.headline).padding(.top, 19)
                if !app.bundleIdentifier.isEmpty {
                    Text("Bundle ID: " + app.bundleIdentifier).padding(.top, 9)
                }
                if !app.category.isEmpty {
                    Text("分类: " + app.category).padding(.top, 9)
                }
                Text("来源: " + (URL(string: app.sourceURL)?.host ?? app.sourceURL))
                    .padding(.top, 9)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(UIColor.systemBackground))
        .navigationBarTitle("软件详情", displayMode: .inline)
    }

    private func metadataCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value.isEmpty ? "—" : value).font(.subheadline)
        }
    }

    @ViewBuilder private var downloadControl: some View {
        if let url = app.downloadURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            if let item = downloadItem {
                switch item.state {
                case .queued:
                    Text("等待下载").font(.caption).foregroundColor(.secondary)
                case .downloading:
                    HStack(spacing: 6) {
                        DownloadProgressBar(progress: item.progress)
                        Text(String(Int(max(0, min(1, item.progress)) * 100)) + "%")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                case .paused:
                    Button("继续下载") { downloadCenter.resume(item) }
                case .completed:
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("已下载")
                    }.foregroundColor(.green)
                case .failed, .cancelled:
                    Button("重新获取") { downloadCenter.enqueue(url) }
                }
            } else {
                Button("获取") { downloadCenter.enqueue(url) }
            }
        } else {
            Text("此软件未提供有效的下载地址").font(.caption).foregroundColor(.secondary)
        }
    }
}

private struct DownloadProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.2))
                Capsule().fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(max(0, min(1, progress))))
            }
        }.frame(width: 54, height: 5)
    }
}
