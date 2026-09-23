import SwiftUI

struct SettingsView: View {
    @State private var autoUpdate = UserDefaults.standard.object(forKey: "GameStore.autoUpdate") as? Bool ?? true
    @State private var notifications = UserDefaults.standard.object(forKey: "GameStore.notifications") as? Bool ?? true
    @State private var forceLocalhost = UserDefaults.standard.object(forKey: "GameStore.forceLocalhost") as? Bool ?? false

    var body: some View {
        Form {
            Section(header: Text("通知与更新")) {
                Toggle("自动更新应用", isOn: persistedBinding("GameStore.autoUpdate", value: $autoUpdate))
                Toggle("推送通知", isOn: persistedBinding("GameStore.notifications", value: $notifications))
            }

            Section(header: Text("安装服务器")) {
                Toggle("强制使用 localhost", isOn: persistedBinding("GameStore.forceLocalhost", value: $forceLocalhost))
            }

            Section(header: Text("存储管理")) {
                Button(action: {}) {
                    Text("清除所有缓存")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationBarTitle("设置")
    }

    private func persistedBinding(_ key: String, value: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                UserDefaults.standard.set(newValue, forKey: key)
            }
        )
    }
}
