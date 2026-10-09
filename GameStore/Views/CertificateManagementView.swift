import SwiftUI
import UniformTypeIdentifiers

struct CertificateManagementView: View {
    @ObservedObject private var store = CertificateStore.shared
    @State private var p12URL: URL?
    @State private var provisionURL: URL?
    @State private var password = ""
    @State private var pickingP12 = false
    @State private var pickingProvision = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        Form {
            Section(header: Text("导入签名证书"),
                    footer: Text("分别选择 P12 与 mobileprovision；证书密码只用于本次校验，不会保存。")) {
                Button("选择 P12 文件") { pickingP12 = true }
                Text(p12URL?.lastPathComponent ?? "未选择 P12")
                    .font(.caption).foregroundColor(.secondary)
                Button("选择 mobileprovision 文件") { pickingProvision = true }
                Text(provisionURL?.lastPathComponent ?? "未选择 mobileprovision")
                    .font(.caption).foregroundColor(.secondary)
                SecureField("P12 密码", text: $password)
                Button("导入证书") {
                    guard let p12 = p12URL, let provision = provisionURL else {
                        errorMessage = "请先选择 P12 和 mobileprovision"
                        return
                    }
                    do {
                        try store.add(p12: p12, provision: provision, password: password)
                        successMessage = "证书已导入"
                        p12URL = nil
                        provisionURL = nil
                        password = ""
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(p12URL == nil || provisionURL == nil)
            }
            Section(header: Text("已导入证书")) {
                if store.certificates.isEmpty {
                    Text("暂无证书").foregroundColor(.secondary)
                } else {
                    ForEach(store.certificates) { certificate in
                        HStack {
                            Image(systemName: "checkmark.shield")
                            VStack(alignment: .leading) {
                                Text(certificate.name)
                                Text(certificate.p12URL?.lastPathComponent ?? "")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                do { try store.remove(certificate) }
                                catch { errorMessage = error.localizedDescription }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }
            }
        }
        .navigationBarTitle("证书管理", displayMode: .inline)
        .fileImporter(isPresented: $pickingP12, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                guard url.pathExtension.lowercased() == "p12" else {
                    errorMessage = "请选择 .p12 文件"; return
                }
                // Copy while the security-scoped URL is accessible: picker URLs may expire.
                do { p12URL = try stage(url) } catch { errorMessage = error.localizedDescription }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $pickingProvision, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                guard url.pathExtension.lowercased() == "mobileprovision" else {
                    errorMessage = "请选择 .mobileprovision 文件"; return
                }
                do { provisionURL = try stage(url) } catch { errorMessage = error.localizedDescription }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert(isPresented: Binding(get: { errorMessage != nil || successMessage != nil },
                                    set: { if !$0 { errorMessage = nil; successMessage = nil } })) {
            Alert(title: Text(errorMessage == nil ? "导入成功" : "导入失败"),
                  message: Text(errorMessage ?? successMessage ?? ""),
                  dismissButton: .default(Text("确定")))
        }
    }

    private func stage(_ url: URL) throws -> URL {
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: staged)
        return staged
    }
}
