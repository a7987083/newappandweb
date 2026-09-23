import SwiftUI

struct SoftwareView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            Group {
                if store.isLoading && store.apps.isEmpty {
                    VStack(spacing: 10) {
                        Text("正在载入…")
                            .font(.headline)
                        Text("请稍候")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(store.apps) { app in
                        NavigationLink(destination: AppDetailView(app: app)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name).font(.headline)
                                Text(app.developer ?? "未知开发者")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationBarTitle("精品软件")
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
    }
}

struct AppDetailView: View {
    let app: AppItem

    var body: some View {
        List {
            Section(header: Text("简介")) {
                Text(app.summary ?? "暂无详细介绍")
            }
            Section {
                keyValueRow("版本", app.version ?? "未知版本")
                keyValueRow("开发者", app.developer ?? "未知")
            }
        }
        .navigationBarTitle(app.name)
    }

    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}
