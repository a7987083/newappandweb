import Foundation
import Combine
import UIKit
import SafariServices

final class UDIDService: ObservableObject {
    static let shared = UDIDService()

    @Published private(set) var udid: String?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .gameStoreDidOpenURL,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?["url"] as? URL else { return }
            self?.consumeCallback(url)
        }
    }

    func requestProfileConfiguration() {
        guard let url = URL(string: "https://new.iosgame.vip/device/udid/config/") else { return }

        DispatchQueue.main.async {
            guard let presenter = Self.topViewController() else { return }

            let safari = SFSafariViewController(url: url)
            safari.modalPresentationStyle = .pageSheet
            presenter.present(safari, animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? UIApplication.shared.windows.first?.rootViewController

        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }

        if let navigation = current as? UINavigationController {
            return navigation.visibleViewController ?? navigation
        }

        if let tab = current as? UITabBarController {
            return tab.selectedViewController ?? tab
        }

        return current
    }

    private func consumeCallback(_ url: URL) {
        guard url.scheme?.lowercased() == "gamestore" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let value = components?.queryItems?.first(where: {
            ["udid", "UDID"].contains($0.name)
        })?.value

        guard let value = value, !value.isEmpty else { return }
        udid = value
    }
}
