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
    private var selectionMode = false
    private var selectedIDs = Set<UUID>()
    var isSelecting: Bool { selectionMode }
    func setSelecting(_ selecting: Bool) {
        selectionMode = selecting
        selectedIDs.removeAll()
        tableView.reloadData()
    }
    func selectAll() {
        selectedIDs = Set(visible.map { $0.id })
        tableView.reloadData()
    }
    func selectedPackages() -> [DownloadCenter.Item] {
        visible.filter { selectedIDs.contains($0.id) }
    }
    func deleteSelected() {
        let targets = selectedPackages()
        guard !targets.isEmpty else { return }
        let confirm = UIAlertController(title: "删除安装包", message: "删除选中的 \(targets.count) 项？", preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "取消", style: .cancel))
        confirm.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            for item in targets {
                switch item.state {
                case .completed: self.center.deleteDownloadedItem(item) { [weak self] error in self?.showError(error) }
                case .failed, .cancelled: self.center.removeTerminalItem(item)
                case .paused: self.center.removePausedItem(item)
                case .queued, .downloading: self.center.cancel(item)
                }
            }
            self.selectedIDs.removeAll()
        })
        present(confirm, animated: true)
    }
    override func loadView() {
        view = UIView()
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0)
        tableView.rowHeight = 96
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PackageDownloadCell.self, forCellReuseIdentifier: "Package")
        view.addSubview(tableView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Publishers.CombineLatest3(center.$activeItems, center.$completedItems, center.$terminalItems)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active, completed, terminal in
                self?.items = active + completed + terminal
                self?.applyFilter()
            }.store(in: &subscriptions)
        center.$extractionStatus.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &subscriptions)
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
            ($0.localURL?.lastPathComponent ?? $0.sourceURL.lastPathComponent)
                .localizedCaseInsensitiveContains(query)
        }
        tableView.reloadData()
        if visible.isEmpty {
            let label = UILabel(frame: tableView.bounds.insetBy(dx: 24, dy: 0))
            label.text = query.isEmpty ? "暂无安装包" : "没有匹配的安装包"
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            tableView.backgroundView = label
        } else { tableView.backgroundView = nil }
    }

    private func title(_ item: DownloadCenter.Item) -> String {
        item.localURL?.lastPathComponent ?? item.sourceURL.lastPathComponent
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visible.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Package", for: indexPath) as! PackageDownloadCell
        let item = visible[indexPath.row]
        let state: String
        let failure: Bool
        switch item.state {
        case .queued: state = "等待下载"; failure = false
        case .downloading: state = "\(Int(min(1, max(0, item.progress)) * 100))% · 下载中"; failure = false
        case .paused: state = "已暂停"; failure = false
        case .completed:
            state = "已下载 · " + (center.extractionStatus[item.localURL?.lastPathComponent ?? ""] ?? "等待解压")
            failure = state.contains("解压失败")
        case .failed: state = "下载失败 · 点击重试或删除"; failure = true
        case .cancelled: state = "已取消 · 点击重试或删除"; failure = true
        }
        cell.configure(name: title(item), status: state, progress: item.progress,
                       failed: failure, showProgress: item.state == .downloading)
        cell.accessoryType = selectionMode && selectedIDs.contains(item.id) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = visible[indexPath.row]
        if selectionMode {
            if !selectedIDs.insert(item.id).inserted { selectedIDs.remove(item.id) }
            tableView.reloadRows(at: [indexPath], with: .none)
            return
        }
        let sheet = UIAlertController(title: title(item), message: nil, preferredStyle: .actionSheet)
        func add(_ title: String, style: UIAlertAction.Style = .default, _ handler: @escaping () -> Void) {
            sheet.addAction(UIAlertAction(title: title, style: style) { _ in handler() })
        }
        switch item.state {
        case .queued, .downloading:
            if item.state == .downloading { add("暂停下载") { [weak self] in self?.center.pause(item) } }
            add("取消下载", style: .destructive) { [weak self] in self?.center.cancel(item) }
        case .paused:
            add("继续下载") { [weak self] in self?.center.resume(item) }
            add("删除任务", style: .destructive) { [weak self] in self?.center.removePausedItem(item) }
        case .failed, .cancelled:
            add("重试下载") { [weak self] in self?.center.enqueue(item.sourceURL) }
            add("删除失败记录", style: .destructive) { [weak self] in self?.center.removeTerminalItem(item) }
        case .completed:
            guard let url = item.localURL else { return }
            // No signing entry until a certificate-selection UI exists.
            if center.extractionStatus[url.lastPathComponent]?.hasPrefix("解压失败") == true ||
                center.extractionStatus[url.lastPathComponent] == "缓存已删除" {
                add("重新解压") { [weak self] in self?.center.retryExtraction(for: item) }
            }
            add("分享 IPA") { [weak self] in
                guard let self = self else { return }
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let popover = activity.popoverPresentationController {
                    popover.sourceView = self.tableView
                    popover.sourceRect = self.tableView.rectForRow(at: indexPath)
                }
                self.present(activity, animated: true)
            }
            add("删除解压缓存", style: .destructive) { [weak self] in
                self?.confirm("删除解压缓存", detail: "只删除解压目录，保留 IPA。") {
                    self?.center.removeExtractionCache(for: item) { [weak self] error in self?.showError(error) }
                }
            }
            add("删除 IPA", style: .destructive) { [weak self] in
                self?.confirm("删除 IPA", detail: "同时删除关联的解压缓存。") {
                    self?.center.deleteDownloadedItem(item) { [weak self] error in self?.showError(error) }
                }
            }
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(sheet, animated: true)
    }

    private func confirm(_ title: String, detail: String, work: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in work() })
        present(alert, animated: true)
    }

    private func showError(_ error: Error?) {
        guard let error = error else { return }
        let alert = UIAlertController(title: "操作失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

private final class PackageDownloadCell: UITableViewCell {
    private let card = UIView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .none
        backgroundColor = .clear
        card.backgroundColor = .white
        card.layer.cornerRadius = 16
        contentView.addSubview(card)
        nameLabel.font = .boldSystemFont(ofSize: 14)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.font = .systemFont(ofSize: 12)
        [nameLabel, statusLabel, progressView].forEach { card.addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("Programmatic only") }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = CGRect(x: 18, y: 0, width: max(0, contentView.bounds.width - 36), height: 88)
        nameLabel.frame = CGRect(x: 14, y: 11, width: max(0, card.bounds.width - 28), height: 23)
        statusLabel.frame = CGRect(x: 14, y: 40, width: max(0, card.bounds.width - 28), height: 21)
        progressView.frame = CGRect(x: 14, y: 71, width: max(0, card.bounds.width - 28), height: 4)
    }

    func configure(name: String, status: String, progress: Double, failed: Bool, showProgress: Bool) {
        nameLabel.text = name
        statusLabel.text = status
        statusLabel.textColor = failed ? .systemRed : .secondaryLabel
        progressView.progress = Float(min(1, max(0, progress)))
        progressView.isHidden = !showProgress
    }
}
