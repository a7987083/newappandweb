import SwiftUI

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
                    ForEach(sourceStore.allApps) { app in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name).font(.headline)
                                Text(app.version.isEmpty ? (sourceStore.sourceNames[app.sourceURL] ?? "") : app.version)
                                    .font(.caption).foregroundColor(.secondary)
                                if !app.subtitle.isEmpty {
                                    Text(app.subtitle).font(.caption).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 4)
                            if let url = app.downloadURL {
                                Button("获取") { self.store.downloadCenter.enqueue(url) }
                                    .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .navigationBarTitle("精品软件")
            .navigationBarItems(trailing: Button(action: { self.sourceStore.refreshAll() }) {
                Image(systemName: "arrow.clockwise")
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear { if self.sourceStore.allApps.isEmpty { self.sourceStore.refreshAll() } }
    }
}
