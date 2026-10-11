import UIKit

/// Deterministic lifecycle for a shell search presentation.
/// Stale animation completions cannot reactivate a restoring search.
final class ShellSearchPhaseMachine {
    enum Phase { case idle, activating, active, restoring }
    private(set) var phase: Phase = .idle
    var isSearching: Bool { phase == .activating || phase == .active }

    @discardableResult func begin() -> Bool {
        guard phase == .idle else { return false }
        phase = .activating
        return true
    }

    @discardableResult func activate() -> Bool {
        guard phase == .activating else { return false }
        phase = .active
        return true
    }

    @discardableResult func startRestoring() -> Bool {
        guard phase == .activating || phase == .active else { return false }
        phase = .restoring
        return true
    }

    func finishRestoring() {
        guard phase == .restoring else { return }
        phase = .idle
    }
}

final class ShellSearchSession {
    struct Anchor {
        let row: Int?
        let screenDelta: CGFloat
    }

    private var originalFrame: CGRect = .zero
    private var originalBottomInset: CGFloat = 0
    private var originalOffset: CGFloat = 0
    private var keyboardObserver: NSObjectProtocol?

    deinit { stopObservingKeyboard() }

    func begin(on table: UITableView, in host: UIView, safeTop: CGFloat) {
        stopObservingKeyboard()
        table.layoutIfNeeded()
        originalFrame = table.frame
        originalOffset = table.contentOffset.y
        originalBottomInset = table.contentInset.bottom
    }

    func activateViewport(on table: UITableView, in host: UIView, safeTop: CGFloat) {
        let bottom = safeTop + 61
        table.frame = CGRect(x: originalFrame.minX, y: bottom,
                             width: originalFrame.width,
                             height: max(0, originalFrame.height - bottom))
        table.setContentOffset(.zero, animated: false)
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main
        ) { [weak self, weak table, weak host] note in
            guard let self = self, let table = table, let host = host,
                  let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let local = host.convert(frame, from: nil)
            let overlap = max(0, host.bounds.maxY - max(host.bounds.minY, local.minY))
            let bottomInset = max(self.originalBottomInset, overlap + 12)
            table.contentInset.bottom = bottomInset
            table.scrollIndicatorInsets.bottom = bottomInset
        }
    }

    func captureCurrent(on table: UITableView) -> Anchor {
        table.layoutIfNeeded()
        let offset = table.contentOffset.y
        let row = table.indexPathsForVisibleRows?
            .filter { $0.section == 0 }
            .min { $0.row < $1.row }?.row
        let delta = row.map {
            table.rectForRow(at: IndexPath(row: $0, section: 0)).minY - offset
        } ?? 0
        return Anchor(row: row, screenDelta: delta + table.frame.minY - originalFrame.minY)
    }

    func restoreViewport(on table: UITableView) {
        stopObservingKeyboard()
        table.contentInset.bottom = originalBottomInset
        table.scrollIndicatorInsets.bottom = originalBottomInset
        table.frame = originalFrame
    }

    func restoreAnchor(on table: UITableView, row: Int?, anchor: Anchor) {
        table.layoutIfNeeded()
        let offset: CGFloat
        if let row = row, row >= 0, row < table.numberOfRows(inSection: 0) {
            offset = table.rectForRow(at: IndexPath(row: row, section: 0)).minY - anchor.screenDelta
        } else {
            offset = originalOffset
        }
        let minimum = -table.adjustedContentInset.top
        let maximum = max(minimum, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
        table.setContentOffset(CGPoint(x: 0, y: min(max(offset, minimum), maximum)), animated: false)
    }

    private func stopObservingKeyboard() {
        if let observer = keyboardObserver {
            NotificationCenter.default.removeObserver(observer)
            keyboardObserver = nil
        }
    }
}

