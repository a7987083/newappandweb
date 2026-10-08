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

                    NavigationLink(destination: PlaceholderView(title: "我的证书", message: "证书接口与导入流程将在 Phase 3 接入。")) {
                        ProfileRow(icon: "person.text.rectangle", title: "我的证书", subtitle: "管理设备导入证书")
                    }

                    NavigationLink(destination: PlaceholderView(title: "我的游戏", message: "激活码与已激活游戏协议将在 Phase 1 接入。")) {
                        ProfileRow(icon: "gamecontroller", title: "我的游戏", subtitle: "已激活游戏与激活码")
                    }

                    NavigationLink(destination: SettingsView()) {
                        ProfileRow(icon: "gearshape", title: "通用设置", subtitle: nil)
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
            "gamestore://web?url=https%3A%2F%2Fexample.com",
            "在 GameStore 内使用 Safari View 打开 HTTP/HTTPS 网页。"
        ),
        (
            "下载 IPA",
            "gamestore://download/https%3A%2F%2Fexample.com%2Fapp.ipa",
            "把 HTTP/HTTPS IPA 地址加入 GameStore 下载队列。"
        ),
        (
            "导入 / 安装 IPA",
            "gamestore://install/https%3A%2F%2Fexample.com%2Fapp.ipa",
            "把 HTTP/HTTPS IPA 地址加入现有下载/导入入口。"
        ),
        (
            "UDID Provider",
            "gamestore://udid?callback=example%3A%2F%2Fcallback",
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
                        Text("GameStore")
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
                            .textSelection(.enabled)

                        HStack(alignment: .top, spacing: 12) {
                            Text(item.note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 8)
                            Button(action: {
                                UIPasteboard.general.string = item.value
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }) {
                                Label("复制", systemImage: "doc.on.doc")
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

private struct PlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.system(size: 38))
                .foregroundColor(.secondary)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .navigationBarTitle(title)
    }
}
