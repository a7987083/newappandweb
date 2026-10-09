import SwiftUI
import UIKit

struct SigningExecutionView: View {
    let ipaURL: URL
    @ObservedObject private var certificates = CertificateStore.shared
    @Environment(\.presentationMode) private var presentation
    @State private var selectedID = ""
    @State private var password = ""
    @State private var state: SigningState = .idle
    @State private var running = false
    @State private var result: SignedArtifact?
    @State private var errorMessage: String?
    @State private var showShare = false
    private let engine = AppSigningService()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("待签名 IPA")) {
                    Text(ipaURL.lastPathComponent).font(.footnote)
                }
                Section(header: Text("签名证书")) {
                    if certificates.certificates.isEmpty {
                        Text("暂无证书。请先前往「我的 → 签名设置 → 导入证书」。")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("选择证书", selection: $selectedID) {
                            ForEach(certificates.certificates) { item in
                                Text(item.name).tag(item.id)
                            }
                        }
                        SecureField("P12 密码", text: $password)
                    }
                }
                Section(header: Text("签名进度")) {
                    HStack {
                        if running { SigningActivityIndicator().frame(width: 20, height: 20).padding(.trailing, 6) }
                        Text(stageName(state))
                    }
                    if let failure = errorMessage {
                        Text(failure).foregroundColor(.red).font(.footnote)
                    }
                    if let artifact = result {
                        Text("签名完成：\(artifact.displayName) \(artifact.version)")
                            .foregroundColor(.green)
                        Text(artifact.ipaURL.lastPathComponent).font(.footnote)
                        Button("分享 / 保存签名 IPA") { showShare = true }
                    }
                }
                Section {
                    Button(running ? "签名处理中…" : "开始签名") { start() }
                        .disabled(running || result != nil ||
                                  !certificates.certificates.contains(where: { $0.id == selectedID }))
                }
            }
            .navigationBarTitle("IPA 签名", displayMode: .inline)
            .navigationBarItems(trailing: Button("关闭") { presentation.wrappedValue.dismiss() }
                .disabled(running))
            .onAppear {
                certificates.reload()
                if selectedID.isEmpty { selectedID = certificates.certificates.first?.id ?? "" }
            }
            .sheet(isPresented: $showShare) {
                if let artifact = result {
                    ActivityShareView(items: [artifact.ipaURL])
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
        let request = SigningRequest(ipaURL: ipaURL, certificate: certificate, password: password)
        engine.sign(request: request, progress: { nextState in
            state = nextState
        }, completion: { response in
            running = false
            password = ""
            switch response {
            case .success(let artifact):
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
