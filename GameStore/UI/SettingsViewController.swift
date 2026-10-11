import UIKit

/// Source component for TrollSkin's fourth tab. iOS 13-compatible UIKit only.
/// Device authentication delegates directly to the existing UDIDService.
@objc(SettingsViewController)
final class SettingsViewController: UIViewController {
    private let background = UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)
    private let blue = UIColor(red: 0.20, green: 0.49, blue: 0.98, alpha: 1)
    private let muted = UIColor(red: 0.56, green: 0.56, blue: 0.59, alpha: 1)
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var statusLabel: UILabel?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = background
        configureLayout()
        renderSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshDeviceStatus),
                                               name: UDIDService.didUpdateNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configureLayout() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.alwaysBounceVertical = true
        scroll.contentInset.bottom = 100
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -25),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -36)
        ])
    }

    private func renderSettings() {
        let heading = label("设置", size: 37, bold: true, color: .black)
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(16, after: heading)
        let note = label("在这里管理设备认证及其他设置。尚未接入的选项保留演示占位。", size: 14, color: muted)
        note.numberOfLines = 0
        stack.addArrangedSubview(note)
        section("设备管理")
        let status = UDIDService.shared.udid
        let auth = row("设备认证", icon: "checkmark.shield.fill", detail: status == nil || status!.isEmpty ? "未获取 UDID" : "已获取 UDID", action: #selector(openDeviceAuthentication))
        statusLabel = auth.1
        stack.addArrangedSubview(auth.0)

        addPlaceholder("自定义清理", icon: "trash.circle.fill")
        addPlaceholder("切换 App Store 账户", icon: "person.2.circle.fill")
        addPlaceholder("允许所有 App 粘贴", icon: "doc.on.doc.fill")
        addPlaceholder("屏蔽 / 恢复 系统更新", icon: "shield.slash.fill")
        addPlaceholder("直降应用", icon: "arrow.down.to.line")
        let description = label("以下系统管理项目尚未接入 GameStore 业务。", size: 13, color: muted)
        stack.addArrangedSubview(description)

        section("签名工具 (LDID)")
        addPlaceholder("ldid 状态（演示占位）", icon: "checkmark.seal.fill")
        section("持久性助手")
        addPlaceholder("助手状态（演示占位）", icon: "checkmark.square.fill")
        addPlaceholder("卸载持久化助手", icon: "trash", tint: .systemRed)
    }

    private func label(_ text: String, size: CGFloat, bold: Bool = false, color: UIColor) -> UILabel {
        let result = UILabel()
        result.text = text
        result.textColor = color
        result.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        return result
    }

    private func section(_ title: String) {
        let text = label(title, size: 14, color: muted)
        stack.addArrangedSubview(text)
        stack.setCustomSpacing(5, after: text)
    }

    private func row(_ title: String, icon: String, detail: String? = nil,
                     tint: UIColor? = nil, action: Selector) -> (UIView, UILabel?) {
        let button = UIButton(type: .custom)
        button.backgroundColor = .white
        button.layer.cornerRadius = 19
        button.heightAnchor.constraint(equalToConstant: detail == nil ? 50 : 62).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)

        let symbol = UIImageView(image: UIImage(systemName: icon))
        symbol.tintColor = tint ?? blue
        symbol.contentMode = .scaleAspectFit
        symbol.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(symbol)

        let titleLabel = label(title, size: 16, color: tint ?? .black)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(titleLabel)

        let detailLabel: UILabel?
        if let detail = detail {
            let subtitle = label(detail, size: 12, color: muted)
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(subtitle)
            detailLabel = subtitle
            NSLayoutConstraint.activate([
                subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                subtitle.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -12),
                subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3)
            ])
        } else {
            detailLabel = nil
        }
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 23),
            symbol.widthAnchor.constraint(equalToConstant: 24),
            symbol.heightAnchor.constraint(equalToConstant: 24),
            symbol.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 63),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -12),
            detailLabel == nil
                ? titleLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor)
                : titleLabel.topAnchor.constraint(equalTo: button.topAnchor, constant: 11)
        ])
        return (button, detailLabel)
    }

    private func addPlaceholder(_ title: String, icon: String, tint: UIColor? = nil) {
        let button = row(title, icon: icon, tint: tint, action: #selector(showPlaceholder(_:))).0
        button.accessibilityIdentifier = title
        stack.addArrangedSubview(button)
    }

    @objc private func showPlaceholder(_ sender: UIButton) {
        let name = sender.accessibilityIdentifier ?? "此功能"
        let alert = UIAlertController(title: name, message: "当前仅为 UI 占位，尚未接入该项业务。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    @objc private func refreshDeviceStatus() {
        let udid = UDIDService.shared.udid
        statusLabel?.text = udid == nil || udid!.isEmpty ? "未获取 UDID" : "已获取 UDID"
    }

    @objc private func openDeviceAuthentication() {
        let udid = UDIDService.shared.udid
        let existing = udid != nil && !udid!.isEmpty
        let alert = UIAlertController(title: "设备认证",
            message: existing ? "已获取设备 UDID：\n\(udid!)" : "尚未获取设备 UDID。可通过原有描述文件流程获取。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: existing ? "重新获取 UDID" : "获取设备 UDID", style: .default) { _ in
            UDIDService.shared.requestProfileConfiguration()
        })
        present(alert, animated: true)
    }
}
