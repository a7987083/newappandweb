import UIKit
import Combine

/// Source applications list controller; the legacy shell owns search transitions
/// and floating navigation until those components are migrated separately.
@objc(AppCatalogViewController)
final class AppCatalogViewController: UIViewController, UITableViewDataSource {
    @objc let tableView = UITableView(frame: .zero, style: .plain)
    private var applications: [SourceCatalogApp] = []
    private var visibleIndices: [Int] = []
    private var query = ""
    private var observer: NSObjectProtocol?
    private var refreshSubscription: AnyCancellable?
    private weak var refreshAlert: UIAlertController?
    private var refreshRequested = false
    private var catalogHeader: UIView?

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0)
        tableView.dataSource = self
        tableView.rowHeight = 94
        tableView.register(AppCatalogCell.self, forCellReuseIdentifier: "SourceApp")
        view.addSubview(tableView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        SourceCatalogUIBridge.start()
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("GameStoreSourceCatalogDidChange"),
            object: nil, queue: .main
        ) { [weak self] _ in self?.reloadCatalog() }
        reloadCatalog()
    }

    @objc(installHeader:)
    func installHeader(_ header: UIView) {
        catalogHeader = header
        tableView.tableHeaderView = header
    }

    @objc(setHeaderCollapsed:)
    func setHeaderCollapsed(_ collapsed: Bool) {
        guard let header = catalogHeader else { return }
        var frame = header.frame
        let height = headerHeight
        frame.size.height = collapsed ? 0 : height
        header.frame = frame
        tableView.tableHeaderView = header
    }

    private var headerHeight: CGFloat = 0

    @objc(setCatalogHeader:height:)
    func setCatalogHeader(_ header: UIView, height: CGFloat) {
        headerHeight = height
        installHeader(header)
    }

    /// Presents the same alert style as source registration but waits for
    /// the actual catalog refresh, not just the registration request.
    @objc(refreshSourceCatalog)
    func refreshSourceCatalog() {
        let store = SoftwareSourceStore.shared
        guard !store.sources.isEmpty else {
            showRefreshMessage("尚未添加软件源", "请先前往「设置 → 软件源」添加软件源。")
            return
        }
        guard !refreshRequested, !store.isCatalogLoading else { return }
        refreshRequested = true
        let alert = UIAlertController(title: "正在刷新软件源",
                                      message: "正在请求并解析软件源…",
                                      preferredStyle: .alert)
        refreshAlert = alert
        refreshSubscription = store.$isCatalogLoading
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                guard let self = self, self.refreshRequested, !loading else { return }
                self.refreshRequested = false
                self.refreshSubscription = nil
                let error = store.catalogError
                self.refreshAlert?.dismiss(animated: true) { [weak self] in
                    if let error = error {
                        self?.showRefreshMessage("软件源刷新提示", error)
                    }
                }
            }
        present(alert, animated: true)
        store.refreshCatalog()
    }

    private func showRefreshMessage(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    @objc(filterWithQuery:)
    func filter(query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFilter()
    }

    private func reloadCatalog() {
        applications = SoftwareSourceStore.shared.catalogApps
        applyFilter()
    }

    private func applyFilter() {
        if query.isEmpty {
            visibleIndices = Array(applications.indices)
        } else {
            visibleIndices = applications.indices.filter { index in
                let app = applications[index]
                return app.name.localizedCaseInsensitiveContains(query) ||
                    app.bundleIdentifier.localizedCaseInsensitiveContains(query) ||
                    app.version.localizedCaseInsensitiveContains(query)
            }
        }
        tableView.reloadData()
        if visibleIndices.isEmpty {
            let label = UILabel()
            label.text = SoftwareSourceStore.shared.sources.isEmpty
                ? "尚未添加软件源，请前往「设置 → 软件源」添加"
                : "暂无软件源应用（正在同步或软件源为空）"
            label.font = .systemFont(ofSize: 15)
            label.textColor = UIColor(red: 142/255, green: 142/255, blue: 147/255, alpha: 1)
            label.textAlignment = .center
            label.numberOfLines = 0
            label.frame = CGRect(x: 20, y: 60, width: max(0, tableView.bounds.width-40), height: 90)
            let holder = UIView(frame: tableView.bounds)
            holder.addSubview(label)
            tableView.backgroundView = holder
        } else {
            tableView.backgroundView = nil
        }
    }

    func appID(atVisibleRow row: Int) -> String? {
        guard visibleIndices.indices.contains(row) else { return nil }
        return applications[visibleIndices[row]].id
    }

    func visibleRow(forAppID id: String) -> Int? {
        visibleIndices.firstIndex { applications[$0].id == id }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleIndices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "SourceApp", for: indexPath) as? AppCatalogCell else {
            return UITableViewCell()
        }
        let app = applications[visibleIndices[indexPath.row]]
        let size = app.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
        let date: String
        if let updated = app.updatedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.string(from: updated)
        } else {
            date = "—"
        }
        let unlocked = SourceUnlockService.shared.isUnlocked(app, udid: UDIDService.shared.udid)
        cell.configureUnlock(app.requiresUnlock == true && !unlocked, available: app.unlockURL != nil)
        cell.onUnlock = { [weak self] in self?.presentUnlock(for: app) }
        cell.configure(name: app.name,
                       metadata: "\(app.version.isEmpty ? "—" : app.version) · \(size) · \(date)",
                       descriptionText: app.description,
                       iconURL: app.iconURL?.absoluteString ?? "")
        return cell
    }
    private func presentUnlock(for app: SourceCatalogApp) {
        guard app.requiresUnlock == true, app.unlockURL != nil else { return }
        guard let udid = UDIDService.shared.udid, !udid.isEmpty else {
            showRefreshMessage("需要设备 UDID", "请先在设置中获取设备 UDID")
            return
        }
        let alert = UIAlertController(title: "使用解锁码", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "请输入卡密" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "使用解锁码", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let code = alert?.textFields?.first?.text ?? ""
            SourceUnlockService.shared.unlock(app: app, udid: udid, code: code) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.showRefreshMessage("解锁成功", "已通过服务器授权校验，正在刷新软件源")
                        SoftwareSourceStore.shared.refreshCatalog()
                        self.tableView.reloadData()
                    case .failure(let error):
                        self.showRefreshMessage("解锁失败", error.localizedDescription)
                    }
                }
            }
        })
        present(alert, animated: true)
    }

}
