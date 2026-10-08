import SwiftUI
import Combine
import UIKit

struct SoftwareView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            Group {
                if store.isLoading && store.apps.isEmpty {
                    loadingPlaceholder
                } else if store.apps.isEmpty {
                    emptyPlaceholder
                } else {
                    List {
                        if !store.featuredApps.isEmpty {
                            Section(header: Text("热门推荐")) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(store.featuredApps) { app in
                                            NavigationLink(destination: AppDetailView(app: app)) {
                                                FeaturedCardView(app: app)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        Section(header: Text("全部软件")) {
                            ForEach(store.apps) { app in
                                NavigationLink(destination: AppDetailView(app: app)) {
                                    AppRowView(app: app)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .listStyle(GroupedListStyle())
                }
            }
            .navigationBarTitle("精品软件")
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

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text("暂无软件")
                .font(.headline)
            Text("请先在“个人中心 → 软件源”添加并解析软件源")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
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
    @EnvironmentObject private var store: AppStoreViewModel
    let app: AppItem

    private var currentApp: AppItem {
        store.apps.first(where: { $0.id == app.id }) ?? app
    }

    private static func displayUpdateTime(_ rawValue: String?) -> String {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return "未知时间"
        }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: rawValue) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }

        return rawValue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    RemoteAppIcon(url: app.iconURL, size: 92, cornerRadius: 20)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(app.name)
                            .font(.system(size: 22, weight: .bold))

                        Text(currentApp.developer ?? "GameStore")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        DownloadActionButton(
                            app: currentApp,
                            downloadCenter: store.downloadCenter,
                            udidService: store.udidService,
                            onUnlocked: store.reload
                        )
                    }

                    Spacer()
                }

                HStack(spacing: 0) {
                    DetailStat(title: "版本", value: currentApp.version ?? "未知版本")
                    Divider().frame(height: 34)
                    DetailStat(title: "大小", value: currentApp.fileSize ?? "未知大小")
                    Divider().frame(height: 34)
                    DetailStat(title: "更新", value: Self.displayUpdateTime(currentApp.modUpdateTime))
                }
                .padding(.vertical, 10)

                VStack(alignment: .leading, spacing: 10) {
                    Text("简介")
                        .font(.system(size: 20, weight: .bold))
                    Text(currentApp.summary ?? "暂无详细介绍")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        .navigationBarTitle(currentApp.name)
    }
}

private struct DownloadActionButton: View {
    let app: AppItem
    @ObservedObject var downloadCenter: DownloadCenter
    @ObservedObject var udidService: UDIDService
    let onUnlocked: () -> Void

    @State private var showUnlockCode = false
    @State private var unlockCode = ""
    @State private var isUnlocking = false
    @State private var unlockError: String?

    private var sourceURL: URL? {
        app.sourceURL.flatMap(URL.init(string:))
    }

    private var unlockURL: URL? {
        app.sourceUnlockURL.flatMap(URL.init(string:))
    }

    private var payURL: URL? {
        app.sourcePayURL.flatMap(URL.init(string:))
    }

    private var hasGrant: Bool {
        guard let sourceURL = sourceURL,
              let udid = udidService.udid,
              !udid.isEmpty else {
            return false
        }
        return SourceUnlockService.shared.hasGrant(
            sourceURL: sourceURL,
            appIdentifier: app.packageName,
            appName: app.name,
            udid: udid
        )
    }

    private var isLocked: Bool {
        if let needsUnlock = app.sourceNeedsUnlock {
            if !needsUnlock { return false }
            return !hasGrant
        }
        return app.downloadURL == nil
    }

    private var item: DownloadCenter.Item? {
        guard let url = app.downloadURL else { return nil }
        return downloadCenter.item(for: url)
    }

    var body: some View {
        Group {
            if isLocked {
                Button(action: beginUnlock) {
                    Text("解锁")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            } else if let item = item {
                switch item.state {
                case .queued, .downloading:
                    HStack(spacing: 6) {
                        ActivityIndicator()
                            .frame(width: 18, height: 18)
                        Text("\(Int(item.progress * 100))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                case .completed:
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("已导入")
                    }
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                case .failed:
                    actionButton(title: "重试", background: .red, action: startDownload)

                case .cancelled, .paused:
                    actionButton(title: "获取", background: .accentColor, action: startDownload)
                }
            } else {
                actionButton(
                    title: app.downloadURL == nil ? "暂无下载地址" : "获取",
                    background: app.downloadURL == nil ? .secondary : .accentColor,
                    action: startDownload
                )
                .disabled(app.downloadURL == nil)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showUnlockCode) {
            UnlockCodeSheet(
                code: $unlockCode,
                isUnlocking: isUnlocking,
                errorMessage: unlockError,
                payURL: payURL,
                onCancel: {
                    guard !isUnlocking else { return }
                    showUnlockCode = false
                    unlockCode = ""
                    unlockError = nil
                },
                onConfirm: unlock
            )
        }
    }

    private func beginUnlock() {
        unlockError = nil

        guard let udid = udidService.udid, !udid.isEmpty else {
            udidService.requestProfileConfiguration()
            return
        }

        showUnlockCode = true
    }

    private func unlock() {
        guard !isUnlocking else { return }
        guard let sourceURL = sourceURL else {
            unlockError = "软件源上下文缺失"
            return
        }
        guard let unlockURL = unlockURL else {
            unlockError = "该软件源未提供解锁接口"
            return
        }
        guard let udid = udidService.udid, !udid.isEmpty else {
            unlockError = "请先获取本机 UDID"
            return
        }

        isUnlocking = true
        unlockError = nil

        SourceUnlockService.shared.unlock(
            sourceURL: sourceURL,
            unlockURL: unlockURL,
            appIdentifier: app.packageName,
            appName: app.name,
            udid: udid,
            code: unlockCode
        ) { result in
            DispatchQueue.main.async {
                self.isUnlocking = false
                switch result {
                case .success:
                    self.showUnlockCode = false
                    self.unlockCode = ""
                    self.unlockError = nil
                    self.onUnlocked()

                case .failure(let error):
                    self.unlockError = error.localizedDescription
                }
            }
        }
    }

    private func startDownload() {
        guard !isLocked, let url = app.downloadURL else { return }
        downloadCenter.enqueue(url)
    }

    private func actionButton(
        title: String,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(background)
                .clipShape(Capsule())
        }
    }
}

private struct UnlockCodeSheet: View {
    @Binding var code: String
    let isUnlocking: Bool
    let errorMessage: String?
    let payURL: URL?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("解锁码")) {
                    TextField("请输入卡密", text: $code)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                if let errorMessage = errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                if let payURL = payURL {
                    Section {
                        Button("获取解锁码") {
                            UIApplication.shared.open(payURL)
                        }
                    }
                }
            }
            .navigationBarTitle("解锁软件源", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消", action: onCancel).disabled(isUnlocking),
                trailing: Button(isUnlocking ? "验证中…" : "验证", action: onConfirm)
                    .disabled(isUnlocking || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
