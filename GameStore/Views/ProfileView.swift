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
                                Text(udid).font(.caption2).textSelection(.enabled)
                            }
                        }
                    }
                }

                Section("功能") {
                    Button("获取认证") {
                        store.udidService.requestProfileConfiguration()
                    }
                    NavigationLink("我的证书", destination: PlaceholderView(title: "我的证书"))
                    NavigationLink("我的游戏", destination: PlaceholderView(title: "我的游戏"))
                    NavigationLink("通用设置", destination: SettingsView())
                }

                Section {
                    NavigationLink("关于我们", destination: PlaceholderView(title: "GameStore"))
                }
            }
            .navigationTitle("个人中心")
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    var body: some View {
        Text("v0.1 已建立模块边界，下一阶段接入真实协议。")
            .padding()
            .navigationTitle(title)
    }
}
