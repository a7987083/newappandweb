import Foundation
import Combine

/// Retains the app-wide download and device services. No source catalog binding.
final class AppStoreViewModel: ObservableObject {
    let downloadCenter = DownloadCenter()
    let udidService = UDIDService.shared
}
