import SwiftUI

struct DownloadCenterView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            Group {
                if store.downloadCenter.items.isEmpty {
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
                    List(store.downloadCenter.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.sourceURL.lastPathComponent)

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

                            if let localURL = item.localURL, item.state == .completed {
                                Text(localURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationBarTitle("下载管理")
        }
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
