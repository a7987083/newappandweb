import SwiftUI

struct DownloadCenterView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            DownloadCenterContent(downloadCenter: store.downloadCenter)
                .navigationBarTitle("下载管理")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

private struct DownloadCenterContent: View {
    @ObservedObject var downloadCenter: DownloadCenter
    @State private var deleteError: String?

    var body: some View {
        Group {
            if downloadCenter.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("暂无下载任务")
                        .font(.headline)
                    Text("在应用详情页点击“获取”后，下载任务将显示在这里")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                List(downloadCenter.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayName(for: item))
                            .font(.headline)
                            .lineLimit(1)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(
                                        width: proxy.size.width
                                            * CGFloat(max(0, min(1, item.progress)))
                                    )
                            }
                        }
                        .frame(height: 4)

                        Text(statusText(for: item))
                            .font(.caption)
                            .foregroundColor(item.state == .failed ? .red : .secondary)

                        if item.state == .completed {
                            HStack {
                                actionButton(
                                    title: "签名",
                                    foreground: .white,
                                    background: .accentColor,
                                    action: {}
                                )
                                .disabled(true)
                                .opacity(0.55)

                                Spacer(minLength: 20)

                                actionButton(
                                    title: "删除",
                                    foreground: .white,
                                    background: .red,
                                    action: { delete(item) }
                                )
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .onAppear {
            downloadCenter.reloadDownloadedItems()
        }
        .alert(isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Alert(
                title: Text("删除失败"),
                message: Text(deleteError ?? ""),
                dismissButton: .default(Text("确定"))
            )
        }
    }

    private func actionButton(
        title: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(foreground)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(background)
                .clipShape(Capsule())
        }
    }

    private func delete(_ item: DownloadCenter.Item) {
        do {
            try downloadCenter.deleteDownloadedItem(item)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func displayName(for item: DownloadCenter.Item) -> String {
        item.localURL?.lastPathComponent ?? item.sourceURL.lastPathComponent
    }

    private func statusText(for item: DownloadCenter.Item) -> String {
        switch item.state {
        case .queued:
            return "等待下载"
        case .downloading:
            return "\(Int(item.progress * 100))% · 下载中"
        case .paused:
            return "已暂停"
        case .completed:
            return "100% · 已下载"
        case .failed:
            return item.errorDescription ?? "下载失败"
        case .cancelled:
            return "已取消"
        }
    }
}
