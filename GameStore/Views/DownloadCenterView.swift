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
                            .foregroundStyle(.secondary)
                        Text("暂无下载任务")
                            .font(.headline)
                        Text("在应用详情页验证激活码后，下载任务将显示在这里")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List(store.downloadCenter.items) { item in
                        VStack(alignment: .leading) {
                            Text(item.sourceURL.lastPathComponent)
                            ProgressView(value: item.progress)
                            Text(item.state.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("下载管理")
        }
    }
}
