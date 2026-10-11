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
        // Keep the interactive pop scoped to the settings navigation stack.
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
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

    @objc private func openSigningSettings() {
        navigationController?.pushViewController(SigningSettingsController(), animated: true)
    }

    @objc private func openSources() {
        let controller = SoftwareSourcesSettingsController()
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func openDeviceAuth() {
        let detail = DeviceAuthDetailController()
        navigationController?.pushViewController(detail, animated: true)
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
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = SettingsStyle.blue
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(back)
        let title = SettingsStyle.text("软件源", size: 19, bold: true)
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        let add = UIButton(type: .system)
        add.setImage(UIImage(systemName: "plus"), for: .normal)
        add.tintColor = SettingsStyle.blue
        add.addTarget(self, action: #selector(addSource), for: .touchUpInside)
        add.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(add)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 50),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 40),
            back.heightAnchor.constraint(equalToConstant: 40),
            title.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            add.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            add.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            add.widthAnchor.constraint(equalToConstant: 40),
            add.heightAnchor.constraint(equalToConstant: 40)
        ])
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

    @objc private func close() { navigationController?.popViewController(animated: true) }
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
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = SettingsStyle.blue
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(back)
        let heading = SettingsStyle.text("设备认证", size: 19, bold: true)
        heading.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(heading)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 50),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 40),
            back.heightAnchor.constraint(equalToConstant: 40),
            heading.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            heading.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
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

    @objc private func close() { navigationController?.popViewController(animated: true) }
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
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = SettingsStyle.blue
        back.translatesAutoresizingMaskIntoConstraints = false
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        header.addSubview(back)
        let title = SettingsStyle.text("签名设置", size: 19, bold: true)
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 50),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 40),
            back.heightAnchor.constraint(equalToConstant: 40),
            title.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        SettingsStyle.embed(scroll: scroll, stack: stack, in: view, top: header.bottomAnchor, bottomInset: 22)

        SettingsStyle.section("证书管理", in: stack)
        let certificate = UIButton(type: .system)
        certificate.backgroundColor = .white
        certificate.layer.cornerRadius = 16
        certificate.heightAnchor.constraint(equalToConstant: 54).isActive = true
        certificate.setTitle("导入证书 ›", for: .normal)
        certificate.setTitleColor(SettingsStyle.blue, for: .normal)
        certificate.addTarget(self, action: #selector(certificateInfo), for: .touchUpInside)
        stack.addArrangedSubview(certificate)
        stack.addArrangedSubview(SettingsStyle.text("支持 P12 与 mobileprovision。证书导入界面暂未迁移。", size: 13, color: SettingsStyle.secondary))

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

    @objc private func certificateInfo() {
        let alert = UIAlertController(title: "证书管理", message: "原有证书存储服务仍保留，证书导入 UI 暂未迁移。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    @objc private func close() { navigationController?.popViewController(animated: true) }
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
