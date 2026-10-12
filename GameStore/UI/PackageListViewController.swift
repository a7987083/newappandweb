import UIKit
import Combine

/// Live download tasks and locally retained IPA archives.
final class PackageListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let tableView = UITableView(frame: .zero, style: .plain)
    var onSignPackage: ((URL) -> Void)?
    private let center = AppStoreViewModel.shared.downloadCenter
    private var items: [DownloadCenter.Item] = []
    private var visible: [DownloadCenter.Item] = []
    private var query = ""
    private var infoByPath = [String: AppPackageInfo]()
    private var metadataPending = Set<String>()
    private let metadataQueue = DispatchQueue(label: "com.GameStore.package.metadata", qos: .utility)
    private var subscriptions = Set<AnyCancellable>()
    private var selectionMode = false
    private var selectedIDs = Set<UUID>()
    var isSelecting: Bool { selectionMode }
    func setSelecting(_ selecting: Bool) {
        selectionMode = selecting
        selectedIDs.removeAll()
        tableView.reloadData()
    }
    func toggleSelectAll() {
        let visibleIDs = Set(visible.map { $0.id })
        if visibleIDs.isSubset(of: selectedIDs) { selectedIDs.subtract(visibleIDs) }
        else { selectedIDs.formUnion(visibleIDs) }
        tableView.reloadData()
    }
    func selectedPackages() -> [DownloadCenter.Item] {
        visible.filter { selectedIDs.contains($0.id) }
    }
    func deleteSelected() {
        let targets = selectedPackages()
        guard !targets.isEmpty else {
            let notice = UIAlertController(title: "未选择安装包", message: "请先选择要删除的项目", preferredStyle: .alert)
            notice.addAction(UIAlertAction(title: "确定", style: .default))
            present(notice, animated: true)
            return
        }
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
            self.tableView.reloadData()
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
        tableView.rowHeight = 112
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PackageDownloadCell.self, forCellReuseIdentifier: "Package")
        view.addSubview(tableView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        center.$completedItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completed in
                self?.items = completed
                self?.applyFilter()
                self?.readMetadata(completed)
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

    private func readMetadata(_ packages: [DownloadCenter.Item]) {
        let livePaths = Set(packages.compactMap { $0.localURL?.path })
        infoByPath = infoByPath.filter { livePaths.contains($0.key) }
        let missing = packages.compactMap { $0.localURL }.filter {
            infoByPath[$0.path] == nil && !metadataPending.contains($0.path)
        }
        guard !missing.isEmpty else { return }
        metadataPending.formUnion(missing.map(\.path))
        metadataQueue.async { [weak self] in
            let found = Dictionary(uniqueKeysWithValues: missing.compactMap { url -> (String, AppPackageInfo)? in
                guard let info = AppPackageInfo.read(from: url) else { return nil }
                return (url.path, info)
            })
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.metadataPending.subtract(missing.map(\.path))
                let stillPresent = Set(self.items.compactMap { $0.localURL?.path })
                self.infoByPath.merge(found.filter { stillPresent.contains($0.key) }) { _, newer in newer }
                self.applyFilter()
            }
        }
    }

    private func applyFilter() {
        visible = query.isEmpty ? items : items.filter {
            let filename = $0.localURL?.lastPathComponent ?? $0.sourceURL.lastPathComponent
            let info = $0.localURL.flatMap { infoByPath[$0.path] }
            return (filename + " " + (info?.name ?? "") + " " + (info?.bundleID ?? ""))
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
        let info = item.localURL.flatMap { infoByPath[$0.path] }
        cell.configure(name: info?.name ?? title(item),
                       status: info.map { "\($0.version) · \($0.sizeText)\n\($0.bundleID)\n\(title(item))" } ?? state,
                       progress: item.progress, failed: failure, showProgress: false,
                       icon: info?.icon)
        cell.accessoryType = selectionMode && selectedIDs.contains(item.id) ? .checkmark : .none
        cell.tintColor = .systemBlue
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
            add("签名") { [weak self] in
                guard FileManager.default.fileExists(atPath: url.path),
                      (try? DownloadIPAExtractor.preparedDirectory(for: url)) != nil else {
                    self?.showError(NSError(domain: "GameStore.PackageSigning", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "安装包尚未准备完成，请重新解压"]))
                    return
                }
                self?.onSignPackage?(url)
            }
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
    private let appIcon = UIImageView()

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
        appIcon.contentMode = .scaleAspectFit
        appIcon.layer.cornerRadius = 12
        appIcon.clipsToBounds = true
        statusLabel.numberOfLines = 3
        [nameLabel, statusLabel, progressView, appIcon].forEach { card.addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("Programmatic only") }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = CGRect(x: 18, y: 0, width: max(0, contentView.bounds.width - 36), height: 104)
        appIcon.frame = CGRect(x: 12, y: 20, width: 62, height: 62)
        let textWidth = max(0, card.bounds.width - 100)
        nameLabel.frame = CGRect(x: 84, y: 9, width: textWidth, height: 23)
        statusLabel.frame = CGRect(x: 84, y: 33, width: textWidth, height: 65)
        progressView.frame = CGRect(x: 84, y: 94, width: textWidth, height: 3)
    }

    func configure(name: String, status: String, progress: Double, failed: Bool, showProgress: Bool, icon: UIImage?) {
        appIcon.image = icon ?? UIImage(systemName: "app.fill")
        appIcon.tintColor = .systemGray3
        nameLabel.text = name
        statusLabel.text = status
        statusLabel.textColor = failed ? .systemRed : .secondaryLabel
        progressView.progress = Float(min(1, max(0, progress)))
        progressView.isHidden = !showProgress
    }
}


private struct AppPackageInfo {
    let name: String
    let version: String
    let bundleID: String
    let sizeText: String
    let icon: UIImage?

    static func read(from archive: URL) -> AppPackageInfo? {
        guard let directory = try? DownloadIPAExtractor.preparedDirectory(for: archive) else { return nil }
        let payload = directory.appendingPathComponent("Payload", isDirectory: true)
        guard let app = (try? FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension.lowercased() == "app" }),
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")),
              let bundle = info["CFBundleIdentifier"] as? String, !bundle.isEmpty else { return nil }
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String) ?? app.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String) ?? "未知"
        let bytes = (try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let iconNames = (info["CFBundleIcons"] as? [String: Any])
            .flatMap { $0["CFBundlePrimaryIcon"] as? [String: Any] }
            .flatMap { $0["CFBundleIconFiles"] as? [String] } ?? []
        let primaryName = (info["CFBundleIcons"] as? [String: Any])
            .flatMap { $0["CFBundlePrimaryIcon"] as? [String: Any] }
            .flatMap { $0["CFBundleIconName"] as? String }
        let candidates = (iconNames + [primaryName].compactMap { $0 } + ["AppIcon60x60", "AppIcon", "Icon"]).reversed()
        var icon: UIImage?
        // UIKit can resolve named images from a compiled Assets.car in the app bundle.
        if let bundle = Bundle(url: app) {
            for name in candidates {
                if let asset = UIImage(named: name, in: bundle, compatibleWith: nil) {
                    icon = asset
                    break
                }
            }
        }
        for candidate in candidates {
            for suffix in ["", "@3x", "@2x"] {
                let name = candidate + suffix + ".png"
                if let image = UIImage(contentsOfFile: app.appendingPathComponent(name).path) {
                    icon = image
                    break
                }
            }
            if icon != nil { break }
        }
        return AppPackageInfo(name: name, version: version, bundleID: bundle, sizeText: size, icon: icon)
    }
}
