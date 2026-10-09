import SwiftUI
import UIKit
import ImageIO
import Combine

struct SoftwareView: View {
    @ObservedObject private var sourceStore = SoftwareSourceStore.shared
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            List {
                if sourceStore.allApps.isEmpty {
                    Text("暂无软件。请先在「我的 → 软件源」添加来源并刷新。")
                        .foregroundColor(.secondary)
                } else {
                    Section(header: Text("热门推荐")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(Array(sourceStore.allApps.prefix(8))) { app in
                                    NavigationLink(destination: RepositoryAppDetailView(app: app)) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            RemoteAppIcon(url: app.iconURL, size: 78, cornerRadius: 18)
                                            Text(app.name).font(.headline).foregroundColor(.primary).lineLimit(1)
                                            Text(app.subtitle.isEmpty ? app.version : app.subtitle)
                                                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                                        }
                                        .frame(width: 150, alignment: .leading)
                                        .padding(12)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }.padding(.vertical, 5)
                        }
                    }
                    Section(header: Text("全部软件")) {
                        ForEach(sourceStore.allApps) { app in
                            HStack(spacing: 12) {
                                NavigationLink(destination: RepositoryAppDetailView(app: app)) {
                                    HStack(spacing: 12) {
                                        RemoteAppIcon(url: app.iconURL, size: 58, cornerRadius: 13)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(app.name).font(.headline).foregroundColor(.primary).lineLimit(1)
                                            Text(app.subtitle.isEmpty ? app.version : app.subtitle)
                                                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                                        }
                                        Spacer(minLength: 8)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                if let url = app.downloadURL {
                                    Button(action: { self.store.downloadCenter.enqueue(url) }) {
                                        Text("获取").font(.subheadline).fontWeight(.semibold)
                                            .foregroundColor(.accentColor)
                                            .padding(.horizontal, 15).padding(.vertical, 7)
                                            .background(Color.accentColor.opacity(0.12))
                                            .clipShape(Capsule())
                                    }.buttonStyle(BorderlessButtonStyle())
                                }
                            }.padding(.vertical, 10)
                        }
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .navigationBarTitle("精品软件")
            .navigationBarItems(trailing: Button(action: { self.sourceStore.refreshAll() }) {
                Image(systemName: "arrow.clockwise")
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            if self.sourceStore.allApps.isEmpty { self.sourceStore.refreshAll() }
        }
    }
}

private struct RepositoryAppDetailView: View {
    let app: RepositoryApp
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    RemoteAppIcon(url: app.iconURL, size: 92, cornerRadius: 20)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.name).font(.title).fontWeight(.bold)
                        if !app.version.isEmpty {
                            Text("版本 " + app.version).font(.subheadline).foregroundColor(.secondary)
                        }
                        if let url = app.downloadURL {
                            Button("获取") { self.store.downloadCenter.enqueue(url) }
                                .padding(.horizontal, 22).padding(.vertical, 8)
                                .foregroundColor(.white)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    Spacer(minLength: 0)
                }
                if !app.subtitle.isEmpty {
                    Text("简介").font(.headline)
                    Text(app.subtitle).foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
        .navigationBarTitle(app.name, displayMode: .inline)
    }
}

struct RemoteAppIcon: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat

    @ObservedObject private var loader: RemoteImageLoader

    init(url: URL?, size: CGFloat, cornerRadius: CGFloat) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
        self._loader = ObservedObject(wrappedValue: RemoteImageLoader(url: url))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(UIColor.tertiarySystemFill)
                    Image(systemName: "app.fill")
                        .font(.system(size: size * 0.35))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear(perform: loader.load)
    }
}

final class RemoteImageLoader: ObservableObject {
    @Published var image: UIImage?

    private static let cache = NSCache<NSURL, UIImage>()
    // Accessed on main only. One network request fans out to all visible views.
    private static var pending: [URL: [(UIImage?) -> Void]] = [:]

    private let url: URL?
    private var loading = false

    init(url: URL?) {
        self.url = url
    }

    func load() {
        guard let url = url, image == nil, !loading else { return }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.load() }
            return
        }

        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }

        loading = true
        let completion: (UIImage?) -> Void = { [weak self] result in
            self?.loading = false
            self?.image = result
        }

        if Self.pending[url] != nil {
            Self.pending[url]?.append(completion)
            return
        }
        Self.pending[url] = [completion]

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { data, response, error in
            let maxImageBytes = 2 * 1024 * 1024
            let validResponse = (response as? HTTPURLResponse).map {
                (200...299).contains($0.statusCode)
                    && ($0.expectedContentLength < 0
                        || $0.expectedContentLength <= Int64(maxImageBytes))
            } ?? false
            let decoded: UIImage?
            if error == nil, validResponse, let data = data,
               data.count <= maxImageBytes,
               let source = CGImageSourceCreateWithData(data as CFData, nil) {
                let properties: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, properties as CFDictionary)
                    .map(UIImage.init(cgImage:))
            } else {
                decoded = nil
            }

            DispatchQueue.main.async {
                if let decoded = decoded {
                    Self.cache.setObject(decoded, forKey: url as NSURL)
                }
                let callbacks = Self.pending.removeValue(forKey: url) ?? []
                callbacks.forEach { $0(decoded) }
            }
        }.resume()
    }
}

