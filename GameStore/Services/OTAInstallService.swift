import Foundation
import UIKit

struct OTAInstallService {
    static func install(manifestURL: URL, completion: @escaping (Bool) -> Void) {
        guard var components = URLComponents(string: "itms-services://") else {
            completion(false)
            return
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: manifestURL.absoluteString)
        ]
        guard let installURL = components.url else {
            completion(false)
            return
        }

        DispatchQueue.main.async {
            UIApplication.shared.open(installURL, options: [:], completionHandler: completion)
        }
    }
}
