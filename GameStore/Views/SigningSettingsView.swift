import SwiftUI

struct SigningSettingsView: View {
    @ObservedObject private var store = SigningOptionsStore.shared

    var body: some View {
        Form {
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
                footer: Text("“临时签署”按当前项目定义为只修改并重新打包 IPA，不执行证书签名。")
            ) {
                Toggle("临时签署", isOn: binding(\.temporarySigning))
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
