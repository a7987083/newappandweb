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

        for (title, symbol) in [
            ("自定义清理", "trash.circle.fill"),
            ("切换 App Store 账户", "person.2.circle.fill"),
            ("允许所有 App 粘贴", "doc.on.doc.fill"),
            ("屏蔽 / 恢复 系统更新", "shield.slash.fill"),
            ("直降应用", "arrow.down.to.line")
        ] {
            stack.addArrangedSubview(placeholder(title, icon: symbol))
        }
        SettingsStyle.section("签名工具 (LDID)", in: stack)
        stack.addArrangedSubview(placeholder("ldid 状态（演示占位）", icon: "checkmark.seal.fill"))
        SettingsStyle.section("持久性助手", in: stack)
        stack.addArrangedSubview(placeholder("助手状态（演示占位）", icon: "checkmark.square.fill"))
        stack.addArrangedSubview(placeholder("卸载持久化助手", icon: "trash", tint: .systemRed))
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

    @objc private func openDeviceAuth() {
        let detail = DeviceAuthDetailController()
        detail.modalPresentationStyle = .fullScreen
        present(detail, animated: true)
    }
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
