import SwiftUI

struct SoftwareView: View {
    @ObservedObject private var sources = SoftwareSourceStore.shared
    @State private var query = ""

    private var displayed: [SourceCatalogApp] {
        query.isEmpty ? sources.catalogApps : sources.catalogApps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("应用")
                        .font(.system(size: 40, weight: .bold))
                        .padding(.top, 12)

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("搜索", text: $query)
                    }
                    .font(.system(size: 19))
                    .padding(13)
                    .background(Color(red: 0.89, green: 0.89, blue: 0.91))
                    .cornerRadius(12)

                    if let error = sources.catalogError {
                        Text(error).font(.footnote).foregroundColor(.orange)
                    }
                    if sources.sources.isEmpty {
                        Text("尚未添加软件源，可在设置页面添加。")
                            .foregroundColor(.secondary)
                    }
                    ForEach(displayed) { app in
                        NavigationLink(destination: SourceAppDetailView(app: app)) {
                            HStack(spacing: 16) {
                                SourceAppIcon(url: app.iconURL)
                                    .frame(width: 64, height: 64)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(app.name)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text([app.version, app.bundleIdentifier].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                    Text("软件源")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.09))
                                        .cornerRadius(6)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white)
                            .cornerRadius(20)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    if displayed.isEmpty && !sources.isCatalogLoading && !sources.sources.isEmpty {
                        Text("没有匹配的应用")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .background(Color(red: 0.95, green: 0.95, blue: 0.97).edgesIgnoringSafeArea(.all))
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(trailing: Button(action: { sources.refreshCatalog() }) {
                Image(systemName: "plus.circle.fill").font(.system(size: 25))
            }.disabled(sources.isCatalogLoading))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct SourceAppRow: View {
    let app: SourceCatalogApp
    var body: some View {
        HStack(spacing: 12) {
            SourceAppIcon(url: app.iconURL).id(app.iconURL?.absoluteString ?? "no-icon")
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
    @State private var loadedImage: UIImage?
    var body: some View {
        Group {
            if let image = loadedImage ?? url.flatMap({ SourceIconCache.shared.cachedMemoryImage(for: $0) }) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "app").resizable().scaledToFit().padding(10)
            }
        }
        .frame(width: 52, height: 52)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .clipped()
        .onAppear { fetch() }
    }
    private func fetch() {
        guard let url = url else { return }
        SourceIconCache.shared.load(url) { image in
            if self.url == url { self.loadedImage = image }
        }
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
                    }
                    Spacer(minLength: 8)
                    downloadControl
                        .frame(minWidth: 92, alignment: .trailing)
                        .padding(.top, 25)
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
        .modifier(CompactDetailTitle())
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
                    Button("继续") { downloadCenter.resume(item) }
                        .modifier(SourceGetPillStyle())
                case .completed:
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("已下载")
                    }.foregroundColor(.green)
                case .failed, .cancelled:
                    Button("重试") { downloadCenter.enqueue(url) }
                        .modifier(SourceGetPillStyle())
                }
            } else {
                Button("获取") { downloadCenter.enqueue(url) }
                    .modifier(SourceGetPillStyle())
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

private struct CompactDetailTitle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 14.0, *) {
            content.navigationBarTitle("软件详情", displayMode: .inline)
        } else {
            content.navigationBarTitle("软件详情")
        }
    }
}

private struct SourceGetPillStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .frame(height: 32)
            .background(Color(red: 0.16, green: 0.46, blue: 0.91))
            .clipShape(Capsule())
            .buttonStyle(PlainButtonStyle())
    }
}
