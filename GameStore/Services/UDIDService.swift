import Foundation
import Combine
import UIKit
import SafariServices

/// Profile Service UDID coordinator. The local server is replaced for every
/// explicit acquisition; callbacks and POST share one idempotent completion path.
final class UDIDService: NSObject, ObservableObject, SFSafariViewControllerDelegate {
    static let shared = UDIDService()
    static let didUpdateNotification = Notification.Name("GameStoreUDIDDidUpdate")
    private static let storageKey = "zonoe.deviceUDID"
    private static let pendingCallbackKey = "zonoe.pendingUDIDCallback"

    @Published private(set) var udid: String?
    @Published private(set) var acquisitionError: String?

    private var localServer: UDIDLocalServer?
    private var sessionToken: String?
    private var completedSession: String?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private override init() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.storageKey) == nil,
           let old = defaults.string(forKey: "gamestore.deviceUDID"), !old.isEmpty {
            defaults.set(old, forKey: Self.storageKey)
            defaults.removeObject(forKey: "gamestore.deviceUDID")
        }
        if defaults.string(forKey: Self.pendingCallbackKey) == nil,
           let old = defaults.string(forKey: "gamestore.pendingUDIDCallback"), !old.isEmpty {
            defaults.set(old, forKey: Self.pendingCallbackKey)
            defaults.removeObject(forKey: "gamestore.pendingUDIDCallback")
        }
        udid = defaults.string(forKey: Self.storageKey)
        super.init()
        NotificationCenter.default.addObserver(
            forName: .gameStoreDidOpenURL, object: nil, queue: .main
        ) { [weak self] notice in
            guard let url = notice.userInfo?["url"] as? URL else { return }
            self?.handleCompletionURL(url)
        }
    }

    func handleProviderRequest(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let value = items.first(where: { $0.name.lowercased() == "callback" })?.value,
              let callback = URL(string: value), callback.scheme != nil else { return }
        if let udid = udid, !udid.isEmpty {
            deliverProviderCallback(callback, udid: udid)
        } else {
            UserDefaults.standard.set(callback.absoluteString, forKey: Self.pendingCallbackKey)
            requestProfileConfiguration()
        }
    }

    func requestProfileConfiguration() {
        DispatchQueue.main.async {
            self.acquisitionError = nil
            do {
                try self.startAcquisition()
                self.beginBackgroundTask()
                guard let url = URL(string: "http://127.0.0.1:\(UDIDLocalServer.port)/profile.mobileconfig"),
                      let presenter = UIApplication.shared.gameStoreTopViewController() else {
                    throw AcquisitionError.presenterUnavailable
                }
                let browser = SFSafariViewController(url: url)
                browser.delegate = self
                browser.modalPresentationStyle = .pageSheet
                presenter.present(browser, animated: true)
            } catch {
                self.localServer?.stop()
                self.localServer = nil
                self.sessionToken = nil
                self.endBackgroundTask()
                self.acquisitionError = error.localizedDescription
                self.presentError(error.localizedDescription)
            }
        }
    }

    private func startAcquisition() throws {
        // A stopped local server object must never prevent a later attempt.
        localServer?.stop()
        localServer = nil
        sessionToken = nil
        completedSession = nil

        guard let file = Bundle.main.url(forResource: "UDIDRequest", withExtension: "mobileconfig"),
              let template = try? String(contentsOf: file, encoding: .utf8) else {
            throw AcquisitionError.missingProfile
        }
        let endpoint = "http://127.0.0.1:\(UDIDLocalServer.port)/udid"
        guard template.contains(endpoint) else { throw AcquisitionError.missingProfile }

        let token = UUID().uuidString.lowercased()
        let configured = template.replacingOccurrences(of: endpoint, with: endpoint + "?session=" + token)
        guard let payload = configured.data(using: .utf8) else { throw AcquisitionError.missingProfile }
        let server = UDIDLocalServer(profileData: payload, sessionToken: token) { [weak self] result in
            self?.finishAcquisition(result, session: token)
        }
        try server.start()
        sessionToken = token
        localServer = server
    }

    private func finishAcquisition(_ value: String, session: String) {
        DispatchQueue.main.async {
            guard self.sessionToken == session, self.completedSession != session else { return }
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            self.completedSession = session
            UserDefaults.standard.set(clean, forKey: Self.storageKey)
            self.udid = clean
            self.acquisitionError = nil
            NotificationCenter.default.post(name: Self.didUpdateNotification, object: clean)
            self.deliverPendingCallback(clean)
            self.endBackgroundTask()
        }
    }

    private func handleCompletionURL(_ url: URL) {
        guard url.scheme?.lowercased() == "zonoe",
              url.host?.lowercased() == "udid-complete",
              let expected = sessionToken else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "session" })?.value == expected else { return }
        if let value = items.first(where: { $0.name.lowercased() == "udid" })?.value {
            finishAcquisition(value, session: expected)
        }
        endBackgroundTask()
    }

    private func deliverPendingCallback(_ value: String) {
        guard let raw = UserDefaults.standard.string(forKey: Self.pendingCallbackKey),
              let url = URL(string: raw) else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingCallbackKey)
        deliverProviderCallback(url, udid: value)
    }

    private func deliverProviderCallback(_ callback: URL, udid: String) {
        guard var target = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return }
        var items = target.queryItems ?? []
        items.removeAll { $0.name.lowercased() == "udid" }
        items.append(URLQueryItem(name: "udid", value: udid))
        target.queryItems = items
        if let url = target.url { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true) {
            self.openProfileSettings()
        }
    }

    private func openProfileSettings() {
        let paths = [
            "prefs:root=General&path=ManagedConfigurationList/PurgatoryInstallRequested",
            "prefs:root=General&path=ManagedConfigurationList",
            "App-Prefs:root=General&path=ManagedConfigurationList/PurgatoryInstallRequested",
            "App-Prefs:root=General&path=ManagedConfigurationList"
        ]
        openSettings(paths, at: 0)
    }

    private func openSettings(_ paths: [String], at index: Int) {
        guard index < paths.count, let url = URL(string: paths[index]) else {
            let alert = UIAlertController(
                title: "描述文件已下载",
                message: "前往“设置 → 通用 → VPN 与设备管理”安装描述文件。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            UIApplication.shared.gameStoreTopViewController()?.present(alert, animated: true)
            return
        }
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok { DispatchQueue.main.async { self.openSettings(paths, at: index + 1) } }
        }
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "获取 UDID 失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        UIApplication.shared.gameStoreTopViewController()?.present(alert, animated: true)
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "GameStore.UDID") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private enum AcquisitionError: LocalizedError {
        case missingProfile, presenterUnavailable
        var errorDescription: String? {
            switch self {
            case .missingProfile: return "应用内的 UDID 描述文件模板缺失或无效"
            case .presenterUnavailable: return "无法打开描述文件下载界面"
            }
        }
    }
}
