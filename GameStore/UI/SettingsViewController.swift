import UIKit

// Settings UI only. All status strings and actions below are presentation placeholders.
// Keep both the settings page and its device-auth detail in this one Swift file.
@objc(SettingsViewController)
final class SettingsViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var authStatusLabel: UILabel?
    private var authDescriptionLabel: UILabel?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateAuthSummary()
    }

    private func updateAuthSummary() {
        let present = UDIDService.shared.udid.map { UDIDLocalServer.validUDID($0) } ?? false
        authStatusLabel?.text = present ? "已获取 UDID" : "未认证"
        authDescriptionLabel?.text = present ? "设备注册状态未知" : "udid未注册，不可正常安装应用"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SettingsStyle.background
        SettingsStyle.embed(scroll: scroll, stack: stack, in: view, bottomInset: 105)

        stack.addArrangedSubview(SettingsStyle.text("设置", size: 37, bold: true))
        let note = SettingsStyle.text("设备管理与应用设置", size: 14, color: SettingsStyle.secondary)
        stack.addArrangedSubview(note)
        SettingsStyle.section("设备管理", in: stack)

        let auth = UIButton(type: .custom)
        auth.backgroundColor = .white
        auth.layer.cornerRadius = 18
        auth.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let icon = SettingsStyle.statusIcon(registered: false, diameter: 48)
        icon.translatesAutoresizingMaskIntoConstraints = false
        auth.addSubview(icon)
        let statusLabel = SettingsStyle.text("未认证", size: 14, color: .systemRed)
        let descriptionLabel = SettingsStyle.text("udid未注册，不可正常安装应用", size: 12, color: SettingsStyle.secondary)
        authStatusLabel = statusLabel
        authDescriptionLabel = descriptionLabel
        let texts = UIStackView(arrangedSubviews: [
            SettingsStyle.text("设备认证", size: 17, bold: true),
            statusLabel,
            descriptionLabel
        ])
        texts.axis = .vertical
        texts.spacing = 3
        texts.translatesAutoresizingMaskIntoConstraints = false
        auth.addSubview(texts)
        let arrow = UIImageView(image: UIImage(systemName: "chevron.right"))
        arrow.tintColor = SettingsStyle.secondary
        arrow.translatesAutoresizingMaskIntoConstraints = false
        auth.addSubview(arrow)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: auth.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: auth.centerYAnchor),
            texts.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            texts.centerYAnchor.constraint(equalTo: auth.centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: arrow.leadingAnchor, constant: -7),
            arrow.trailingAnchor.constraint(equalTo: auth.trailingAnchor, constant: -15),
            arrow.centerYAnchor.constraint(equalTo: auth.centerYAnchor)
        ])
        auth.addTarget(self, action: #selector(openDeviceAuth), for: .touchUpInside)
        stack.addArrangedSubview(auth)
        updateAuthSummary()

        SettingsStyle.section("功能", in: stack)
        let source = placeholder("软件源", icon: "tray.full.fill")
        source.removeTarget(self, action: #selector(placeholderTapped(_:)), for: .touchUpInside)
        source.addTarget(self, action: #selector(openSources), for: .touchUpInside)
        stack.addArrangedSubview(source)
        let signing = placeholder("签名设置", icon: "signature")
        signing.removeTarget(self, action: #selector(placeholderTapped(_:)), for: .touchUpInside)
        signing.addTarget(self, action: #selector(openSigningSettings), for: .touchUpInside)
        stack.addArrangedSubview(signing)
        let plugins = placeholder("动态库/插件", icon: "puzzlepiece.extension.fill")
        plugins.removeTarget(self, action: #selector(placeholderTapped(_:)), for: .touchUpInside)
        plugins.addTarget(self, action: #selector(openPlugins), for: .touchUpInside)
        stack.addArrangedSubview(plugins)
        let about = placeholder("关于我们", icon: "info.circle.fill")
        about.removeTarget(self, action: #selector(placeholderTapped(_:)), for: .touchUpInside)
        about.addTarget(self, action: #selector(openAbout), for: .touchUpInside)
        stack.addArrangedSubview(about)
    }

    private func placeholder(_ title: String, icon: String, tint: UIColor = SettingsStyle.blue) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = .white
        button.layer.cornerRadius = 18
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        let image = UIImageView(image: UIImage(systemName: icon))
        image.tintColor = tint
        image.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(image)
        let label = SettingsStyle.text(title, size: 16, color: tint == .systemRed ? .systemRed : .black)
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 21),
            image.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 24),
            image.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 61),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        button.accessibilityIdentifier = title
        button.addTarget(self, action: #selector(placeholderTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func placeholderTapped(_ sender: UIButton) {
        let alert = UIAlertController(title: sender.accessibilityIdentifier, message: "当前仅为 UI 占位。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    @objc private func openPlugins() {
        let page = PluginLibraryController()
        page.modalPresentationStyle = .fullScreen
        present(page, animated: true)
    }

    @objc private func openAbout() {
        let page = AboutSettingsController()
        page.modalPresentationStyle = .fullScreen
        present(page, animated: true)
    }

    @objc private func openSigningSettings() {
        let detail = SigningSettingsController()
        detail.modalPresentationStyle = .fullScreen
        present(detail, animated: true)
    }

    @objc private func openSources() {
        let controller = SoftwareSourcesSettingsController()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    @objc private func openDeviceAuth() {
        let detail = DeviceAuthDetailController()
        detail.modalPresentationStyle = .fullScreen
        present(detail, animated: true)
    }
}


// Software sources settings: private UIKit screen, deliberately kept in this UI file.
// Source validation, persistence and network decoding remain in SoftwareSourceStore.
private final class SoftwareSourcesSettingsController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let store = SoftwareSourceStore.shared
    private let table = UITableView(frame: .zero, style: .grouped)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyLabel = SettingsStyle.text("暂无软件源\n点击右上角 + 添加 HTTP/HTTPS 软件源地址", size: 15, color: SettingsStyle.secondary)
    private var activeRequest = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SettingsStyle.background
        let header = SettingsDetailLayout.header(in: self, title: "软件源", back: #selector(close),
                                                  accessory: ("plus", #selector(addSource)))
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = SettingsStyle.background
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 76
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: header.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        spinner.hidesWhenStopped = true
        refreshList()
    }

    private func refreshList() {
        table.reloadData()
        if store.sources.isEmpty {
            let empty = UIView(frame: CGRect(x: 0, y: 0, width: max(view.bounds.width, 280), height: 210))
            emptyLabel.frame = CGRect(x: 20, y: 40, width: empty.bounds.width - 40, height: 100)
            empty.addSubview(emptyLabel)
            table.backgroundView = empty
        } else {
            table.backgroundView = nil
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { store.sources.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        store.sources.isEmpty ? nil : "已添加"
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "source")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "source")
        let address = store.sources[indexPath.row]
        cell.textLabel?.text = store.sourceNames[address] ?? URL(string: address)?.host ?? "软件源"
        cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = address
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = SettingsStyle.secondary
        cell.selectionStyle = .none
        return cell
    }
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard store.sources.indices.contains(indexPath.row) else { return nil }
        let address = store.sources[indexPath.row]
        let copy = UIContextualAction(style: .normal, title: "复制") { _, _, done in
            UIPasteboard.general.string = address
            done(true)
        }
        copy.backgroundColor = SettingsStyle.blue
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            self?.store.remove(address)
            self?.refreshList()
            done(true)
        }
        let actions = UISwipeActionsConfiguration(actions: [delete, copy])
        actions.performsFirstActionWithFullSwipe = false
        return actions
    }

    @objc private func addSource() {
        guard !activeRequest else { return }
        let alert = UIAlertController(title: "添加软件源", message: "请输入 HTTP 或 HTTPS 软件源地址", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://example.com/repo.json"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "添加", style: .default) { [weak self, weak alert] _ in
            self?.register(alert?.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }

    private func register(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty else {
            showError("请输入有效的 HTTP 或 HTTPS 软件源地址。")
            return
        }
        guard !store.sources.contains(url.absoluteString) else {
            showError("该软件源已经添加。")
            return
        }
        activeRequest = true
        let loading = UIAlertController(title: "正在添加软件源", message: "正在请求并解析软件源…", preferredStyle: .alert)
        present(loading, animated: true)
        store.add(url) { [weak self, weak loading] result in
            DispatchQueue.main.async {
                self?.activeRequest = false
                loading?.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success: self.refreshList()
                    case .failure(let error): self.showError(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "添加软件源失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    @objc private func close() { dismiss(animated: true) }
}

// Local presentation-only detail controller; intentionally not registered as a separate source file.
private final class DeviceAuthDetailController: UIViewController {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var stateTitle: UILabel?
    private var stateDescription: UILabel?
    private var udidDisplay: UILabel?
    private var acquireButton: UIButton?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshUDID()
    }

    @objc private func refreshUDID() {
        let valid = UDIDService.shared.udid.flatMap { UDIDLocalServer.validUDID($0) ? $0 : nil }
        stateTitle?.text = valid == nil ? "未认证" : "已获取 UDID"
        stateDescription?.text = valid == nil ? "udid未注册，不可正常安装应用" : "设备注册状态未知"
        udidDisplay?.text = valid ?? "未获取"
        acquireButton?.setTitle(valid == nil ? "获取设备 UDID" : "重新获取 UDID", for: .normal)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SettingsStyle.background
        NotificationCenter.default.addObserver(self, selector: #selector(refreshUDID),
                                               name: UDIDService.didUpdateNotification, object: nil)
        let header = SettingsDetailLayout.header(in: self, title: "设备认证", back: #selector(close))
        SettingsStyle.embed(scroll: scroll, stack: stack, in: view, top: header.bottomAnchor, bottomInset: 20)

        let stateCard = SettingsStyle.card()
        let stateIcon = SettingsStyle.statusIcon(registered: false, diameter: 60)
        stateIcon.translatesAutoresizingMaskIntoConstraints = false
        let title = SettingsStyle.text("未认证", size: 21, bold: true)
        let desc = SettingsStyle.text("udid未注册，不可正常安装应用", size: 14, color: SettingsStyle.secondary)
        stateTitle = title
        stateDescription = desc
        let stateText = UIStackView(arrangedSubviews: [title, desc])
        stateText.axis = .vertical
        stateText.spacing = 6
        stateText.translatesAutoresizingMaskIntoConstraints = false
        stateCard.addSubview(stateIcon)
        stateCard.addSubview(stateText)
        stateCard.heightAnchor.constraint(equalToConstant: 110).isActive = true
        NSLayoutConstraint.activate([
            stateIcon.leadingAnchor.constraint(equalTo: stateCard.leadingAnchor, constant: 20),
            stateIcon.centerYAnchor.constraint(equalTo: stateCard.centerYAnchor),
            stateText.leadingAnchor.constraint(equalTo: stateIcon.trailingAnchor, constant: 18),
            stateText.centerYAnchor.constraint(equalTo: stateCard.centerYAnchor),
            stateText.trailingAnchor.constraint(lessThanOrEqualTo: stateCard.trailingAnchor, constant: -12)
        ])
        stack.addArrangedSubview(stateCard)

        let info = SettingsStyle.card()
        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        info.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: info.topAnchor),
            rows.leadingAnchor.constraint(equalTo: info.leadingAnchor, constant: 17),
            rows.trailingAnchor.constraint(equalTo: info.trailingAnchor, constant: -17),
            rows.bottomAnchor.constraint(equalTo: info.bottomAnchor)
        ])
        let udidRow = infoRow("UDID", value: "未获取", symbol: "doc.on.doc")
        rows.addArrangedSubview(udidRow)
        udidDisplay = udidRow.subviews.compactMap { $0 as? UILabel }.last
        rows.addArrangedSubview(SettingsStyle.separator())
        rows.addArrangedSubview(infoRow("注册状态", value: "未知", valueColor: SettingsStyle.secondary))
        rows.addArrangedSubview(SettingsStyle.separator())
        rows.addArrangedSubview(infoRow("注册时间", value: "—"))
        stack.addArrangedSubview(info)

        let request = actionButton("获取设备 UDID", filled: true)
        request.addTarget(self, action: #selector(requestUDID), for: .touchUpInside)
        acquireButton = request
        stack.addArrangedSubview(request)
        stack.addArrangedSubview(actionButton("打开官网注册", filled: false))

        let tips = SettingsStyle.card()
        let hint = SettingsStyle.text("提示\n\n1. 点击「获取设备 UDID」获取本机 UDID\n2. 在官网注册并绑定设备\n3. 注册成功后即可安装应用", size: 14, color: SettingsStyle.secondary)
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        tips.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: tips.topAnchor, constant: 17),
            hint.bottomAnchor.constraint(equalTo: tips.bottomAnchor, constant: -17),
            hint.leadingAnchor.constraint(equalTo: tips.leadingAnchor, constant: 17),
            hint.trailingAnchor.constraint(equalTo: tips.trailingAnchor, constant: -17)
        ])
        stack.addArrangedSubview(tips)
        refreshUDID()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func requestUDID() {
        UDIDService.shared.requestProfileConfiguration()
    }

    @objc private func copyUDID() {
        guard let value = UDIDService.shared.udid,
              UDIDLocalServer.validUDID(value) else { return }
        UIPasteboard.general.string = value
    }

    private func infoRow(_ title: String, value: String, symbol: String? = nil, valueColor: UIColor = SettingsStyle.secondary) -> UIView {
        let row = UIView()
        row.heightAnchor.constraint(equalToConstant: 54).isActive = true
        let label = SettingsStyle.text(title, size: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        let result = SettingsStyle.text(value, size: 14, color: valueColor)
        result.lineBreakMode = .byTruncatingMiddle
        result.numberOfLines = 1
        result.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(result)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            result.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            result.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12)
        ])
        if symbol == nil {
            result.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
        }
        if let symbol = symbol {
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = SettingsStyle.blue
            icon.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(icon)
            if title == "UDID" {
                let tap = UITapGestureRecognizer(target: self, action: #selector(copyUDID))
                row.addGestureRecognizer(tap)
                row.isUserInteractionEnabled = true
            }
            NSLayoutConstraint.activate([
                icon.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                result.trailingAnchor.constraint(equalTo: icon.leadingAnchor, constant: -9)
            ])
        }
        return row
    }

    private func actionButton(_ title: String, filled: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.layer.cornerRadius = 14
        button.backgroundColor = filled ? SettingsStyle.blue : UIColor(red: 0.89, green: 0.93, blue: 1.0, alpha: 1)
        button.setTitle(title, for: .normal)
        button.setTitleColor(filled ? .white : SettingsStyle.blue, for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 17)
        button.heightAnchor.constraint(equalToConstant: 56).isActive = true
        if !filled {
            button.addTarget(self, action: #selector(showNotConnected), for: .touchUpInside)
        }
        return button
    }

    @objc private func showNotConnected() {
        let alert = UIAlertController(title: "界面占位", message: "此按钮暂未接入业务逻辑。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    @objc private func close() { dismiss(animated: true) }
}


private final class SigningSettingsController: UIViewController {
    private let store = SigningOptionsStore.shared
    private var switches: [UISwitch] = []
    private weak var packagingButton: UIButton?
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SettingsStyle.background
        let header = SettingsDetailLayout.header(in: self, title: "签名设置", back: #selector(close))
        SettingsStyle.embed(scroll: scroll, stack: stack, in: view, top: header.bottomAnchor, bottomInset: 22)

        SettingsStyle.section("证书管理", in: stack)
        let certificate = UIButton(type: .system)
        certificate.backgroundColor = .white
        certificate.layer.cornerRadius = 16
        certificate.heightAnchor.constraint(equalToConstant: 54).isActive = true
        certificate.setTitle("导入证书 ›", for: .normal)
        certificate.setTitleColor(SettingsStyle.blue, for: .normal)
        certificate.addTarget(self, action: #selector(openCertificates), for: .touchUpInside)
        stack.addArrangedSubview(certificate)
        stack.addArrangedSubview(SettingsStyle.text("支持导入 P12 和 mobileprovision，证书密码只用于校验。", size: 13, color: SettingsStyle.secondary))

        SettingsStyle.section("应用能力", in: stack)
        addSwitch("强制本地化", key: 0, value: store.options.forceLocalization)
        addSwitch("文件共享", key: 1, value: store.options.fileSharing)
        addSwitch("iTunes 文件共享", key: 2, value: store.options.itunesFileSharing)
        addSwitch("ProMotion", key: 3, value: store.options.proMotion)
        addSwitch("游戏模式", key: 4, value: store.options.gameMode)
        addSwitch("iPad 全屏", key: 5, value: store.options.ipadFullscreen)

        SettingsStyle.section("签名行为", in: stack)
        addSwitch("Ad-hoc 伪签名", key: 6, value: store.options.temporarySigning)
        addSwitch("签名完成自动安装", key: 7, value: store.options.autoInstallAfterSigning)
        addSwitch("注册回调", key: 8, value: store.options.registerCallback)
        stack.addArrangedSubview(SettingsStyle.text("临时签署使用 Zsign Ad-hoc 伪签名；注册回调用于向目标 App 注册 UDID URL Scheme。", size: 12, color: SettingsStyle.secondary))

        SettingsStyle.section("打包规则", in: stack)
        let packaging = UIButton(type: .system)
        packaging.backgroundColor = .white
        packaging.layer.cornerRadius = 16
        packaging.heightAnchor.constraint(equalToConstant: 54).isActive = true
        packaging.setTitle("打包规则：\(store.options.packagingRule.title)  ›", for: .normal)
        packaging.setTitleColor(.black, for: .normal)
        packaging.addTarget(self, action: #selector(selectPackaging(_:)), for: .touchUpInside)
        packagingButton = packaging
        stack.addArrangedSubview(packaging)

        let reset = UIButton(type: .system)
        reset.backgroundColor = .white
        reset.layer.cornerRadius = 16
        reset.heightAnchor.constraint(equalToConstant: 54).isActive = true
        reset.setTitle("恢复默认设置", for: .normal)
        reset.setTitleColor(.systemRed, for: .normal)
        reset.addTarget(self, action: #selector(resetSettings), for: .touchUpInside)
        stack.addArrangedSubview(reset)
    }

    private func addSwitch(_ title: String, key: Int, value: Bool) {
        let row = UIView()
        row.backgroundColor = .white
        row.layer.cornerRadius = 16
        row.heightAnchor.constraint(equalToConstant: 54).isActive = true
        let label = SettingsStyle.text(title, size: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        let toggle = UISwitch()
        toggle.isOn = value
        toggle.tag = key
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(changeOption(_:)), for: .valueChanged)
        switches.append(toggle)
        row.addSubview(toggle)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 17),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -17),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8)
        ])
        stack.addArrangedSubview(row)
    }

    @objc private func changeOption(_ sender: UISwitch) {
        var options = store.options
        switch sender.tag {
        case 0: options.forceLocalization = sender.isOn
        case 1: options.fileSharing = sender.isOn
        case 2: options.itunesFileSharing = sender.isOn
        case 3: options.proMotion = sender.isOn
        case 4: options.gameMode = sender.isOn
        case 5: options.ipadFullscreen = sender.isOn
        case 6: options.temporarySigning = sender.isOn
        case 7: options.autoInstallAfterSigning = sender.isOn
        case 8: options.registerCallback = sender.isOn
        default: return
        }
        store.options = options
    }

    @objc private func selectPackaging(_ sender: UIButton) {
        let sheet = UIAlertController(title: "打包规则", message: nil, preferredStyle: .actionSheet)
        for rule in SigningPackagingRule.allCases {
            sheet.addAction(UIAlertAction(title: rule.title, style: .default) { [weak self, weak sender] _ in
                guard let self = self else { return }
                var options = self.store.options
                options.packagingRule = rule
                self.store.options = options
                sender?.setTitle("打包规则：\(rule.title)  ›", for: .normal)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func resetSettings() {
        let alert = UIAlertController(title: "恢复默认设置", message: "确定恢复所有签名设置？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "恢复", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.store.resetToDefaults()
            for toggle in self.switches {
                switch toggle.tag {
                case 0: toggle.isOn = self.store.options.forceLocalization
                case 1: toggle.isOn = self.store.options.fileSharing
                case 2: toggle.isOn = self.store.options.itunesFileSharing
                case 3: toggle.isOn = self.store.options.proMotion
                case 4: toggle.isOn = self.store.options.gameMode
                case 5: toggle.isOn = self.store.options.ipadFullscreen
                case 6: toggle.isOn = self.store.options.temporarySigning
                case 7: toggle.isOn = self.store.options.autoInstallAfterSigning
                case 8: toggle.isOn = self.store.options.registerCallback
                default: break
                }
            }
            self.packagingButton?.setTitle("打包规则：\(self.store.options.packagingRule.title)  ›", for: .normal)
        })
        present(alert, animated: true)
    }

    @objc private func openCertificates() {
        let page = CertificateSettingsController()
        page.modalPresentationStyle = .fullScreen
        present(page, animated: true)
    }

    @objc private func close() { dismiss(animated: true) }
}


// Shared full-screen presentation chrome for every settings subpage.
// All layout lives here; the TrollSkin floating tab dock remains on the parent screen.
private enum SettingsDetailLayout {
    static func header(in owner: UIViewController, title: String, back: Selector,
                       accessory: (symbol: String, action: Selector)? = nil) -> UIView {
        owner.view.backgroundColor = SettingsStyle.background
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        owner.view.addSubview(header)
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = SettingsStyle.blue
        button.addTarget(owner, action: back, for: .touchUpInside)
        header.addSubview(button)
        let heading = SettingsStyle.text(title, size: 19, bold: true)
        heading.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(heading)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: owner.view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: owner.view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: owner.view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 50),
            button.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            button.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40),
            heading.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            heading.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        if let accessory = accessory {
            let trailing = UIButton(type: .system)
            trailing.translatesAutoresizingMaskIntoConstraints = false
            trailing.setImage(UIImage(systemName: accessory.symbol), for: .normal)
            trailing.tintColor = SettingsStyle.blue
            trailing.addTarget(owner, action: accessory.action, for: .touchUpInside)
            header.addSubview(trailing)
            NSLayoutConstraint.activate([
                trailing.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
                trailing.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                trailing.widthAnchor.constraint(equalToConstant: 40),
                trailing.heightAnchor.constraint(equalToConstant: 40)
            ])
        }
        return header
    }
}


private final class AboutSettingsController: UIViewController {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let schemes: [(String, String, String)] = [
        ("App 内打开网页", "zonoe://web?url=https%3A%2F%2Fexample.com", "在 zonoe 内使用 Safari View 打开 HTTP/HTTPS 网页。"),
        ("下载 IPA", "zonoe://download/https%3A%2F%2Fexample.com%2Fapp.ipa", "将 HTTP/HTTPS IPA 地址加入下载队列。"),
        ("下载 IPA（install 兼容入口）", "zonoe://install/https%3A%2F%2Fexample.com%2Fapp.ipa", "与 download 相同，加入下载队列。"),
        ("UDID Provider", "zonoe://udid?callback=example%3A%2F%2Fcallback", "将已保存的 UDID 返回给请求方；未获取时先走设备信息获取流程。")
    ]
    override func viewDidLoad() {
        super.viewDidLoad()
        let header = SettingsDetailLayout.header(in: self, title: "关于我们", back: #selector(close))
        SettingsStyle.embed(scroll: scroll, stack: stack, in: view, top: header.bottomAnchor, bottomInset: 20)
        stack.addArrangedSubview(SettingsStyle.text("zonoe", size: 25, bold: true))
        SettingsStyle.section("URL Scheme 说明", in: stack)
        for (index, entry) in schemes.enumerated() {
            let card = SettingsStyle.card()
            let title = SettingsStyle.text(entry.0, size: 16, bold: true)
            let uri = SettingsStyle.text(entry.1, size: 12)
            uri.lineBreakMode = .byCharWrapping
            let note = SettingsStyle.text(entry.2, size: 13, color: SettingsStyle.secondary)
            let copy = UIButton(type: .system)
            copy.setTitle("复制", for: .normal)
            copy.tag = index
            copy.addTarget(self, action: #selector(copyScheme(_:)), for: .touchUpInside)
            let content = UIStackView(arrangedSubviews: [title, uri, note, copy])
            content.axis = .vertical
            content.alignment = .leading
            content.spacing = 9
            content.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
                content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
                content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
                content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
            ])
            stack.addArrangedSubview(card)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        stack.addArrangedSubview(SettingsStyle.text("v\(version)-dev", size: 13, color: SettingsStyle.secondary))
    }
    @objc private func copyScheme(_ sender: UIButton) {
        guard schemes.indices.contains(sender.tag) else { return }
        UIPasteboard.general.string = schemes[sender.tag].1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    @objc private func close() { dismiss(animated: true) }
}

// Certificate import uses the existing CertificateStore, without duplicating verification.
private final class CertificateSettingsController: UIViewController, UIDocumentPickerDelegate {
    private let store = CertificateStore.shared
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var p12: URL?
    private var provision: URL?
    private var pickingP12 = true
    private var p12Button = UIButton(type: .system)
    private var provisionButton = UIButton(type: .system)
    private let password = UITextField()
    private let list = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        let header = SettingsDetailLayout.header(in: self, title: "证书管理", back: #selector(close))
        SettingsStyle.embed(scroll: scroll, stack: stack, in: view, top: header.bottomAnchor, bottomInset: 20)
        SettingsStyle.section("导入签名证书", in: stack)
        p12Button = makeButton("选择 P12 文件", selector: #selector(selectP12))
        provisionButton = makeButton("选择 mobileprovision 文件", selector: #selector(selectProvision))
        stack.addArrangedSubview(p12Button)
        stack.addArrangedSubview(provisionButton)
        let passwordCard = SettingsStyle.card()
        password.isSecureTextEntry = true
        password.placeholder = "P12 密码"
        password.textContentType = .password
        password.translatesAutoresizingMaskIntoConstraints = false
        passwordCard.addSubview(password)
        passwordCard.heightAnchor.constraint(equalToConstant: 52).isActive = true
        NSLayoutConstraint.activate([
            password.leadingAnchor.constraint(equalTo: passwordCard.leadingAnchor, constant: 16),
            password.trailingAnchor.constraint(equalTo: passwordCard.trailingAnchor, constant: -16),
            password.centerYAnchor.constraint(equalTo: passwordCard.centerYAnchor)
        ])
        stack.addArrangedSubview(passwordCard)
        stack.addArrangedSubview(makeButton("导入证书", selector: #selector(importCertificate)))
        stack.addArrangedSubview(SettingsStyle.text("请选择 P12 和 mobileprovision 文件；密码仅用于本次校验，不会保存到设置页面。", size: 13, color: SettingsStyle.secondary))
        SettingsStyle.section("已导入证书", in: stack)
        list.axis = .vertical
        list.spacing = 8
        stack.addArrangedSubview(list)
        renderCertificates()
    }

    private func makeButton(_ title: String, selector: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = .white
        button.layer.cornerRadius = 16
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: selector, for: .touchUpInside)
        return button
    }

    @objc private func selectP12() { pickingP12 = true; pickDocument() }
    @objc private func selectProvision() { pickingP12 = false; pickDocument() }
    private func pickDocument() {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let source = urls.first else { return }
        let expected = pickingP12 ? "p12" : "mobileprovision"
        guard source.pathExtension.lowercased() == expected else {
            alert("文件格式错误", "请选择 .\(expected) 文件")
            return
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: staged)
            if pickingP12 {
                if let old = p12 { try? FileManager.default.removeItem(at: old) }
                p12 = staged
                p12Button.setTitle("P12：\(source.lastPathComponent)", for: .normal)
            } else {
                if let old = provision { try? FileManager.default.removeItem(at: old) }
                provision = staged
                provisionButton.setTitle("描述文件：\(source.lastPathComponent)", for: .normal)
            }
        } catch { alert("读取文件失败", error.localizedDescription) }
    }

    @objc private func importCertificate() {
        guard let p12 = p12, let provision = provision else {
            alert("未选择文件", "请先选择 P12 和 mobileprovision")
            return
        }
        view.endEditing(true)
        do {
            try store.add(p12: p12, provision: provision, password: password.text ?? "")
            try? FileManager.default.removeItem(at: p12)
            try? FileManager.default.removeItem(at: provision)
            self.p12 = nil
            self.provision = nil
            p12Button.setTitle("选择 P12 文件", for: .normal)
            provisionButton.setTitle("选择 mobileprovision 文件", for: .normal)
            password.text = nil
            renderCertificates()
            alert("导入成功", "证书已导入")
        } catch { alert("导入失败", error.localizedDescription) }
    }

    private func renderCertificates() {
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        store.reload()
        if store.certificates.isEmpty {
            list.addArrangedSubview(SettingsStyle.text("暂无证书", size: 14, color: SettingsStyle.secondary))
        }
        for item in store.certificates {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 10
            let label = SettingsStyle.text(item.name, size: 15)
            let remove = UIButton(type: .system)
            remove.setImage(UIImage(systemName: "trash"), for: .normal)
            remove.tintColor = .systemRed
            remove.addActionForCertificateRemoval(target: self, id: item.id)
            row.addArrangedSubview(label)
            row.addArrangedSubview(remove)
            list.addArrangedSubview(row)
        }
    }

    @objc fileprivate func removeCertificate(_ sender: UIButton) {
        guard let item = store.certificates.first(where: { $0.id == sender.accessibilityIdentifier }) else { return }
        do { try store.remove(item); renderCertificates() }
        catch { alert("删除失败", error.localizedDescription) }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    deinit {
        if let p12 = p12 { try? FileManager.default.removeItem(at: p12) }
        if let provision = provision { try? FileManager.default.removeItem(at: provision) }
    }
    @objc private func close() { dismiss(animated: true) }
}

private extension UIButton {
    func addActionForCertificateRemoval(target: CertificateSettingsController, id: String) {
        accessibilityIdentifier = id
        addTarget(target, action: #selector(CertificateSettingsController.removeCertificate(_:)), for: .touchUpInside)
    }
}

private enum SettingsStyle {
    static let background = UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)
    static let secondary = UIColor(red: 0.56, green: 0.56, blue: 0.59, alpha: 1)
    static let blue = UIColor(red: 0.13, green: 0.49, blue: 0.98, alpha: 1)

    static func text(_ value: String, size: CGFloat, bold: Bool = false, color: UIColor = .black) -> UILabel {
        let label = UILabel()
        label.text = value
        label.textColor = color
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.numberOfLines = 0
        return label
    }

    static func card() -> UIView {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 17
        return view
    }

    static func statusIcon(registered: Bool, diameter: CGFloat) -> UIView {
        let circle = UIView()
        circle.backgroundColor = registered ? .systemGreen : .systemRed
        circle.layer.cornerRadius = diameter / 2
        circle.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        circle.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        let icon = UIImageView(image: UIImage(systemName: registered ? "checkmark" : "xmark"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: diameter * 0.44),
            icon.heightAnchor.constraint(equalToConstant: diameter * 0.44)
        ])
        return circle
    }

    static func separator() -> UIView {
        let line = UIView()
        line.backgroundColor = UIColor(white: 0.91, alpha: 1)
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return line
    }

    static func section(_ value: String, in stack: UIStackView) {
        let label = text(value, size: 14, color: secondary)
        stack.addArrangedSubview(label)
        stack.setCustomSpacing(5, after: label)
    }

    static func embed(scroll: UIScrollView, stack: UIStackView, in view: UIView,
                      top: NSLayoutYAxisAnchor? = nil, bottomInset: CGFloat) {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset.bottom = bottomInset
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: top ?? view.safeAreaLayoutGuide.topAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -22),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -16)
        ])
    }
}


/// A separate plugin warehouse. No IPA archive is published into this directory.
enum ZonoePluginLibrary {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zonoedylib", isDirectory: true)
    }
    static func validName(_ url: URL) -> Bool {
        ["dylib", "deb", "framework"].contains(url.pathExtension.lowercased())
    }
    static func files() -> [URL] {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { validName($0) && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
    static func importFile(_ source: URL) throws {
        guard validName(source) else { throw failure("仅支持 dylib、deb、framework") }
        let fm = FileManager.default
        let security = source.startAccessingSecurityScopedResource()
        defer { if security { source.stopAccessingSecurityScopedResource() } }
        guard fm.fileExists(atPath: source.path) else { throw failure("导入文件不存在") }
        if (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw failure("不支持符号链接")
        }
        let ext = source.pathExtension.lowercased()
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        guard (ext == "framework") == isDirectory else { throw failure("Framework 必须为完整目录，其他插件必须是文件") }
        if isDirectory {
            let contents = fm.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey])
            while let item = contents?.nextObject() as? URL {
                if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    throw failure("Framework 内包含符号链接，暂不支持导入")
                }
            }
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let stage = directory.appendingPathComponent(".incoming-" + UUID().uuidString)
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: source, to: stage)
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        while fm.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + source.lastPathComponent)
        }
        try fm.moveItem(at: stage, to: destination)
    }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "ZonoePluginLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

final class PluginLibraryController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    var onSelection: (([URL]) -> Void)?
    private var entries = [URL]()
    private var selected = Set<URL>()
    private var editingFiles = false
    private let table = UITableView(frame: .zero, style: .plain)
    private let editButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    private let selectionBar = UIStackView()
    private let queue = DispatchQueue(label: "zonoe.plugins.io", qos: .utility)
    private var importing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGroupedBackground
        let nav = UIView()
        nav.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nav)
        let back = UIButton(type: .system)
        back.setTitle("返回", for: .normal)
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        nav.addSubview(back)
        let title = UILabel()
        title.text = onSelection == nil ? "动态库/插件" : "选择注入插件"
        title.font = .boldSystemFont(ofSize: 18)
        title.translatesAutoresizingMaskIntoConstraints = false
        nav.addSubview(title)
        editButton.setTitle("编辑", for: .normal)
        editButton.addTarget(self, action: #selector(toggleEdit), for: .touchUpInside)
        editButton.translatesAutoresizingMaskIntoConstraints = false
        nav.addSubview(editButton)
        plusButton.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        plusButton.addTarget(self, action: #selector(showImport), for: .touchUpInside)
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        nav.addSubview(plusButton)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 67
        view.addSubview(table)
        selectionBar.axis = .horizontal
        selectionBar.distribution = .fillEqually
        selectionBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(selectionBar)
        for name in ["全选", onSelection == nil ? "删除" : "确定选择", "完成"] {
            let button = UIButton(type: .system)
            button.setTitle(name, for: .normal)
            if name == "删除" { button.setTitleColor(.systemRed, for: .normal) }
            button.addTarget(self, action: name == "全选" ? #selector(selectAll) : name == "删除" ? #selector(removeSelected) : name == "完成" ? #selector(toggleEdit) : #selector(commitSelection), for: .touchUpInside)
            selectionBar.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            nav.leadingAnchor.constraint(equalTo: view.leadingAnchor), nav.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nav.heightAnchor.constraint(equalToConstant: 54),
            back.leadingAnchor.constraint(equalTo: nav.leadingAnchor, constant: 18), back.centerYAnchor.constraint(equalTo: nav.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: nav.centerXAnchor), title.centerYAnchor.constraint(equalTo: nav.centerYAnchor),
            plusButton.trailingAnchor.constraint(equalTo: nav.trailingAnchor, constant: -16), plusButton.centerYAnchor.constraint(equalTo: nav.centerYAnchor),
            plusButton.widthAnchor.constraint(equalToConstant: 34), plusButton.heightAnchor.constraint(equalToConstant: 42),
            editButton.trailingAnchor.constraint(equalTo: plusButton.leadingAnchor, constant: -15), editButton.centerYAnchor.constraint(equalTo: nav.centerYAnchor),
            table.topAnchor.constraint(equalTo: nav.bottomAnchor), table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: selectionBar.topAnchor),
            selectionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            selectionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            selectionBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            selectionBar.heightAnchor.constraint(equalToConstant: 48)
        ])
        if onSelection != nil { editingFiles = true }
        refresh()
        updateEditing()
    }
    private func refresh() {
        entries = ZonoePluginLibrary.files()
        selected.formIntersection(Set(entries))
        table.reloadData()
    }
    private func updateEditing() {
        selectionBar.isHidden = !editingFiles
        editButton.setTitle(editingFiles ? "完成" : "编辑", for: .normal)
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func toggleEdit() {
        editingFiles.toggle()
        if !editingFiles { selected.removeAll() }
        updateEditing()
        table.reloadData()
    }
    @objc private func selectAll() {
        selected = Set(entries)
        table.reloadData()
    }
    @objc private func commitSelection() {
        onSelection?(entries.filter { selected.contains($0) })
        dismiss(animated: true)
    }
    @objc private func removeSelected() {
        guard !selected.isEmpty else { return }
        let alert = UIAlertController(title: "删除选中的插件", message: "将删除 " + String(selected.count) + " 个文件或目录，确定继续？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let files = Array(self.selected)
            self.queue.async {
                var failure: Error?
                for file in files {
                    do { try FileManager.default.removeItem(at: file) } catch { failure = error }
                }
                DispatchQueue.main.async {
                    self.selected.removeAll()
                    self.refresh()
                    if let failure = failure { self.message(failure.localizedDescription) }
                }
            }
        })
        present(alert, animated: true)
    }
    @objc private func showImport() {
        let alert = UIAlertController(title: "添加第三方库", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "从文件安装", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let picker = UIDocumentPickerViewController(documentTypes: ["public.data", "public.folder"], in: .import)
            picker.allowsMultipleSelection = true
            picker.delegate = self
            self.present(picker, animated: true)
        })
        alert.addAction(UIAlertAction(title: "从链接安装", style: .default) { [weak self] _ in self?.importLink() })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = plusButton
        alert.popoverPresentationController?.sourceRect = plusButton.bounds
        present(alert, animated: true)
    }
    private func importLink() {
        let alert = UIAlertController(title: "从链接安装", message: "支持直接下载 dylib 或 deb；Framework 请从文件导入", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "https://example.com/example.dylib" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "下载", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let raw = alert?.textFields?.first?.text,
                  let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil, ["dylib", "deb"].contains(url.pathExtension.lowercased()) else {
                self?.message("请输入有效的 dylib 或 deb 下载链接")
                return
            }
            guard !self.importing else { self.message("正在导入插件，请稍后重试"); return }
            self.importing = true
            URLSession.shared.downloadTask(with: url) { [weak self] location, response, error in
                guard let self = self else { return }
                self.queue.async {
                    var failure: Error? = error
                    do {
                        guard failure == nil, let location = location,
                              let code = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(code) else {
                            throw failure ?? ZonoePluginLibrary.failure("下载失败")
                        }
                        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + url.pathExtension.lowercased())
                        defer { try? FileManager.default.removeItem(at: staging) }
                        try FileManager.default.copyItem(at: location, to: staging)
                        try ZonoePluginLibrary.importFile(staging)
                    } catch { failure = error }
                    DispatchQueue.main.async {
                        self.importing = false
                        self.refresh()
                        if let failure = failure { self.message(failure.localizedDescription) }
                    }
                }
            }.resume()
        })
        present(alert, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty, !importing else { return }
        importing = true
        queue.async {
            var failure: Error?
            for url in urls {
                do { try ZonoePluginLibrary.importFile(url) } catch { failure = error }
            }
            DispatchQueue.main.async {
                self.importing = false
                self.refresh()
                if let failure = failure { self.message(failure.localizedDescription) }
            }
        }
    }
    private func message(_ text: String) {
        let alert = UIAlertController(title: "插件管理", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Plugin") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "Plugin")
        let file = entries[indexPath.row]
        cell.textLabel?.text = file.lastPathComponent
        let resource = try? file.resourceValues(forKeys: [.fileSizeKey])
        cell.detailTextLabel?.text = file.pathExtension.uppercased() + " · " + ByteCountFormatter.string(fromByteCount: Int64(resource?.fileSize ?? 0), countStyle: .file)
        cell.imageView?.image = UIImage(systemName: file.pathExtension.lowercased() == "framework" ? "folder" : "doc.zipper")
        cell.accessoryType = selected.contains(file) ? .checkmark : .none
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let file = entries[indexPath.row]
        if editingFiles {
            if !selected.insert(file).inserted { selected.remove(file) }
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
}
