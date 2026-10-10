import SwiftUI
import UIKit

struct SigningExecutionView: View {
    let ipaURL: URL
    @ObservedObject private var certificates = CertificateStore.shared
    @ObservedObject private var signingOptions = SigningOptionsStore.shared
    @Environment(\.presentationMode) private var presentation
    @State private var selectedID = ""
    @State private var password = ""
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
    private let engine = AppSigningService()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    Section(header: Text("应用信息"), footer: Text("修改项将在重新签名前写入应用 Info.plist。")) {
                        HStack { Text("应用名称"); Spacer(); TextField("应用名称", text: $appName).multilineTextAlignment(.trailing) }
                        HStack { Text("应用标识符"); Spacer(); TextField("Bundle ID", text: $bundleID).multilineTextAlignment(.trailing).autocapitalization(.none) }
                        HStack { Text("版本号"); Spacer(); TextField("版本", text: $version).multilineTextAlignment(.trailing) }
                        HStack { Text("最低系统要求"); Spacer(); TextField("最低版本", text: $minimumOS).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation) }
                    }
                    Section(header: Text("输出格式")) {
                        Picker("输出格式", selection: $outputFormat) {
                            Text("ipa").tag("ipa")
                            Text("zip").tag("zip")
                            Text("tipa").tag("tipa")
                        }.pickerStyle(SegmentedPickerStyle())
                    }
                    Section(header: Text("打包选项")) {
                        Toggle("移除应用跳转", isOn: $removeURLSchemes)
                        Toggle("文件共享", isOn: optionBinding(\.fileSharing))
                        Toggle("iTunes 文件共享", isOn: optionBinding(\.itunesFileSharing))
                        Toggle("ProMotion", isOn: optionBinding(\.proMotion))
                        Toggle("游戏模式", isOn: optionBinding(\.gameMode))
                        Toggle("iPad 全屏", isOn: optionBinding(\.ipadFullscreen))
                    }
                    Section(header: Text("注入选项"), footer: Text("库注入、依赖修复和 Mach-O 编辑需要单独接入安全的二进制处理流程，本版不执行。")) {
                        Text("注入路径：@executable_path / @rpath").foregroundColor(.secondary)
                        Text("目标目录：根目录 / Frameworks").foregroundColor(.secondary)
                        HStack { Text("选择注入文件"); Spacer(); Text("待接入").foregroundColor(.secondary) }
                        HStack { Text("选择要移除的库"); Spacer(); Text("待接入").foregroundColor(.secondary) }
                    }
                    Section(header: Text("高级操作")) {
                        HStack { Text("提取库"); Spacer(); Text("待接入").foregroundColor(.secondary) }
                        HStack { Text("编辑 Info.plist"); Spacer(); Text("上方已支持常用字段").foregroundColor(.secondary) }
                    }
                    Section(header: Text("签名证书")) {
                        if certificates.certificates.isEmpty {
                            Text("请先到签名设置导入证书").foregroundColor(.secondary)
                        } else {
                            Picker("选择证书", selection: $selectedID) {
                                ForEach(certificates.certificates) { item in Text(item.name).tag(item.id) }
                            }
                            if selectedCertificateNeedsPassword {
                                SecureField("旧证书：补录一次 P12 密码", text: $password)
                            }
                        }
                    }
                    Section(header: Text("签名进度")) {
                        HStack {
                            if running { SigningActivityIndicator().frame(width: 20, height: 20) }
                            Text(stageName(state))
                        }
                        if let failure = errorMessage { Text(failure).foregroundColor(.red) }
                        if let artifact = result {
                            Text("处理完成：" + artifact.displayName).foregroundColor(.green)
                            Button("分享 / 保存文件") { showShare = true }
                        }
                    }
                }
                Button(action: start) {
                    Text(running ? "正在处理…" : "确认修改 / 打包")
                        .font(.headline).frame(maxWidth: .infinity).padding(15)
                        .background(Color.blue).foregroundColor(.white).cornerRadius(14)
                }
                .disabled(running || result != nil || !certificates.certificates.contains(where: { $0.id == selectedID }))
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .navigationBarTitle("修改应用信息", displayMode: .inline)
            .navigationBarItems(leading: Button("取消") { presentation.wrappedValue.dismiss() }.disabled(running))
            .onAppear {
                certificates.reload()
                if selectedID.isEmpty { selectedID = certificates.certificates.first?.id ?? "" }
                if let inspection = try? IPAInspector.inspect(ipaURL) {
                    appName = inspection.displayName
                    bundleID = inspection.bundleID
                    version = inspection.version
                }
            }
            .sheet(isPresented: $showShare) {
                if let artifact = result { ActivityShareView(items: [artifact.ipaURL]) }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    private func optionBinding(_ key: WritableKeyPath<SigningOptions, Bool>) -> Binding<Bool> {
        Binding(get: { self.signingOptions.options[keyPath: key] },
                set: { newValue in
                    var options = self.signingOptions.options
                    options[keyPath: key] = newValue
                    self.signingOptions.options = options
                })
    }

    private var selectedCertificateNeedsPassword: Bool {
        !selectedID.isEmpty && CertificatePasswordKeychain.read(for: selectedID) == nil
    }

    private func start() {
        guard !running,
              let certificate = certificates.certificates.first(where: { $0.id == selectedID }) else {
            errorMessage = "请选择已导入的证书"
            return
        }
        running = true
        result = nil
        errorMessage = nil
        state = .prepareContext
        let storedPassword = CertificatePasswordKeychain.read(for: certificate.id)
        let effectivePassword = storedPassword ?? password
        let wasLegacy = storedPassword == nil
        let editing = SigningAppEditing(displayName: appName, bundleIdentifier: bundleID, version: version, minimumOS: minimumOS, removeURLSchemes: removeURLSchemes, outputFormat: outputFormat)
        let request = SigningRequest(ipaURL: ipaURL, certificate: certificate, password: effectivePassword, editing: editing)
        engine.sign(request: request, progress: { nextState in
            state = nextState
        }, completion: { response in
            running = false
            switch response {
            case .success(let artifact):
                if wasLegacy { try? CertificatePasswordKeychain.save(effectivePassword, for: certificate.id) }
                password = ""
                result = artifact
                state = .verifySignature
            case .failure(let error):
                state = .failed
                errorMessage = error.localizedDescription
            }
        })
    }

    private func stageName(_ value: SigningState) -> String {
        switch value {
        case .idle: return "准备就绪"
        case .prepareContext: return "初始化签名环境"
        case .verifyCertificate: return "验证证书"
        case .prepareIPA: return "检查 IPA"
        case .extracting: return "解包 IPA"
        case .signing: return "使用 Zsign 签名"
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
