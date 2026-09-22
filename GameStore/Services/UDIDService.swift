import Foundation
import UIKit

@MainActor
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
        UIApplication.shared.open(url)
    }

    private func consumeCallback(_ url: URL) {
        guard url.scheme?.lowercased() == "gamestore" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let value = components?.queryItems?.first(where: {
            ["udid", "UDID"].contains($0.name)
        })?.value

        guard let value, !value.isEmpty else { return }
        udid = value
    }
}
