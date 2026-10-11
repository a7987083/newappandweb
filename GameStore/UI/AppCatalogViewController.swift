import UIKit

/// Source applications list controller; the legacy shell owns search transitions
/// and floating navigation until those components are migrated separately.
@objc(AppCatalogViewController)
final class AppCatalogViewController: UIViewController, UITableViewDataSource {
    @objc let tableView = UITableView(frame: .zero, style: .plain)
    private var applications: [SourceCatalogApp] = []
    private var visibleIndices: [Int] = []
    private var query = ""
    private var observer: NSObjectProtocol?

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0)
        tableView.dataSource = self
        tableView.rowHeight = 78
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

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleIndices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "SourceApp", for: indexPath) as? AppCatalogCell else {
            return UITableViewCell()
        }
        let app = applications[visibleIndices[indexPath.row]]
        let detail = [app.version, app.bundleIdentifier].filter { !$0.isEmpty }.joined(separator: " · ")
        cell.configure(name: app.name, detail: detail,
                       category: app.category.isEmpty ? "软件源" : app.category,
                       iconURL: app.iconURL?.absoluteString ?? "")
        return cell
    }
}
