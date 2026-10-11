import Foundation
import Combine
import UIKit

/// Read-only catalog adapter for TrollSkin's Objective-C application tab.
/// Parsing, caching and network requests remain in SoftwareSourceStore.
@objcMembers final class SourceCatalogUIBridge: NSObject {
    private static let instance = SourceCatalogUIBridge()
    private var subscription: AnyCancellable?

    private override init() {
        super.init()
        subscription = SoftwareSourceStore.shared.$catalogApps
            .receive(on: DispatchQueue.main)
            .sink { _ in
                NotificationCenter.default.post(name: Notification.Name("GameStoreSourceCatalogDidChange"), object: nil)
            }
    }

    class func start() { _ = instance }

    class func hasSources() -> Bool { !SoftwareSourceStore.shared.sources.isEmpty }

    class func refresh() {
        guard hasSources() else { return }
        SoftwareSourceStore.shared.refreshCatalog()
    }

    class func entries() -> [[String: String]] {
        _ = instance
        return SoftwareSourceStore.shared.catalogApps.map { app in
            let info = [app.version, app.bundleIdentifier].filter { !$0.isEmpty }.joined(separator: " · ")
            return [
                "name": app.name,
                "detail": info,
                "category": app.category.isEmpty ? "软件源" : app.category,
                "iconURL": app.iconURL?.absoluteString ?? ""
            ]
        }
    }

    class func loadIcon(_ address: String, completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            completion(nil)
            return
        }
        SourceIconCache.shared.load(url, completion: completion)
    }

    class func cachedIcon(_ address: String) -> UIImage? {
        guard let url = URL(string: address) else { return nil }
        return SourceIconCache.shared.cachedMemoryImage(for: url)
    }
}
