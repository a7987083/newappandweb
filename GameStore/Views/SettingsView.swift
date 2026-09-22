import SwiftUI

struct SettingsView: View {
    @AppStorage("GameStore.autoUpdate") private var autoUpdate = true
    @AppStorage("GameStore.notifications") private var notifications = true
    @AppStorage("GameStore.forceLocalhost") private var forceLocalhost = false

    var body: some View {
        Form {
            Section("通知与更新") {
                Toggle("自动更新应用", isOn: $autoUpdate)
                Toggle("推送通知", isOn: $notifications)
            }

            Section("安装服务器") {
                Toggle("强制使用 localhost", isOn: $forceLocalhost)
            }

            Section("存储管理") {
                Button("清除所有缓存", role: .destructive) {}
            }
        }
        .navigationTitle("设置")
    }
}
