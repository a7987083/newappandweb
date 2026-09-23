import Foundation
import Combine

final class DownloadCenter: ObservableObject {
    enum State: String {
        case queued, downloading, paused, completed, failed, cancelled
    }

    struct Item: Identifiable {
        let id = UUID()
        let sourceURL: URL
        var progress: Double
        var state: State
        var localURL: URL?
        var errorDescription: String?
    }

    @Published private(set) var items: [Item] = []

    func enqueue(_ url: URL) {
        items.append(Item(sourceURL: url, progress: 0, state: .queued))
        // v0.1 establishes the queue/state boundary. URLSession background transfer
        // and persistence are implemented after endpoint validation.
    }
}
