import SwiftUI
import UIKit
import SafariServices

@UIApplicationMain
final class GameStoreAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let store = AppStoreViewModel.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = MainShellViewController()
        window.makeKeyAndVisible()
        self.window = window
        if let file = launchOptions?[.url] as? URL, file.isFileURL {
            IncomingFileRouter.shared.receive(file)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if url.isFileURL {
            IncomingFileRouter.shared.receive(url)
            return true
        }
        guard url.scheme?.lowercased() == "zonoe" else { return false }

        NotificationCenter.default.post(
            name: .gameStoreDidOpenURL,
            object: nil,
            userInfo: ["url": url]
        )

        routeGameStoreURL(url)
        return true
    }
    private func routeGameStoreURL(_ url: URL) {
        let action = url.host?.lowercased() ?? ""

        switch action {
        case "web":
            guard let value = queryValue("url", from: url),
                  let target = URL(string: value),
                  isHTTPURL(target) else { return }
            presentInAppWeb(target)

        case "download", "install":
            let prefix = "zonoe://\(action)/"
            guard url.absoluteString.lowercased().hasPrefix(prefix),
                  let payload = String(url.absoluteString.dropFirst(prefix.count)).removingPercentEncoding,
                  let target = URL(string: payload),
                  isHTTPURL(target) else { return }
            store.downloadCenter.enqueue(target)

        case "udid":
            store.udidService.handleProviderRequest(url)

        default:
            break
        }
    }

    private func queryValue(_ name: String, from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func presentInAppWeb(_ url: URL) {
        DispatchQueue.main.async {
            let controller = SFSafariViewController(url: url)
            UIApplication.shared.gameStoreTopViewController()?
                .present(controller, animated: true)
        }
    }
}

extension UIApplication {
    func gameStoreTopViewController() -> UIViewController? {
        let root = windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? windows.first?.rootViewController

        var current = root

        while true {
            if let presented = current?.presentedViewController {
                current = presented
                continue
            }

            if let navigation = current as? UINavigationController {
                current = navigation.visibleViewController ?? navigation
                continue
            }

            if let tab = current as? UITabBarController {
                current = tab.selectedViewController ?? tab
                continue
            }

            break
        }

        return current
    }
}

extension Notification.Name {
    static let gameStoreDidOpenURL = Notification.Name("GameStoreDidOpenURL")
}

extension Notification.Name {
    static let zonoeIncomingCertificate = Notification.Name("zonoe.incoming.certificate")
}

/// File handoff for AirDrop, Files.app and open-in. Reuses the existing import engines.
final class IncomingFileRouter {
    static let shared = IncomingFileRouter()
    private let fm = FileManager.default
    private let queue = DispatchQueue(label: "zonoe.incoming.files", qos: .userInitiated)
    private init() {}

    func receive(_ url: URL) {
        guard url.isFileURL else { return }
        let ext = url.pathExtension.lowercased()
        guard ["ipa", "tipa", "dylib", "deb", "framework", "p12", "mobileprovision"].contains(ext) else {
            notify("暂不支持导入：" + url.lastPathComponent)
            return
        }
        // Copy while the document-provider security scope is active, before async processing.
        queue.async {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let stagingRoot = self.fm.temporaryDirectory.appendingPathComponent("zonoe-incoming-" + UUID().uuidString, isDirectory: true)
            let staged = stagingRoot.appendingPathComponent(url.lastPathComponent)
            do {
                try self.fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
                try self.fm.copyItem(at: url, to: staged)
                DispatchQueue.main.async {
                    switch ext {
                    case "ipa", "tipa":
                        AppStoreViewModel.shared.downloadCenter.importLocalPackage(staged) { error in
                            try? self.fm.removeItem(at: stagingRoot)
                            self.notify(error == nil ? "安装包已导入：" + url.lastPathComponent : "导入失败：" + (error?.localizedDescription ?? "未知错误"))
                        }
                    case "dylib", "deb", "framework":
                        do {
                            try ZonoePluginLibrary.importFile(staged)
                            self.notify("插件已导入：" + url.lastPathComponent)
                        } catch { self.notify("插件导入失败：" + error.localizedDescription) }
                        try? self.fm.removeItem(at: stagingRoot)
                    case "p12", "mobileprovision":
                        do {
                            let inbox = self.fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                .appendingPathComponent("IncomingCertificates", isDirectory: true)
                            try self.fm.createDirectory(at: inbox, withIntermediateDirectories: true)
                            let dest = inbox.appendingPathComponent(ext == "p12" ? "incoming.p12" : "incoming.mobileprovision")
                            if self.fm.fileExists(atPath: dest.path) { try self.fm.removeItem(at: dest) }
                            try self.fm.copyItem(at: staged, to: dest)
                            NotificationCenter.default.post(name: .zonoeIncomingCertificate, object: nil)
                            self.notify("已接收证书文件，请到签名设置 → 导入证书完成配对验证")
                        } catch { self.notify("证书接收失败：" + error.localizedDescription) }
                        try? self.fm.removeItem(at: stagingRoot)
                    default: break
                    }
                }
            } catch {
                try? self.fm.removeItem(at: stagingRoot)
                self.notify("接收文件失败：" + error.localizedDescription)
            }
        }
    }

    private func notify(_ message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "文件导入", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            UIApplication.shared.gameStoreTopViewController()?.present(alert, animated: true)
        }
    }
}
