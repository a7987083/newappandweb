import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.14))
                                .frame(width: 58, height: 58)
                            Image(systemName: store.udidService.udid == nil ? "iphone.slash" : "checkmark.seal.fill")
                                .font(.system(size: 27))
                                .foregroundColor(.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.udidService.udid == nil ? "设备未认证" : "已认证设备")
                                .font(.headline)

                            if let udid = store.udidService.udid {
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
                    if store.udidService.udid == nil {
                        Button(action: {
                            store.udidService.requestProfileConfiguration()
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
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.fill")
                .font(.system(size: 62))
                .foregroundColor(.accentColor)
            Text("GameStore")
                .font(.system(size: 24, weight: .bold))
            Text("为你精选全球精品应用与游戏，安全可靠，即装即用。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Text("Version 0.2-dev")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("© 2025 GameStore Team")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 50)
        .navigationBarTitle("GameStore")
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
