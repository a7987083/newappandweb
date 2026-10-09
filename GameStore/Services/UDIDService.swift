import Foundation
import Combine
import UIKit
import SafariServices

final class UDIDService: NSObject, ObservableObject, SFSafariViewControllerDelegate {
    static let shared = UDIDService()

    static let didUpdateNotification = Notification.Name("GameStoreUDIDDidUpdate")
    private static let storageKey = "zonoe.deviceUDID"
    private static let pendingCallbackKey = "zonoe.pendingUDIDCallback"
    private static let legacyStorageKey = "gamestore.deviceUDID"
    private static let legacyPendingCallbackKey = "gamestore.pendingUDIDCallback"

    @Published private(set) var udid: String?

    private var localServer: UDIDLocalServer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private override init() {
        let defaults = UserDefaults.standard

        if defaults.string(forKey: Self.storageKey) == nil,
           let legacyUDID = defaults.string(forKey: Self.legacyStorageKey),
           !legacyUDID.isEmpty {
            defaults.set(legacyUDID, forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.legacyStorageKey)
        }

        if defaults.string(forKey: Self.pendingCallbackKey) == nil,
           let legacyCallback = defaults.string(forKey: Self.legacyPendingCallbackKey),
           !legacyCallback.isEmpty {
            defaults.set(legacyCallback, forKey: Self.pendingCallbackKey)
            defaults.removeObject(forKey: Self.legacyPendingCallbackKey)
        }

        udid = defaults.string(forKey: Self.storageKey)
        super.init()

        NotificationCenter.default.addObserver(
            forName: .gameStoreDidOpenURL,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?["url"] as? URL else { return }
            self?.consumeCallback(url)
        }
    }

    func handleProviderRequest(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let callbackValue = components?.queryItems?.first(where: {
            $0.name.caseInsensitiveCompare("callback") == .orderedSame
        })?.value,
        let callbackURL = URL(string: callbackValue) else {
            return
        }

        if let udid = udid, !udid.isEmpty {
            openProviderCallback(callbackURL, udid: udid)
            return
        }

        UserDefaults.standard.set(callbackURL.absoluteString, forKey: Self.pendingCallbackKey)
        requestProfileConfiguration()
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
            safari.delegate = self
            safari.modalPresentationStyle = .pageSheet
            presenter.present(safari, animated: true)
        }
    }


    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openProfileSettings()
            }
        }
    }

    private func openProfileSettings() {
        let candidates = [
            "prefs:root=General&path=ManagedConfigurationList/PurgatoryInstallRequested",
            "prefs:root=General&path=ManagedConfigurationList",
            "App-Prefs:root=General&path=ManagedConfigurationList/PurgatoryInstallRequested",
            "App-Prefs:root=General&path=ManagedConfigurationList"
        ]

        DispatchQueue.main.async {
            self.openProfileSettings(candidates, at: 0)
        }
    }

    private func openProfileSettings(_ candidates: [String], at index: Int) {
        guard index < candidates.count, let url = URL(string: candidates[index]) else {
            showProfileSettingsFallback()
            return
        }

        UIApplication.shared.open(url, options: [:]) { success in
            DispatchQueue.main.async {
                if !success {
                    self.openProfileSettings(candidates, at: index + 1)
                }
            }
        }
    }

    private func showProfileSettingsFallback() {
        let alert = UIAlertController(
            title: "描述文件已下载",
            message: "请前往“设置 → 通用 → VPN 与设备管理”，安装“获取本机 UDID”。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "打开设置", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        guard let presenter = Self.topViewController() else { return }
        presenter.present(alert, animated: true)
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
            self.completePendingProviderCallback(with: value)
        }
    }

    private func completePendingProviderCallback(with udid: String) {
        guard let value = UserDefaults.standard.string(forKey: Self.pendingCallbackKey),
              let callbackURL = URL(string: value) else {
            return
        }

        UserDefaults.standard.removeObject(forKey: Self.pendingCallbackKey)
        openProviderCallback(callbackURL, udid: udid)
    }

    private func openProviderCallback(_ callbackURL: URL, udid: String) {
        guard var components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else { return }
        var items = components.queryItems ?? []
        items.removeAll { $0.name.caseInsensitiveCompare("udid") == .orderedSame }
        items.append(URLQueryItem(name: "udid", value: udid))
        components.queryItems = items

        guard let target = components.url else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(target, options: [:], completionHandler: nil)
        }
    }

    private func consumeCallback(_ url: URL) {
        guard url.scheme?.lowercased() == "zonoe",
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


    private enum LocalError: Error {
        case missingProfile
    }
}
