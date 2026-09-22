import SwiftUI

@main
struct GameStoreApp: App {
    @UIApplicationDelegateAdaptor(GameStoreAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStoreViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

final class GameStoreAppDelegate: NSObject, UIApplicationDelegate {
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
