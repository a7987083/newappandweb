import UIKit

/// Per-package signing editor. The signing engine and global settings remain shared.
final class SigningEditorViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let ipaURL: URL
    private let packageInfo: AppPackageInfo?
    private var toggles = [WritableKeyPath<SigningOptions, Bool>: UISwitch]()
    private var installMode: IPAInstallMode = .network
    private let installButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let service = AppSigningService()
    private let content = UIStackView()
    private let action = UIButton(type: .system)
    private let status = UILabel()
    private var fields = [String: UITextField]()
    private var certificate: DeviceCertificate?
    private var passwordField = UITextField()
    private var format = UISegmentedControl(items: ["IPA", "ZIP", "TIPA"])
    private var compression = UISegmentedControl(items: IPACompressionPreset.allCases.map { $0.title })
    private var removeSchemes = UISwitch()
    private var replacementIcon: Data?
    private var running = false
    private var artifact: SignedArtifact?
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
        content.spacing = 12
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
        addControl("移除应用跳转", control: removeSchemes)
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
        let rule = UISegmentedControl(items: SigningPackagingRule.allCases.map { $0.title })
        rule.selectedSegmentIndex = SigningPackagingRule.allCases.firstIndex(of: options.packagingRule) ?? 0
        rule.addTarget(self, action: #selector(changePackagingRule(_:)), for: .valueChanged)
        addControl("打包规则", control: rule)
        let installLabel = UILabel()
        installLabel.text = "安装方式：网络安装"
        addCard(installLabel)
        let iconButton = UIButton(type: .system)
        iconButton.setTitle("选择替换图标", for: .normal)
        iconButton.addTarget(self, action: #selector(selectIcon), for: .touchUpInside)
        addCard(iconButton)
        let certButton = UIButton(type: .system)
        certButton.setTitle("选择签名证书", for: .normal)
        certButton.addTarget(self, action: #selector(selectCertificate), for: .touchUpInside)
        addCard(certButton)
        passwordField.placeholder = "旧证书 P12 密码（如需要）"
        passwordField.isSecureTextEntry = true
        passwordField.borderStyle = .roundedRect
        addCard(passwordField)
        status.text = "准备就绪"
        status.numberOfLines = 0
        addCard(status)
        installButton.setTitle("安装应用（网络）", for: .normal)
        installButton.isHidden = true
        installButton.addTarget(self, action: #selector(installResult), for: .touchUpInside)
        addCard(installButton)
        cancelButton.setTitle("取消签名", for: .normal)
        cancelButton.isHidden = true
        cancelButton.addTarget(self, action: #selector(cancelSigning), for: .touchUpInside)
        addCard(cancelButton)

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

    private func addToggle(_ title: String, key: WritableKeyPath<SigningOptions, Bool>, value: Bool) {
        let control = UISwitch()
        control.isOn = value
        control.addAction(UIAction { _ in
            var options = SigningOptionsStore.shared.options
            options[keyPath: key] = control.isOn
            SigningOptionsStore.shared.options = options
        }, for: .valueChanged)
        toggles[key] = control
        let stack = UIStackView(arrangedSubviews: [UILabel(), control])
        (stack.arrangedSubviews[0] as? UILabel)?.text = title
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        addCard(stack)
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
        installButton.isEnabled = false
        status.text = "正在启动网络安装…"
        IPAInstallCoordinator.shared.begin(artifact: artifact, mode: installMode) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.installButton.isEnabled = true
                switch response {
                case .success(let accepted):
                    self.status.text = accepted ? "已提交系统安装请求（不代表安装完成）" : "iOS 未接受安装请求"
                case .failure(let error): self.showMessage(error.localizedDescription)
                }
            }
        }
    }

    private func addCard(_ child: UIView) {
        let wrapper = UIView()
        wrapper.backgroundColor = .white
        wrapper.layer.cornerRadius = 14
        content.addArrangedSubview(wrapper)
        child.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            child.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            child.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 12),
            child.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -12)
        ])
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
    @objc private func selectIcon() {
        guard !running else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        present(picker, animated: true)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        replacementIcon = (info[.originalImage] as? UIImage)?.pngData()
        picker.dismiss(animated: true)
    }
    @objc private func start() {
        guard !running else { return }
        let temporary = SigningOptionsStore.shared.options.temporarySigning
        guard temporary || certificate != nil else {
            showMessage("请先导入并选择签名证书")
            return
        }
        let selected = certificate ?? DeviceCertificate(id: "modify-only", name: "仅修改", p12URL: nil, mobileProvisionURL: nil)
        let stored = CertificatePasswordKeychain.read(for: selected.id)
        let password = temporary ? "" : (stored ?? passwordField.text ?? "")
        let formats = ["ipa", "zip", "tipa"]
        let editing = SigningAppEditing(
            displayName: fields["name"]?.text,
            bundleIdentifier: fields["bundle"]?.text,
            version: fields["version"]?.text,
            minimumOS: fields["minimum"]?.text,
            removeURLSchemes: removeSchemes.isOn,
            outputFormat: formats[format.selectedSegmentIndex],
            compressionPreset: IPACompressionPreset.allCases[compression.selectedSegmentIndex],
            replacementIconPNG: replacementIcon
        )
        running = true
        action.isEnabled = false
        cancelButton.isHidden = false
        cancelButton.isEnabled = true
        status.text = "正在准备签名…"
        service.sign(request: SigningRequest(ipaURL: ipaURL, certificate: selected, password: password, editing: editing),
            progress: { [weak self] state in self?.status.text = state.rawValue },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.running = false
                self.action.isEnabled = true
                self.cancelButton.isHidden = true
                switch result {
                case .success(let file):
                    if !temporary && stored == nil { try? CertificatePasswordKeychain.save(password, for: selected.id) }
                    self.artifact = file
                    self.installButton.isHidden = false
                    self.passwordField.text = ""
                    self.status.text = "签名完成：" + file.ipaURL.lastPathComponent
                    self.action.setTitle("签名完成", for: .normal)
                    self.action.isEnabled = false
                    let done = UIAlertController(title: "签名完成", message: file.ipaURL.lastPathComponent, preferredStyle: .alert)
                    done.addAction(UIAlertAction(title: "分享", style: .default) { _ in
                        self.present(UIActivityViewController(activityItems: [file.ipaURL], applicationActivities: nil), animated: true)
                    })
                    done.addAction(UIAlertAction(title: "网络安装", style: .default) { _ in self.installResult() })
                    done.addAction(UIAlertAction(title: "完成", style: .cancel))
                    self.present(done, animated: true)
                    if SigningOptionsStore.shared.options.autoInstallAfterSigning {
                        // Dismiss the result sheet first, then begin the network install.
                        done.dismiss(animated: true) { self.installResult() }
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
