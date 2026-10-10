import SwiftUI
import UIKit
import ZIPFoundation

struct SigningExecutionView: View {
    let ipaURL: URL
    @ObservedObject private var certificates = CertificateStore.shared
    @ObservedObject private var signingOptions = SigningOptionsStore.shared
    @Environment(\.presentationMode) private var presentation
    @State private var selectedID = ""
    @State private var password = ""
    @State private var previewIcon: UIImage?
    @State private var replacementIconPNG: Data?
    @State private var showingIconPicker = false
    @State private var appName = ""
    @State private var bundleID = ""
    @State private var version = ""
    @State private var minimumOS = ""
    @State private var outputFormat = "ipa"
    @State private var removeURLSchemes = false
    @State private var state: SigningState = .idle
    @State private var running = false
    @State private var result: SignedArtifact?
    @State private var errorMessage: String?
    @State private var showShare = false
    @State private var installMode = IPAInstallMode.local
    @State private var installing = false
    private let engine = AppSigningService()


    private let pageColor = Color(red: 0.92, green: 0.92, blue: 0.94)

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        iconHeader
                        inputField("应用名称", value: $appName)
                        inputField("应用标识符", value: $bundleID)
                        inputField("版本号", value: $version)
                        inputField("最低系统要求", value: $minimumOS)

                        sectionLabel("输出格式")
                        Picker("输出格式", selection: $outputFormat) {
                            Text("ipa").tag("ipa")
                            Text("zip").tag("zip")
                            Text("tipa").tag("tipa")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal, 18)
                        .padding(.bottom, 28)

                        sectionLabel("打包选项")
                        roundedToggle("移除应用跳转", value: $removeURLSchemes)
                        roundedToggle("文件共享", value: optionBinding(\.fileSharing))
                        roundedToggle("iTunes 文件共享", value: optionBinding(\.itunesFileSharing))
                        roundedToggle("ProMotion", value: optionBinding(\.proMotion))
                        roundedToggle("游戏模式", value: optionBinding(\.gameMode))
                        roundedToggle("iPad 全屏", value: optionBinding(\.ipadFullscreen))
                        roundedToggle("强制本地化", value: optionBinding(\.forceLocalization))

                        sectionLabel("签名方式")
                        roundedToggle("Ad-hoc 伪签名", value: optionBinding(\.temporarySigning))
                        roundedToggle("注册 zonoe UDID 回调", value: optionBinding(\.registerCallback))
                        roundedToggle("签名完成自动安装", value: optionBinding(\.autoInstallAfterSigning))
                        HStack {
                            Text("安装方式")
                            Spacer()
                            Picker("安装方式", selection: $installMode) {
                                Text("本地 OTA").tag(IPAInstallMode.local)
                                Text("网络服务器").tag(IPAInstallMode.network)
                            }.pickerStyle(SegmentedPickerStyle()).frame(width: 210)
                        }.padding(14).background(Color.white).cornerRadius(12)
                         .padding(.horizontal, 18).padding(.bottom, 12)
                        HStack {
                            Text("打包规则")
                            Spacer()
                            Picker("打包规则", selection: packagingRuleBinding) {
                                ForEach(SigningPackagingRule.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .labelsHidden()
                        }
                        .padding(14)
                        .background(Color.white)
                        .cornerRadius(12)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)

                        if !signingOptions.options.temporarySigning {
                            sectionLabel("签名证书")
                            VStack(alignment: .leading, spacing: 8) {
                                if certificates.certificates.isEmpty {
                                    Text("请先在签名设置导入 P12 与描述文件")
                                        .foregroundColor(.secondary)
                                } else {
                                    Picker("选择证书", selection: $selectedID) {
                                        ForEach(certificates.certificates) { item in
                                            Text(item.name).tag(item.id)
                                        }
                                    }
                                    if selectedCertificateNeedsPassword {
                                        SecureField("旧证书：补录一次 P12 密码", text: $password)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white)
                            .cornerRadius(12)
                            .padding(.horizontal, 18)
                        }

                        sectionLabel("执行状态")
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                if running { SigningActivityIndicator().frame(width: 22, height: 22) }
                                Text(stageName(state))
                            }
                            if let failure = errorMessage {
                                Text(failure).font(.footnote).foregroundColor(.red)
                            }
                            if let artifact = result {
                                Text(artifact.ipaURL.lastPathComponent)
                                    .font(.footnote)
                                Button("分享 / 保存文件") { showShare = true }
                                Button(installing ? "正在启动安装…" : "安装应用") { beginInstall(artifact) }
                                    .disabled(installing)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white)
                        .cornerRadius(12)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 28)
                    }
                }
                .background(pageColor)

                Button(action: start) {
                    Text(running ? "正在处理…" : "确认修改 / 打包")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color(red: 0.20, green: 0.47, blue: 0.97))
                        .foregroundColor(.white)
                        .cornerRadius(17)
                }
                .disabled(running || result != nil ||
                          (!signingOptions.options.temporarySigning &&
                           !certificates.certificates.contains(where: { $0.id == selectedID })))
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .background(pageColor)
            }
            .navigationBarTitle("修改应用信息", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") { presentation.wrappedValue.dismiss() }.disabled(running),
                trailing: Button(action: {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }) {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            )
            .onAppear {
                certificates.reload()
                loadPreviewIcon()
                if selectedID.isEmpty { selectedID = certificates.certificates.first?.id ?? "" }
                if let inspection = try? IPAInspector.inspect(ipaURL) {
                    appName = inspection.displayName
                    bundleID = inspection.bundleID
                    version = inspection.version
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                GameStoreIconImagePicker { image in
                    if let bytes = image.pngData() {
                        replacementIconPNG = bytes
                        previewIcon = image
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                if let artifact = result { ActivityShareView(items: [artifact.ipaURL]) }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var iconHeader: some View {
        VStack(spacing: 9) {
            Button(action: { if !running { showingIconPicker = true } }) {
            Group {
                if let icon = previewIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .foregroundColor(Color(red: 0.29, green: 0.48, blue: 0.88))
                }
            }
            .frame(width: 94, height: 94)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(PlainButtonStyle())
            Text(ipaURL.lastPathComponent)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(replacementIconPNG != nil ? "已选择新图标 · 点击重新选择" : "点击图标更换应用图标")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 22)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 28)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }

    private func inputField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.gray)
                .padding(.leading, 10)
            TextField(title, text: value)
                .font(.system(size: 17))
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
                .autocapitalization(.none)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 15)
    }

    private func roundedToggle(_ title: String, value: Binding<Bool>) -> some View {
        Toggle(title, isOn: value)
            .font(.system(size: 16))
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.20)))
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
    }

    private func loadPreviewIcon() {
        let file = ipaURL
        DispatchQueue.global(qos: .userInitiated).async {
            let image = IPAIconPreviewResolver.load(file)
            DispatchQueue.main.async { self.previewIcon = image }
        }
    }

    private func optionBinding(_ key: WritableKeyPath<SigningOptions, Bool>) -> Binding<Bool> {
        Binding(get: { self.signingOptions.options[keyPath: key] },
                set: { newValue in
                    var options = self.signingOptions.options
                    options[keyPath: key] = newValue
                    self.signingOptions.options = options
                })
    }

    private var packagingRuleBinding: Binding<SigningPackagingRule> {
        Binding(get: { self.signingOptions.options.packagingRule }, set: { value in
            var options = self.signingOptions.options
            options.packagingRule = value
            self.signingOptions.options = options
        })
    }
    private var selectedCertificateNeedsPassword: Bool {
        !selectedID.isEmpty && CertificatePasswordKeychain.read(for: selectedID) == nil
    }

    private func start() {
        guard !running else { return }
        let temporary = signingOptions.options.temporarySigning
        guard temporary || certificates.certificates.contains(where: { $0.id == selectedID }) else {
            errorMessage = "请选择已导入的证书"
            return
        }
        let certificate = certificates.certificates.first(where: { $0.id == selectedID }) ?? DeviceCertificate(id: "modify-only", name: "仅修改", p12URL: nil, mobileProvisionURL: nil)
        running = true
        result = nil
        errorMessage = nil
        state = .prepareContext
        let storedPassword = temporary ? "" : CertificatePasswordKeychain.read(for: certificate.id)
        let effectivePassword = storedPassword ?? password
        let wasLegacy = storedPassword == nil
        let editing = SigningAppEditing(displayName: appName, bundleIdentifier: bundleID, version: version, minimumOS: minimumOS, removeURLSchemes: removeURLSchemes, outputFormat: outputFormat, replacementIconPNG: replacementIconPNG)
        let request = SigningRequest(ipaURL: ipaURL, certificate: certificate, password: effectivePassword, editing: editing)
        engine.sign(request: request, progress: { nextState in
            state = nextState
        }, completion: { response in
            running = false
            switch response {
            case .success(let artifact):
                if wasLegacy && !temporary { try? CertificatePasswordKeychain.save(effectivePassword, for: certificate.id) }
                password = ""
                result = artifact
                state = .verifySignature
                if signingOptions.options.autoInstallAfterSigning { beginInstall(artifact) }
            case .failure(let error):
                state = .failed
                errorMessage = error.localizedDescription
            }
        })
    }

    private func beginInstall(_ artifact: SignedArtifact) {
        guard !installing else { return }
        installing = true
        errorMessage = nil
        state = .waitingForSystemInstall
        IPAInstallCoordinator.shared.begin(artifact: artifact, mode: installMode) { response in
            DispatchQueue.main.async {
                installing = false
                switch response {
                case .success(let accepted):
                    if !accepted { errorMessage = "iOS 未接受安装链接，请检查安装环境与清单地址" }
                    // Opening a URL does not establish that the app was installed.
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stageName(_ value: SigningState) -> String {
        switch value {
        case .idle: return "准备就绪"
        case .prepareContext: return "初始化签名环境"
        case .verifyCertificate: return "验证证书"
        case .prepareIPA: return "检查 IPA"
        case .extracting: return "解包 IPA"
        case .signing: return signingOptions.options.temporarySigning ? "Ad-hoc 伪签名" : "使用证书签名"
        case .repacking: return "重新打包 IPA"
        case .verifySignature: return result == nil ? "验证输出" : "签名已完成"
        case .waitingForSystemInstall: return "等待安装"
        case .installComplete: return "安装完成"
        case .failed: return "签名失败"
        }
    }
}

private struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct SigningActivityIndicator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: .medium)
        view.startAnimating()
        return view
    }
    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {
        if !uiView.isAnimating { uiView.startAnimating() }
    }
}

private enum IPAIconPreviewResolver {
    static func load(_ ipa: URL) -> UIImage? {
        let manager = FileManager.default
        let work = manager.temporaryDirectory.appendingPathComponent("gamestore-icon-" + UUID().uuidString, isDirectory: true)
        defer { try? manager.removeItem(at: work) }
        do {
            try manager.createDirectory(at: work, withIntermediateDirectories: true, attributes: nil)
            try manager.unzipItem(at: ipa, to: work)
            let payload = work.appendingPathComponent("Payload", isDirectory: true)
            let apps = try manager.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "app" }
            guard apps.count == 1, let app = apps.first else { return nil }
            let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
            var candidates = [String]()
            if let primary = info["CFBundleIcons"] as? [String: Any],
               let icon = primary["CFBundlePrimaryIcon"] as? [String: Any] {
                candidates += icon["CFBundleIconFiles"] as? [String] ?? []
                if let name = icon["CFBundleIconName"] as? String { candidates.append(name) }
            }
            if let file = info["CFBundleIconFile"] as? String { candidates.append(file) }
            // Prefer the largest declared icon. CgBI and Assets.car require separate decoders.
            for name in candidates.reversed() {
                let base = (name as NSString).lastPathComponent
                for suffix in ["", ".png", "@3x.png", "@2x.png"] {
                    let path = app.appendingPathComponent(base + suffix)
                    if let image = UIImage(contentsOfFile: path.path) { return image }
                }
            }
            return nil
        } catch {
            return nil
        }
    }
}

private struct GameStoreIconImagePicker: UIViewControllerRepresentable {
    let onSelect: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentation

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: GameStoreIconImagePicker
        init(parent: GameStoreIconImagePicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentation.wrappedValue.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onSelect(image) }
            parent.presentation.wrappedValue.dismiss()
        }
    }
}
