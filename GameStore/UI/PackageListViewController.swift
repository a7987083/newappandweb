import UIKit
import Combine

/// Live download tasks and locally retained IPA archives.
final class PackageListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let tableView = UITableView(frame: .zero, style: .plain)
    private let center = AppStoreViewModel.shared.downloadCenter
    private var items: [DownloadCenter.Item] = []
    private var visible: [DownloadCenter.Item] = []
    private var query = ""
    private var subscriptions = Set<AnyCancellable>()
    private var inspected = [String: String]()
    private var inspecting = Set<String>()

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0)
        tableView.rowHeight = 106
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PackageDownloadCell.self, forCellReuseIdentifier: "Package")
        view.addSubview(tableView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Subscribe to all three published arrays, not just active transfers.
        Publishers.CombineLatest3(center.$activeItems, center.$completedItems, center.$terminalItems)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active, completed, terminal in
                self?.items = active + completed + terminal
                self?.applyFilter()
            }.store(in: &subscriptions)
        center.reloadDownloadedItems()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        center.reloadDownloadedItems()
    }

    func filter(query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFilter()
    }

    private func applyFilter() {
        visible = query.isEmpty ? items : items.filter {
            displayName($0).localizedCaseInsensitiveContains(query)
        }
        tableView.reloadData()
        if visible.isEmpty {
            let holder = UIView(frame: tableView.bounds)
            let label = UILabel(frame: CGRect(x: 20, y: 62, width: max(0, tableView.bounds.width - 40), height: 90))
            label.text = query.isEmpty ? "暂无安装包\n在应用页面点击「获取」后，下载任务会显示在这里" : "没有匹配的安装包"
            label.font = .systemFont(ofSize: 15)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            holder.addSubview(label)
            tableView.backgroundView = holder
        } else {
            tableView.backgroundView = nil
        }
    }

    private func displayName(_ item: DownloadCenter.Item) -> String {
        item.localURL?.lastPathComponent ?? item.sourceURL.lastPathComponent
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visible.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Package", for: indexPath) as! PackageDownloadCell
        let item = visible[indexPath.row]
        let status: String
        let action: String?
        switch item.state {
        case .queued: status = "等待下载"; action = nil
        case .downloading: status = "\(Int(min(1, max(0, item.progress)) * 100))% · 下载中"; action = "暂停"
        case .paused: status = "已暂停"; action = "继续"
        case .completed: status = "已下载"; action = "检查"
        case .failed: status = item.errorDescription ?? "下载失败"; action = "重试"
        case .cancelled: status = "已取消"; action = "重试"
        }
        cell.configure(name: displayName(item), status: status, progress: item.progress,
                       action: action, completed: item.state == .completed)
        cell.onAction = { [weak self] in self?.performAction(item) }
        cell.onDelete = { [weak self] in self?.confirmDelete(item) }
        return cell
    }

    private func performAction(_ item: DownloadCenter.Item) {
        switch item.state {
        case .downloading: center.pause(item)
        case .paused: center.resume(item)
        case .failed, .cancelled: center.enqueue(item.sourceURL)
        case .completed:
            guard let url = item.localURL else { return }
            inspect(url)
        case .queued: break
        }
    }

    private func inspect(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !inspecting.contains(path) else { return }
        inspecting.insert(path)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let message: String
            do {
                let result = try IPAInspector.inspect(url)
                message = "\(result.displayName) · \(result.version) · \(result.bundleID)\nSHA-256: \(result.sha256)"
            } catch {
                message = "IPA 校验失败：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.inspecting.remove(path)
                self.inspected[path] = message
                let alert = UIAlertController(title: "安装包检查", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func confirmDelete(_ item: DownloadCenter.Item) {
        guard item.state == .completed else { return }
        let alert = UIAlertController(title: "删除安装包", message: "确定删除「\(displayName(item))」？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.center.deleteDownloadedItem(item) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    let failure = UIAlertController(title: "删除失败", message: error.localizedDescription, preferredStyle: .alert)
                    failure.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(failure, animated: true)
                } else {
                    self.items = self.center.items
                    self.applyFilter()
                }
            }
        })
        present(alert, animated: true)
    }
}

private final class PackageDownloadCell: UITableViewCell {
    private let card = UIView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let actionButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    var onAction: (() -> Void)?
    var onDelete: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        card.backgroundColor = .white
        card.layer.cornerRadius = 16
        contentView.addSubview(card)
        nameLabel.font = .boldSystemFont(ofSize: 14)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        actionButton.titleLabel?.font = .boldSystemFont(ofSize: 12)
        actionButton.addTarget(self, action: #selector(act), for: .touchUpInside)
        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = .systemRed
        deleteButton.addTarget(self, action: #selector(remove), for: .touchUpInside)
        [nameLabel, statusLabel, progressView, actionButton, deleteButton].forEach(card.addSubview)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic only") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onAction = nil
        onDelete = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = CGRect(x: 18, y: 0, width: max(0, contentView.bounds.width - 36), height: 98)
        let width = max(0, card.bounds.width - 104)
        nameLabel.frame = CGRect(x: 14, y: 13, width: width, height: 23)
        statusLabel.frame = CGRect(x: 14, y: 40, width: width, height: 19)
        progressView.frame = CGRect(x: 14, y: 75, width: max(0, card.bounds.width - 28), height: 4)
        actionButton.frame = CGRect(x: card.bounds.width - 83, y: 14, width: 64, height: 32)
        deleteButton.frame = CGRect(x: card.bounds.width - 49, y: 49, width: 30, height: 30)
    }

    func configure(name: String, status: String, progress: Double, action: String?, completed: Bool) {
        nameLabel.text = name
        statusLabel.text = status
        progressView.progress = Float(min(1, max(0, progress)))
        progressView.isHidden = completed
        actionButton.setTitle(action, for: .normal)
        actionButton.isHidden = action == nil
        deleteButton.isHidden = !completed
    }

    @objc private func act() { onAction?() }
    @objc private func remove() { onDelete?() }
}
