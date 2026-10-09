import SwiftUI
import UIKit
import SafariServices

@UIApplicationMain
final class GameStoreAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let store = AppStoreViewModel()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let rootView = ContentView()
            .environmentObject(store)
        window.rootViewController = UIHostingController(rootView: rootView)
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
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
