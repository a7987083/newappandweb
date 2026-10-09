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
    private static let pendingNonceKey = "zonoe.pendingUDIDNonce"

    @Published private(set) var udid: String?
    @Published private(set) var acquisitionError: String?

    private var localServer: UDIDLocalServer?
    private let bridgeLock = NSLock()
    private var bridgeResults: [String: (udid: String, expiry: Date)] = [:]
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
              let callback = URL(string: value), let scheme = callback.scheme,
              !scheme.isEmpty, scheme.lowercased() != "http",
              scheme.lowercased() != "https" else { return }
        let nonce = items.first(where: { $0.name.lowercased() == "nonce" })?.value
        let validNonce = nonce.flatMap { UDIDLocalServer.validNonce($0) ? $0 : nil }
        if let udid = udid, !udid.isEmpty {
            deliverProviderCallback(callback, udid: udid, nonce: validNonce)
        } else {
            UserDefaults.standard.set(callback.absoluteString, forKey: Self.pendingCallbackKey)
            if let validNonce {
                UserDefaults.standard.set(validNonce, forKey: Self.pendingNonceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingNonceKey)
            }
            requestProfileConfiguration()
        }
    }

    private func bridgeResult(_ nonce: String) -> String? {
        bridgeLock.lock()
        defer { bridgeLock.unlock() }
        bridgeResults = bridgeResults.filter { $0.value.expiry > Date() }
        return bridgeResults[nonce]?.udid
    }

    private func acknowledgeBridge(_ nonce: String) -> Bool {
        bridgeLock.lock()
        let didRemove = bridgeResults.removeValue(forKey: nonce) != nil
        bridgeLock.unlock()
        if didRemove {
            DispatchQueue.main.async { self.endBackgroundTask() }
        }
        return didRemove
    }

    private func makeServer(profileData: Data, token: String, onUDID: @escaping (String) -> Void) -> UDIDLocalServer {
        UDIDLocalServer(
            profileData: profileData, sessionToken: token, onUDID: onUDID,
            bridgeRead: { [weak self] nonce in self?.bridgeResult(nonce) },
            bridgeAck: { [weak self] nonce in self?.acknowledgeBridge(nonce) ?? false }
        )
    }

    private func ensureBridgeServer() -> Bool {
        if localServer != nil { return true }
        let server = makeServer(profileData: Data(), token: "", onUDID: { _ in })
        do {
            try server.start()
            localServer = server
            return true
        } catch {
            return false
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
        let server = makeServer(profileData: payload, token: token) { [weak self] result in
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
        let nonce = UserDefaults.standard.string(forKey: Self.pendingNonceKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingCallbackKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingNonceKey)
        deliverProviderCallback(url, udid: value, nonce: nonce)
    }

    private func deliverProviderCallback(_ callback: URL, udid: String, nonce: String? = nil) {
        guard var target = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return }
        var items = target.queryItems ?? []
        items.removeAll { $0.name.lowercased() == "udid" || $0.name.lowercased() == "nonce" }

        // No-hook protocol: nonce stays with the caller; the callback URL wakes it only.
        if let nonce = nonce, UDIDLocalServer.validNonce(nonce), ensureBridgeServer() {
            bridgeLock.lock()
            bridgeResults = bridgeResults.filter { $0.value.expiry > Date() }
            bridgeResults[nonce] = (udid, Date().addingTimeInterval(60))
            bridgeLock.unlock()
            target.queryItems = items.isEmpty ? nil : items
            beginBackgroundTask()
        } else {
            // Legacy consumers receive UDID directly when bridge setup is unavailable.
            items.append(URLQueryItem(name: "udid", value: udid))
            target.queryItems = items
        }
        if let url = target.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
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
