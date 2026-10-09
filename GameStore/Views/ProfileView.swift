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

    private var sources: [String] {
        sourceStore.sources
    }

    var body: some View {
        ZStack {
            if sources.isEmpty {
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
                .padding(24)
            } else {
                SourceSwipeTable(
                    urls: sources,
                    names: sourceStore.sourceNames,
                    onCopy: { UIPasteboard.general.string = $0 },
                    onDelete: { self.sourceStore.remove($0) }
                )
            }
            if sourceStore.isLoading {
                Color.black.opacity(0.18)
                    .edgesIgnoringSafeArea(.all)
                VStack(spacing: 12) {
                    SourceActivityIndicator()
                        .frame(width: 30, height: 30)
                    Text("正在添加软件源")
                        .font(.headline)
                    Text("正在请求并解析软件源…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(18)
                .shadow(radius: 8)
            }
        }
        .navigationBarTitle("软件源")
        .navigationBarItems(trailing:
            Button(action: presentAddSourceAlert) {
                Image(systemName: "plus")
            }
            .disabled(sourceStore.isLoading)
        )
    }

    private func presentAddSourceAlert() {
        let alert = UIAlertController(
            title: "添加软件源",
            message: "请输入 HTTP 或 HTTPS 软件源地址",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "https://example.com/repo.json"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "添加", style: .default) { [weak alert] _ in
            self.addSource(alert?.textFields?.first?.text ?? "")
        })
        guard let presenter = UIApplication.shared.gameStoreTopViewController() else { return }
        presenter.present(alert, animated: true)
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


private struct SourceActivityIndicator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: .medium)
        view.startAnimating()
        return view
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {}
}

private struct SourceSwipeTable: UIViewRepresentable {
    let urls: [String]
    let names: [String: String]
    let onCopy: (String) -> Void
    let onDelete: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .grouped)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 76
        return table
    }

    func updateUIView(_ view: UITableView, context: Context) {
        context.coordinator.parent = self
        view.reloadData()
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: SourceSwipeTable
        init(_ parent: SourceSwipeTable) { self.parent = parent }

        func numberOfSections(in tableView: UITableView) -> Int { 1 }
        func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "已添加" }
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            parent.urls.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "source")
                ?? UITableViewCell(style: .subtitle, reuseIdentifier: "source")
            let url = parent.urls[indexPath.row]
            cell.textLabel?.text = parent.names[url] ?? URL(string: url)?.host ?? "软件源"
            cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
            cell.detailTextLabel?.text = url
            cell.detailTextLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.numberOfLines = 2
            cell.selectionStyle = .none
            return cell
        }

        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard parent.urls.indices.contains(indexPath.row) else { return nil }
            let url = parent.urls[indexPath.row]
            let copy = UIContextualAction(style: .normal, title: "复制") { [weak self] _, _, finish in
                self?.parent.onCopy(url)
                finish(true)
            }
            copy.backgroundColor = .systemBlue
            let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, finish in
                self?.parent.onDelete(url)
                finish(true)
            }
            let actions = UISwipeActionsConfiguration(actions: [delete, copy])
            actions.performsFirstActionWithFullSwipe = false
            return actions
        }
    }
}
