import Foundation
import Combine

final class DownloadCenter: NSObject, ObservableObject, URLSessionDownloadDelegate {
    enum State: String {
        case queued, downloading, paused, completed, failed, cancelled
    }

    struct Item: Identifiable {
        let id: UUID
        let sourceURL: URL
        var progress: Double
        var state: State
        var localURL: URL?
        var errorDescription: String?
        var taskIdentifier: Int?
    }

    @Published private(set) var activeItems: [Item] = []
    @Published private(set) var completedItems: [Item] = []
    @Published private(set) var terminalItems: [Item] = []

    var items: [Item] {
        activeItems + completedItems + terminalItems
    }

    override init() {
        super.init()
        reloadDownloadedItems()
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }()

    func enqueue(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }

        guard !activeItems.contains(where: { $0.sourceURL == url }) else {
            return
        }

        terminalItems.removeAll { $0.sourceURL == url }

        let task = session.downloadTask(with: url)
        let item = Item(
            id: UUID(),
            sourceURL: url,
            progress: 0,
            state: .queued,
            localURL: nil,
            errorDescription: nil,
            taskIdentifier: task.taskIdentifier
        )

        DispatchQueue.main.async {
            self.activeItems.append(item)
            self.updateActiveItem(taskIdentifier: task.taskIdentifier) {
                $0.state = .downloading
            }
        }

        task.resume()
    }

    func item(for url: URL) -> Item? {
        if let active = activeItems.last(where: { $0.sourceURL == url }) {
            return active
        }
        if let completed = completedItems.last(where: { $0.sourceURL == url }) {
            return completed
        }
        return terminalItems.last(where: { $0.sourceURL == url })
    }

    func cancel(_ item: Item) {
        guard let taskIdentifier = item.taskIdentifier else { return }

        session.getAllTasks { tasks in
            tasks.first(where: { $0.taskIdentifier == taskIdentifier })?.cancel()
        }

        DispatchQueue.main.async {
            self.finishActiveItem(
                taskIdentifier: taskIdentifier,
                state: .cancelled,
                localURL: nil,
                errorDescription: nil
            )
        }
    }

    func reloadDownloadedItems() {
        let fileManager = FileManager.default
        let directory = Self.downloadsDirectory(fileManager: fileManager)

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let files = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "ipa" }
            .sorted {
                let lhs = (try? $0.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }

            DispatchQueue.main.async {
                let existingByPath = Dictionary(
                    uniqueKeysWithValues: self.completedItems.compactMap { item -> (String, Item)? in
                        guard let localURL = item.localURL else { return nil }
                        return (localURL.standardizedFileURL.path, item)
                    }
                )

                self.completedItems = files.map { fileURL in
                    let path = fileURL.standardizedFileURL.path
                    if let existing = existingByPath[path] {
                        return existing
                    }

                    return Item(
                        id: UUID(),
                        sourceURL: fileURL,
                        progress: 1,
                        state: .completed,
                        localURL: fileURL,
                        errorDescription: nil,
                        taskIdentifier: nil
                    )
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.terminalItems.append(
                    Item(
                        id: UUID(),
                        sourceURL: directory,
                        progress: 0,
                        state: .failed,
                        localURL: nil,
                        errorDescription: "读取下载目录失败：\(error.localizedDescription)",
                        taskIdentifier: nil
                    )
                )
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }

        let progress = min(
            1,
            max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        )

        DispatchQueue.main.async {
            self.updateActiveItem(taskIdentifier: downloadTask.taskIdentifier) {
                $0.progress = progress
                $0.state = .downloading
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskIdentifier = downloadTask.taskIdentifier

        do {
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                throw DownloadCenterError.httpStatus(response.statusCode)
            }

            let destination = try Self.downloadDestination(
                suggestedFilename: downloadTask.response?.suggestedFilename,
                sourceURL: downloadTask.originalRequest?.url
            )

            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)

            DispatchQueue.main.async {
                self.finishActiveItem(
                    taskIdentifier: taskIdentifier,
                    state: .completed,
                    localURL: destination,
                    errorDescription: nil
                )
            }
        } catch {
            DispatchQueue.main.async {
                self.finishActiveItem(
                    taskIdentifier: taskIdentifier,
                    state: .failed,
                    localURL: nil,
                    errorDescription: error.localizedDescription
                )
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error else { return }

        DispatchQueue.main.async {
            let state: State = (error as NSError).code == NSURLErrorCancelled
                ? .cancelled
                : .failed

            self.finishActiveItem(
                taskIdentifier: task.taskIdentifier,
                state: state,
                localURL: nil,
                errorDescription: state == .failed ? error.localizedDescription : nil
            )
        }
    }

    private func updateActiveItem(
        taskIdentifier: Int,
        mutate: (inout Item) -> Void
    ) {
        guard let index = activeItems.lastIndex(where: {
            $0.taskIdentifier == taskIdentifier
        }) else {
            return
        }

        var item = activeItems[index]
        mutate(&item)
        activeItems[index] = item
    }

    private func finishActiveItem(
        taskIdentifier: Int,
        state: State,
        localURL: URL?,
        errorDescription: String?
    ) {
        guard let index = activeItems.lastIndex(where: {
            $0.taskIdentifier == taskIdentifier
        }) else {
            return
        }

        var item = activeItems.remove(at: index)
        item.progress = state == .completed ? 1 : item.progress
        item.state = state
        item.localURL = localURL
        item.errorDescription = errorDescription
        item.taskIdentifier = nil

        switch state {
        case .completed:
            guard let localURL = localURL else { return }
            let path = localURL.standardizedFileURL.path
            completedItems.removeAll {
                $0.localURL?.standardizedFileURL.path == path
            }
            completedItems.insert(item, at: 0)

        case .failed, .cancelled:
            terminalItems.removeAll { $0.sourceURL == item.sourceURL }
            terminalItems.insert(item, at: 0)

        case .queued, .downloading, .paused:
            break
        }
    }

    private static func downloadsDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let documents = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        return documents.appendingPathComponent(
            "Downloads",
            isDirectory: true
        )
    }

    private static func downloadDestination(
        suggestedFilename: String?,
        sourceURL: URL?
    ) throws -> URL {
        let fileManager = FileManager.default
        let directory = downloadsDirectory(fileManager: fileManager)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let fallback = sourceURL?.lastPathComponent
        var fileName = suggestedFilename?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if fileName == nil || fileName?.isEmpty == true {
            fileName = fallback
        }
        if fileName == nil || fileName?.isEmpty == true {
            fileName = "download.ipa"
        }

        var sanitized = fileName!
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")

        if sanitized.lowercased().hasSuffix(".ipa") == false {
            sanitized += ".ipa"
        }

        let base = (sanitized as NSString).deletingPathExtension
        let ext = (sanitized as NSString).pathExtension

        var destination = directory.appendingPathComponent(sanitized)
        var suffix = 2

        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(
                "\(base)-\(suffix).\(ext)"
            )
            suffix += 1
        }

        return destination
    }
}

enum DownloadCenterError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "下载服务器返回 HTTP \(code)"
        }
    }
}
