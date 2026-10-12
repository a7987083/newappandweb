import UIKit
import Zip

/// Per-package signing editor. The signing engine and global settings remain shared.
final class SigningEditorViewController: UIViewController {
    private let ipaURL: URL
    private let packageInfo: AppPackageInfo?
    private var toggles = [WritableKeyPath<SigningOptions, Bool>: UISwitch]()
    private let automaticInjectionToggle = UISwitch()
    private var installMode: IPAInstallMode = .network
    private let cancelButton = UIButton(type: .system)
    private let service = AppSigningService()
    private let content = UIStackView()
    private let action = UIButton(type: .system)
    private let status = UILabel()
    private var fields = [String: UITextField]()
    private var certificate: DeviceCertificate?
    private var format = UISegmentedControl(items: ["IPA", "ZIP", "TIPA"])
    private var compression = UISegmentedControl(items: IPACompressionPreset.allCases.map { $0.title })
    private var removeSchemes = UISwitch()
    private var selectedPlugins: [URL] = []
    private var removedLoadPaths: [String] = []
    private var running = false
    private var artifact: SignedArtifact?
    private var installing = false
    private var cancelCard: UIView?
    private let blue = UIColor(red: 51/255, green: 124/255, blue: 250/255, alpha: 1)

    init(ipaURL: URL, packageInfo: AppPackageInfo? = nil) {
        self.ipaURL = ipaURL
        self.packageInfo = packageInfo
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("Programmatic only") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1)
        let nav = UIView()
        nav.backgroundColor = .white
        nav.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nav)
        let back = UIButton(type: .system)
        back.setTitle("取消", for: .normal)
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        nav.addSubview(back)
        let heading = UILabel()
        heading.text = "修改应用信息"
        heading.font = .boldSystemFont(ofSize: 17)
        heading.translatesAutoresizingMaskIntoConstraints = false
        nav.addSubview(heading)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        content.axis = .vertical
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        let summary = UILabel()
        summary.text = ipaURL.lastPathComponent
        summary.numberOfLines = 2
        summary.font = .systemFont(ofSize: 13)
        summary.textColor = .secondaryLabel
        addCard(summary)
        addField("应用名称", key: "name", value: packageInfo?.name)
        addField("应用标识符", key: "bundle", value: packageInfo?.bundleID)
        addField("版本号", key: "version", value: packageInfo?.version)
        addField("最低系统要求", key: "minimum", value: packageInfo?.minimumOS)
        if packageInfo == nil { loadPackageInfo() }
        format.selectedSegmentIndex = 0
        addControl("输出格式", control: format)
        compression.selectedSegmentIndex = 1
        addControl("压缩预设", control: compression)
        addStandaloneToggle("移除应用跳转", control: removeSchemes)
        let options = SigningOptionsStore.shared.options
        addToggle("文件共享", key: \.fileSharing, value: options.fileSharing)
        addToggle("iTunes 文件共享", key: \.itunesFileSharing, value: options.itunesFileSharing)
        addToggle("ProMotion", key: \.proMotion, value: options.proMotion)
        addToggle("游戏模式", key: \.gameMode, value: options.gameMode)
        addToggle("iPad 全屏", key: \.ipadFullscreen, value: options.ipadFullscreen)
        addToggle("强制本地化", key: \.forceLocalization, value: options.forceLocalization)
        addToggle("Ad-hoc 伪签名", key: \.temporarySigning, value: options.temporarySigning)
        addToggle("注册 UDID 回调", key: \.registerCallback, value: options.registerCallback)
        addToggle("签名完成自动安装", key: \.autoInstallAfterSigning, value: options.autoInstallAfterSigning)
        automaticInjectionToggle.isOn = SigningInjectionPreferences.automaticBuiltIn
        automaticInjectionToggle.addTarget(self, action: #selector(changeAutomaticInjection(_:)), for: .valueChanged)
        addStandaloneToggle("注入修改器和菜单", control: automaticInjectionToggle)
        let rule = UISegmentedControl(items: SigningPackagingRule.allCases.map { $0.title })
        rule.selectedSegmentIndex = SigningPackagingRule.allCases.firstIndex(of: options.packagingRule) ?? 0
        rule.addTarget(self, action: #selector(changePackagingRule(_:)), for: .valueChanged)
        addControl("打包规则", control: rule)
        let pluginButton = UIButton(type: .system)
        pluginButton.setTitle("选择注入动态库", for: .normal)
        pluginButton.addTarget(self, action: #selector(selectPlugins), for: .touchUpInside)
        addCard(pluginButton)
        let removeButton = UIButton(type: .system)
        removeButton.setTitle("移除已有库（0）", for: .normal)
        removeButton.addTarget(self, action: #selector(pickExistingLibraries(_:)), for: .touchUpInside)
        addCard(removeButton)
        let certButton = UIButton(type: .system)
        certButton.setTitle("选择签名证书", for: .normal)
        certButton.addTarget(self, action: #selector(selectCertificate), for: .touchUpInside)
        addCard(certButton)
        status.text = "准备就绪"
        status.numberOfLines = 0
        addCard(status)
        cancelButton.setTitle("取消签名", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelSigning), for: .touchUpInside)
        cancelCard = addCard(cancelButton)
        cancelCard?.isHidden = true

        action.setTitle("确认修改 / 开始签名", for: .normal)
        action.backgroundColor = blue
        action.setTitleColor(.white, for: .normal)
        action.titleLabel?.font = .boldSystemFont(ofSize: 16)
        action.layer.cornerRadius = 15
        action.addTarget(self, action: #selector(start), for: .touchUpInside)
        action.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(action)

        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            nav.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nav.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nav.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: nav.leadingAnchor, constant: 18),
            back.centerYAnchor.constraint(equalTo: nav.centerYAnchor),
            heading.centerXAnchor.constraint(equalTo: nav.centerXAnchor),
            heading.centerYAnchor.constraint(equalTo: nav.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: nav.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: action.topAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -18),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -36),
            action.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            action.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            action.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            action.heightAnchor.constraint(equalToConstant: 52)
        ])
        CertificateStore.shared.reload()
        certificate = CertificateStore.shared.certificates.first
    }

    private func loadPackageInfo() {
        let archive = ipaURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let directory = try? DownloadIPAExtractor.preparedDirectory(for: archive),
                  let app = (try? FileManager.default.contentsOfDirectory(
                    at: directory.appendingPathComponent("Payload"), includingPropertiesForKeys: nil))?
                    .first(where: { $0.pathExtension.lowercased() == "app" }),
                  let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")) else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                for (key, plist) in [("name", "CFBundleDisplayName"), ("bundle", "CFBundleIdentifier"),
                                     ("version", "CFBundleShortVersionString"), ("minimum", "MinimumOSVersion")] {
                    if self.fields[key]?.text?.isEmpty == true {
                        self.fields[key]?.text = info[plist] as? String
                    }
                }
            }
        }
    }

    private func addStandaloneToggle(_ title: String, control: UISwitch) {
        addToggleRow(title, control: control)
    }
    private func addToggleRow(_ title: String, control: UISwitch) {
        let row = UIView()
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16)
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(control)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 38),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        addCard(row, verticalInset: 6)
    }
    private func addToggle(_ title: String, key: WritableKeyPath<SigningOptions, Bool>, value: Bool) {
        let control = UISwitch()
        control.isOn = value
        control.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        toggles[key] = control
        addToggleRow(title, control: control)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        automaticInjectionToggle.isOn = SigningInjectionPreferences.automaticBuiltIn
    }
    @objc private func changeAutomaticInjection(_ sender: UISwitch) {
        SigningInjectionPreferences.automaticBuiltIn = sender.isOn
    }
    @objc private func toggleChanged(_ sender: UISwitch) {
        guard let key = toggles.first(where: { $0.value === sender })?.key else { return }
        var options = SigningOptionsStore.shared.options
        options[keyPath: key] = sender.isOn
        SigningOptionsStore.shared.options = options
    }
    @objc private func changePackagingRule(_ sender: UISegmentedControl) {
        var options = SigningOptionsStore.shared.options
        options.packagingRule = SigningPackagingRule.allCases[sender.selectedSegmentIndex]
        SigningOptionsStore.shared.options = options
    }
    @objc private func cancelSigning() {
        guard running else { return }
        service.cancel()
        status.text = "正在取消签名…"
        cancelButton.isEnabled = false
    }
    @objc private func installResult() {
        guard let artifact = artifact, !running else { return }
        installing = true
        action.isEnabled = false
        action.setTitle("正在启动安装…", for: .normal)
        status.text = "正在启动网络安装…"
        IPAInstallCoordinator.shared.begin(artifact: artifact, mode: installMode) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.installing = false
                self.action.isEnabled = true
                self.action.setTitle("安装", for: .normal)
                switch response {
                case .success(let accepted):
                    self.status.text = accepted ? "已提交系统安装请求（不代表安装完成）" : "iOS 未接受安装请求"
                case .failure(let error): self.showMessage(error.localizedDescription)
                }
            }
        }
    }

    @discardableResult
    private func addCard(_ child: UIView, verticalInset: CGFloat = 12) -> UIView {
        let wrapper = UIView()
        wrapper.backgroundColor = .white
        wrapper.layer.cornerRadius = 14
        content.addArrangedSubview(wrapper)
        child.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            child.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            child.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: verticalInset),
            child.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -verticalInset)
        ])
        return wrapper
    }
    private func addField(_ label: String, key: String, value: String?) {
        let field = UITextField()
        field.placeholder = label
        field.text = value
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        fields[key] = field
        addCard(field)
    }
    private func addControl(_ label: String, control: UIView) {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        let title = UILabel()
        title.text = label
        title.font = .systemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(control)
        addCard(stack)
    }
    @objc private func close() {
        guard !running else { return }
        dismiss(animated: true)
    }
    @objc private func selectPlugins() {
        guard !running else { return }
        let library = PluginLibraryController()
        library.modalPresentationStyle = .fullScreen
        library.onSelection = { [weak self] chosen in
            self?.selectedPlugins = chosen
            self?.status.text = chosen.isEmpty ? "未选择插件" : "已选择 " + String(chosen.count) + " 个插件（支持 dylib / framework）"
        }
        present(library, animated: true)
    }
    @objc private func pickExistingLibraries(_ sender: UIButton) {
        guard !running else { return }
        sender.isEnabled = false
        status.text = "正在读取现有动态库…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak sender] in
            guard let self = self else { return }
            let fm = FileManager.default
            let scratch = fm.temporaryDirectory.appendingPathComponent("zonoe-dylib-scan-" + UUID().uuidString, isDirectory: true)
            var paths = [String]()
            var failure: Error?
            do {
                try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: scratch) }
                Zip.addCustomFileExtension("ipa")
                Zip.addCustomFileExtension("tipa")
                try Zip.unzipFile(self.ipaURL, destination: scratch, overwrite: true, password: nil)
                let payload = scratch.appendingPathComponent("Payload")
                let apps = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "app" }
                guard apps.count == 1, let binary = Bundle(url: apps[0])?.executableURL else {
                    throw ZonoePluginLibrary.failure("IPA 主程序不存在")
                }
                paths = Array(Set(ZNZsignKit.linkedDylibs(in: binary).filter {
                    $0.hasPrefix("@rpath/") || $0.hasPrefix("@executable_path/")
                })).sorted()
            } catch { failure = error }
            DispatchQueue.main.async {
                sender?.isEnabled = true
                if let failure = failure {
                    self.showMessage(failure.localizedDescription)
                    return
                }
                let sheet = UIAlertController(title: "移除已有库", message: "点击条目选择或取消；仅移除加载命令，不删除库文件。", preferredStyle: .actionSheet)
                for path in paths {
                    let selected = self.removedLoadPaths.contains(path)
                    sheet.addAction(UIAlertAction(title: (selected ? "✓ " : "") + path, style: .default) { [weak self, weak sender] _ in
                        guard let self = self else { return }
                        if let i = self.removedLoadPaths.firstIndex(of: path) { self.removedLoadPaths.remove(at: i) }
                        else { self.removedLoadPaths.append(path) }
                        sender?.setTitle("移除已有库（" + String(self.removedLoadPaths.count) + "）", for: .normal)
                        if let sender = sender { self.pickExistingLibraries(sender) }
                    })
                }
                sheet.addAction(UIAlertAction(title: "完成", style: .cancel))
                sheet.popoverPresentationController?.sourceView = sender
                sheet.popoverPresentationController?.sourceRect = sender?.bounds ?? .zero
                self.present(sheet, animated: true)
            }
        }
    }

    @objc private func selectCertificate() {
        guard !running else { return }
        CertificateStore.shared.reload()
        let sheet = UIAlertController(title: "选择签名证书", message: nil, preferredStyle: .actionSheet)
        for item in CertificateStore.shared.certificates {
            sheet.addAction(UIAlertAction(title: item.name, style: .default) { [weak self] _ in
                self?.certificate = item
                self?.status.text = "已选择证书：\(item.name)"
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(sheet, animated: true)
    }
    private func promptPassword(for certificate: DeviceCertificate) {
        let alert = UIAlertController(title: "输入证书密码", message: "此证书尚未保存 P12 密码", preferredStyle: .alert)
        alert.addTextField {
            $0.isSecureTextEntry = true
            $0.placeholder = "P12 密码"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "继续签名", style: .default) { [weak self, weak alert] _ in
            self?.performSigning(passwordOverride: alert?.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }
    @objc private func start() {
        if artifact != nil {
            if !installing { installResult() }
            return
        }
        guard !running else { return }
        if !SigningOptionsStore.shared.options.temporarySigning,
           let cert = certificate, CertificatePasswordKeychain.read(for: cert.id) == nil {
            promptPassword(for: cert)
            return
        }
        performSigning(passwordOverride: nil)
    }
    private func performSigning(passwordOverride: String?) {
        guard !running else { return }
        let temporary = SigningOptionsStore.shared.options.temporarySigning
        guard temporary || certificate != nil else {
            showMessage("请先导入并选择签名证书")
            return
        }
        let selected = certificate ?? DeviceCertificate(id: "modify-only", name: "仅修改", p12URL: nil, mobileProvisionURL: nil)
        let stored = CertificatePasswordKeychain.read(for: selected.id)
        let password = temporary ? "" : (stored ?? passwordOverride ?? "")
        let formats = ["ipa", "zip", "tipa"]
        let editing = SigningAppEditing(
            displayName: fields["name"]?.text,
            bundleIdentifier: fields["bundle"]?.text,
            version: fields["version"]?.text,
            minimumOS: fields["minimum"]?.text,
            removeURLSchemes: removeSchemes.isOn,
            outputFormat: formats[format.selectedSegmentIndex],
            compressionPreset: IPACompressionPreset.allCases[compression.selectedSegmentIndex],
            replacementIconPNG: nil
        )
        running = true
        action.isEnabled = false
        cancelCard?.isHidden = false
        cancelButton.isEnabled = true
        status.text = "正在准备签名…"
        service.sign(request: SigningRequest(ipaURL: ipaURL, certificate: selected, password: password, editing: editing,
                                             injectedPlugins: selectedPlugins, removedLoadPaths: removedLoadPaths,
                                             automaticBuiltIn: automaticInjectionToggle.isOn),
            progress: { [weak self] state in self?.status.text = state.rawValue },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.running = false
                self.action.isEnabled = true
                self.cancelCard?.isHidden = true
                switch result {
                case .success(let file):
                    if !temporary && stored == nil {
                        try? CertificatePasswordKeychain.save(password, for: selected.id)
                    }
                    self.artifact = file
                    self.status.text = "签名完成：" + file.ipaURL.lastPathComponent
                    self.action.setTitle("安装", for: .normal)
                    self.action.isEnabled = true
                    if SigningOptionsStore.shared.options.autoInstallAfterSigning {
                        self.installResult()
                    }
                case .failure(let error):
                    self.status.text = "签名失败"
                    self.showMessage(error.localizedDescription)
                }
            })
    }
    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
