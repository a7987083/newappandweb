import SwiftUI
import ImageIO
import Combine
import UIKit

struct SoftwareView: View {
    @ObservedObject private var sourceStore = SoftwareSourceStore.shared
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)

                if sourceStore.isLoading && sourceStore.allApps.isEmpty {
                    loadingPlaceholder
                } else {
                    ScrollView {
                        VStack(spacing: 22) {
                            if !featuredApps.isEmpty {
                                featuredSection
                            }

                            appListSection
                        }
                        .padding(.vertical, 14)
                    }
                }
            }
            .navigationBarTitle("精品软件")
            .navigationBarItems(trailing: Button(action: { self.sourceStore.refreshAll() }) {
                Image(systemName: "arrow.clockwise")
            })
            .onAppear {
                if sourceStore.allApps.isEmpty {
                    sourceStore.refreshAll()
                }
            }
            .alert(isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Alert(
                    title: Text("错误"),
                    message: Text(store.errorMessage ?? ""),
                    dismissButton: .default(Text("确定"))
                )
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var featuredApps: [RepositoryApp] { [] }

    private var featuredSection: some View {
        EmptyView()
    }

    private var appListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "全部软件")
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(sourceStore.allApps.enumerated()), id: \.element.id) { index, app in
                    AppRowView(app: app, onDownload: {
                        if let url = app.downloadURL { self.store.downloadCenter.enqueue(url) }
                    })

                    if index != sourceStore.allApps.count - 1 {
                        Divider().padding(.leading, 86)
                    }
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(14)
            .padding(.horizontal, 16)
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ActivityIndicator()
                .frame(width: 28, height: 28)
            Text("正在载入…")
                .font(.headline)
            Text("请稍候")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}


struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Spacer()
        }
    }
}


struct AppRowView: View {
    let app: RepositoryApp
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteAppIcon(url: app.iconURL, size: 58, cornerRadius: 13)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.headline).foregroundColor(.primary).lineLimit(1)
                Text(app.subtitle.isEmpty ? app.version : app.subtitle)
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if app.downloadURL != nil {
                Button(action: onDownload) {
                    Text("获取").font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 15).padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }.buttonStyle(BorderlessButtonStyle())
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
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


private struct ActivityIndicator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: .medium)
        view.startAnimating()
        return view
    }
    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {}
}
