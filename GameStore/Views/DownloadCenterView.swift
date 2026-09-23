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
                        Text("在应用详情页验证激活码后，下载任务将显示在这里")
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
                                        .frame(width: proxy.size.width * CGFloat(max(0, min(1, item.progress))))
                                }
                            }
                            .frame(height: 4)
                            Text("\(Int(item.progress * 100))% · \(item.state.rawValue)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationBarTitle("下载管理")
        }
    }
}
