import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 42))
                        VStack(alignment: .leading) {
                            Text(store.udidService.udid == nil ? "设备未认证" : "已认证设备")
                                .font(.headline)
                            if let udid = store.udidService.udid {
                                Text(udid)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text("功能")) {
                    Button("获取认证") {
                        store.udidService.requestProfileConfiguration()
                    }
                    NavigationLink(destination: PlaceholderView(title: "我的证书")) {
                        Text("我的证书")
                    }
                    NavigationLink(destination: PlaceholderView(title: "我的游戏")) {
                        Text("我的游戏")
                    }
                    NavigationLink(destination: SettingsView()) {
                        Text("通用设置")
                    }
                }

                Section {
                    NavigationLink(destination: PlaceholderView(title: "GameStore")) {
                        Text("关于我们")
                    }
                }
            }
            .navigationBarTitle("个人中心")
        }
    }
}

private struct PlaceholderView: View {
    let title: String

    var body: some View {
        Text("v0.1 已建立模块边界，下一阶段接入真实协议。")
            .padding()
            .navigationBarTitle(title)
    }
}
