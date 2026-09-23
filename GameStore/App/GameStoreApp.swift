import SwiftUI
import UIKit

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
        NotificationCenter.default.post(
            name: .gameStoreDidOpenURL,
            object: nil,
            userInfo: ["url": url]
        )
        return url.scheme?.lowercased() == "gamestore"
    }
}

extension Notification.Name {
    static let gameStoreDidOpenURL = Notification.Name("GameStoreDidOpenURL")
}
