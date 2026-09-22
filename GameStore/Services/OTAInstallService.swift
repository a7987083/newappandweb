import Foundation
import UIKit

struct OTAInstallService {
    static func install(manifestURL: URL) async -> Bool {
        guard var components = URLComponents(string: "itms-services://") else {
            return false
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: manifestURL.absoluteString)
        ]
        guard let installURL = components.url else { return false }

        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                UIApplication.shared.open(installURL, options: [:]) { accepted in
                    continuation.resume(returning: accepted)
                }
            }
        }
    }
}
