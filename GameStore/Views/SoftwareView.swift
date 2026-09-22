import SwiftUI

struct SoftwareView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            Group {
                if store.isLoading && store.apps.isEmpty {
                    ProgressView("正在载入…")
                } else {
                    List(store.apps) { app in
                        NavigationLink(destination: AppDetailView(app: app)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name).font(.headline)
                                Text(app.developer ?? "未知开发者")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .refreshable { await store.reload() }
                }
            }
            .navigationTitle("精品软件")
            .task {
                if store.apps.isEmpty {
                    await store.reload()
                }
            }
            .alert("错误", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

struct AppDetailView: View {
    let app: AppItem

    var body: some View {
        List {
            Section("简介") {
                Text(app.summary ?? "暂无详细介绍")
            }
            Section {
                keyValueRow("版本", app.version ?? "未知版本")
                keyValueRow("开发者", app.developer ?? "未知")
            }
        }
        .navigationTitle(app.name)
    }

    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
