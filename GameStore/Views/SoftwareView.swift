import SwiftUI
import Combine
import UIKit

struct SoftwareView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)

                if store.isLoading && store.apps.isEmpty {
                    loadingPlaceholder
                } else {
                    ScrollView {
                        VStack(spacing: 22) {
                            if !store.featuredApps.isEmpty {
                                featuredSection
                            }

                            appListSection
                        }
                        .padding(.vertical, 14)
                    }
                }
            }
            .navigationBarTitle("精品软件", displayMode: .large)
            .navigationBarItems(trailing: Button(action: store.reload) {
                Image(systemName: "arrow.clockwise")
            })
            .onAppear {
                if store.apps.isEmpty {
                    store.reload()
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

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "热门推荐")
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.featuredApps) { app in
                        NavigationLink(destination: AppDetailView(app: app)) {
                            FeaturedCardView(app: app)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var appListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "全部软件")
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(store.apps.enumerated()), id: \.element.id) { index, app in
                    NavigationLink(destination: AppDetailView(app: app)) {
                        AppRowView(app: app)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if index != store.apps.count - 1 {
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

struct FeaturedCardView: View {
    let app: AppItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteAppIcon(url: app.iconURL, size: 78, cornerRadius: 18)

            Text(app.name)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(app.developer ?? "发现一款值得尝试的好游戏")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 190, alignment: .leading)
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct AppRowView: View {
    let app: AppItem

    var body: some View {
        HStack(spacing: 12) {
            RemoteAppIcon(url: app.iconURL, size: 58, cornerRadius: 13)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(app.summary ?? app.developer ?? "发现一款值得尝试的好游戏")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("获取")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 15)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct AppDetailView: View {
    let app: AppItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    RemoteAppIcon(url: app.iconURL, size: 92, cornerRadius: 20)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(app.name)
                            .font(.system(size: 22, weight: .bold))

                        Text(app.developer ?? "GameStore")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("获取")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }

                    Spacer()
                }

                HStack(spacing: 0) {
                    DetailStat(title: "版本", value: app.version ?? "未知版本")
                    Divider().frame(height: 34)
                    DetailStat(title: "大小", value: "未知大小")
                    Divider().frame(height: 34)
                    DetailStat(title: "更新", value: "未知时间")
                }
                .padding(.vertical, 10)

                VStack(alignment: .leading, spacing: 10) {
                    Text("简介")
                        .font(.system(size: 20, weight: .bold))
                    Text(app.summary ?? "暂无详细介绍")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        .navigationBarTitle(app.name, displayMode: .inline)
    }
}

private struct DetailStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
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

    private let url: URL?
    private var task: URLSessionDataTask?

    init(url: URL?) {
        self.url = url
    }

    func load() {
        guard image == nil, task == nil, let url = url else { return }
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.image = image
                self?.task = nil
            }
        }
        task?.resume()
    }

    deinit {
        task?.cancel()
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
