import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var store: AppStoreViewModel
    @ObservedObject private var udidService = UDIDService.shared

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.14))
                                .frame(width: 58, height: 58)
                            Image(systemName: udidService.udid == nil ? "iphone.slash" : "checkmark.seal.fill")
                                .font(.system(size: 27))
                                .foregroundColor(.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(udidService.udid == nil ? "设备未认证" : "已认证设备")
                                .font(.headline)

                            if let udid = udidService.udid {
                                Text(udid)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("获取设备认证后可使用证书与安装功能")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }

                Section(header: Text("功能")) {
                    if udidService.udid == nil {
                        Button(action: {
                            udidService.requestProfileConfiguration()
                        }) {
                            ProfileRow(icon: "checkmark.shield", title: "获取认证", subtitle: "安装描述文件并验证设备")
                        }
                    }

                    NavigationLink(destination: SourcesView()) {
                        ProfileRow(icon: "tray.full", title: "软件源", subtitle: "添加软件源")
                    }

                    NavigationLink(destination: SigningSettingsView()) {
                        ProfileRow(icon: "signature", title: "签名设置", subtitle: "配置签名与打包行为")
                    }

                }

                Section {
                    NavigationLink(destination: AboutView()) {
                        ProfileRow(icon: "info.circle", title: "关于我们", subtitle: nil)
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .navigationBarTitle("个人中心")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

private struct ProfileRow: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct AboutView: View {
    private let schemes: [(title: String, value: String, note: String)] = [
        (
            "App 内打开网页",
            "zonoe://web?url=https%3A%2F%2Fexample.com",
            "在 zonoe 内使用 Safari View 打开 HTTP/HTTPS 网页。"
        ),
        (
            "下载 IPA",
            "zonoe://download/https%3A%2F%2Fexample.com%2Fapp.ipa",
            "把 HTTP/HTTPS IPA 地址加入 zonoe 下载队列。"
        ),
        (
            "下载 IPA（install 兼容入口）",
            "zonoe://install/https%3A%2F%2Fexample.com%2Fapp.ipa",
            "当前行为与 download 相同：把 HTTP/HTTPS IPA 地址加入下载队列。"
        ),
        (
            "UDID Provider",
            "zonoe://udid?callback=example%3A%2F%2Fcallback",
            "返回已保存的 UDID；未认证时先完成设备认证，再回调请求方。"
        )
    ]

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("zonoe")
                            .font(.headline)
                        Text("URL Scheme")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("URL Scheme 说明")) {
                ForEach(schemes.indices, id: \.self) { index in
                    let item = schemes[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .font(.headline)

                        Text(item.value)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.primary)

                        HStack(alignment: .top, spacing: 12) {
                            Text(item.note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 8)
                            Button(action: {
                                UIPasteboard.general.string = item.value
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                    Text("复制")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.vertical, 5)
                }
            }

            Section {
                Text("Version 0.2-dev")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(GroupedListStyle())
        .navigationBarTitle("关于我们")
    }
}

private struct SourcesView: View {
    @ObservedObject private var sourceStore = SoftwareSourceStore.shared
    @State private var showAddSourceSheet = false
    @State private var sourceInput = ""

    private var sources: [String] {
        sourceStore.sources
    }

    var body: some View {
        ZStack {
            List {
                if sources.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.system(size: 34))
                                .foregroundColor(.secondary)
                            Text("暂无软件源")
                                .font(.headline)
                            Text("点击右上角 + 添加 HTTP/HTTPS 软件源地址")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    Section(header: Text("已添加")) {
                        ForEach(sources, id: \.self) { value in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sourceDisplayName(value))
                                    .font(.headline)
                                Text(value)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(GroupedListStyle())


        }
        .navigationBarTitle("软件源")
        .overlay(Group {
            if sourceStore.isLoading {
                Text("正在验证软件源…")
                    .padding(20)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(14)
            }
        })
        .navigationBarItems(trailing:
            Button(action: { showAddSourceSheet = true }) {
                Image(systemName: "plus")
            }
            .disabled(sourceStore.isLoading)
        )
        .sheet(isPresented: $showAddSourceSheet) {
            NavigationView {
                Form {
                    Section(header: Text("软件源地址")) {
                        TextField("https://example.com/repo.json", text: self.$sourceInput)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }
                .navigationBarTitle("添加软件源", displayMode: .inline)
                .navigationBarItems(
                    leading: Button("取消") {
                        self.showAddSourceSheet = false
                    },
                    trailing: Button("添加") {
                        let value = self.sourceInput
                        self.showAddSourceSheet = false
                        self.sourceInput = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            self.addSource(value)
                        }
                    }
                    .disabled(self.sourceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                )
            }
        }
    }

    private func addSource(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            showError("请输入有效的 HTTP 或 HTTPS 软件源地址。")
            return
        }

        let normalized = url.absoluteString
        guard !sources.contains(normalized) else {
            showError("该软件源已经添加。")
            return
        }

        sourceStore.add(url) { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    showError(error.localizedDescription)
                }
            }
        }
    }

    private func sourceDisplayName(_ value: String) -> String {
        sourceStore.sourceNames[value] ?? URL(string: value)?.host ?? "软件源"
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "添加软件源失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        guard let presenter = UIApplication.shared.gameStoreTopViewController() else { return }
        presenter.present(alert, animated: true)
    }

}

