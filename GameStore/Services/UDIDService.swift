import Foundation
import Combine
import UIKit
import SafariServices

final class UDIDService: ObservableObject {
    static let shared = UDIDService()

    static let didUpdateNotification = Notification.Name("GameStoreUDIDDidUpdate")
    private static let storageKey = "gamestore.deviceUDID"

    @Published private(set) var udid: String?

    private var localServer: UDIDLocalServer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        udid = UserDefaults.standard.string(forKey: Self.storageKey)

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
        beginBackgroundTask()

        do {
            try ensureLocalServerRunning()
        } catch {
            endBackgroundTask()
            return
        }

        guard let url = URL(string: "http://127.0.0.1:\(UDIDLocalServer.port)/profile.mobileconfig") else {
            endBackgroundTask()
            return
        }

        DispatchQueue.main.async {
            guard let presenter = Self.topViewController() else {
                self.endBackgroundTask()
                return
            }

            let safari = SFSafariViewController(url: url)
            safari.modalPresentationStyle = .pageSheet
            presenter.present(safari, animated: true)
        }
    }

    private func ensureLocalServerRunning() throws {
        if localServer != nil { return }

        guard let profileURL = Bundle.main.url(forResource: "UDIDRequest", withExtension: "mobileconfig"),
              let profileData = try? Data(contentsOf: profileURL) else {
            throw LocalError.missingProfile
        }

        let server = UDIDLocalServer(profileData: profileData) { [weak self] udid in
            self?.saveUDID(udid)
        }

        try server.start()
        localServer = server
    }

    private func saveUDID(_ value: String) {
        guard !value.isEmpty else { return }
        UserDefaults.standard.set(value, forKey: Self.storageKey)

        DispatchQueue.main.async {
            self.udid = value
            NotificationCenter.default.post(name: Self.didUpdateNotification, object: value)
        }
    }

    private func consumeCallback(_ url: URL) {
        guard url.scheme?.lowercased() == "gamestore",
              url.host?.lowercased() == "udid-complete" else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let value = components?.queryItems?.first(where: {
            $0.name.caseInsensitiveCompare("udid") == .orderedSame
        })?.value

        if let value = value, !value.isEmpty {
            saveUDID(value)
        }

        dismissPresentedSafariIfNeeded()
        endBackgroundTask()
    }

    private func dismissPresentedSafariIfNeeded() {
        DispatchQueue.main.async {
            guard let presenter = Self.topViewController() else { return }
            if presenter is SFSafariViewController {
                presenter.dismiss(animated: true)
            }
        }
    }

    private func beginBackgroundTask() {
        DispatchQueue.main.async {
            guard self.backgroundTask == .invalid else { return }
            self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "GameStore.udid") { [weak self] in
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        DispatchQueue.main.async {
            guard self.backgroundTask != .invalid else { return }
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
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

    private enum LocalError: Error {
        case missingProfile
    }
}
