import SwiftUI

struct SigningSettingsView: View {
    @ObservedObject private var store = SigningOptionsStore.shared

    var body: some View {
        Form {
            Section(header: Text("证书管理")) {
                NavigationLink(destination: CertificateManagementView()) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                        Text("导入证书")
                    }
                }
                Text("支持导入 P12 与 mobileprovision，签名时选择已保存的证书。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Section(header: Text("应用能力")) {
                Toggle("强制本地化", isOn: binding(\.forceLocalization))
                Toggle("文件共享", isOn: binding(\.fileSharing))
                Toggle("iTunes 文件共享", isOn: binding(\.itunesFileSharing))
                Toggle("ProMotion", isOn: binding(\.proMotion))
                Toggle("游戏模式", isOn: binding(\.gameMode))
                Toggle("iPad 全屏", isOn: binding(\.ipadFullscreen))
            }

            Section(
                header: Text("签名行为"),
                footer: Text("“临时签署”使用 Zsign Ad-hoc 伪签名，不需要证书；注册回调用于向目标 App 注册 zonoe UDID URL Scheme。")
            ) {
                Toggle("Ad-hoc 伪签名", isOn: binding(\.temporarySigning))
                Toggle("签名完成自动安装", isOn: binding(\.autoInstallAfterSigning))
                Toggle("注册回调", isOn: binding(\.registerCallback))
            }

            Section(
                header: Text("打包规则"),
                footer: Text("两种模式都会生成标准 IPA；区别仅在输出文件名规则。")
            ) {
                Picker(
                    "打包规则",
                    selection: binding(\.packagingRule)
                ) {
                    ForEach(SigningPackagingRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
            }

            Section {
                Button("恢复默认设置") {
                    store.resetToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .navigationBarTitle("签名设置")
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<SigningOptions, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                store.options[keyPath: keyPath]
            },
            set: { newValue in
                var options = store.options
                options[keyPath: keyPath] = newValue
                store.options = options
            }
        )
    }
}
