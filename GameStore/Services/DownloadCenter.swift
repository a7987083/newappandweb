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

    @Published private(set) var items: [Item] = []

    override init() {
        super.init()
        reloadDownloadedItems()
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
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "ipa" }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }

            let activeItems = items.filter {
                $0.state == .queued || $0.state == .downloading || $0.state == .paused
            }
            let activePaths = Set(activeItems.compactMap { $0.localURL?.standardizedFileURL.path })

            let completedItems = files.compactMap { fileURL -> Item? in
                let path = fileURL.standardizedFileURL.path
                guard !activePaths.contains(path) else { return nil }
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

            DispatchQueue.main.async {
                let transientFailures = self.items.filter {
                    $0.state == .failed || $0.state == .cancelled
                }
                self.items = activeItems + completedItems + transientFailures
            }
        } catch {
            // Directory restore is best-effort. Active downloads remain intact.
        }
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

        if items.contains(where: {
            $0.sourceURL == url && ($0.state == .queued || $0.state == .downloading)
        }) {
            return
        }

        let id = UUID()
        let task = session.downloadTask(with: url)
        let item = Item(
            id: id,
            sourceURL: url,
            progress: 0,
            state: .queued,
            localURL: nil,
            errorDescription: nil,
            taskIdentifier: task.taskIdentifier
        )

        DispatchQueue.main.async {
            self.items.append(item)
            self.updateItem(taskIdentifier: task.taskIdentifier) {
                $0.state = .downloading
            }
        }

        task.resume()
    }

    func item(for url: URL) -> Item? {
        items.last(where: { $0.sourceURL == url })
    }

    func cancel(_ item: Item) {
        guard let taskIdentifier = item.taskIdentifier else { return }
        session.getAllTasks { tasks in
            tasks.first(where: { $0.taskIdentifier == taskIdentifier })?.cancel()
        }
        DispatchQueue.main.async {
            self.updateItem(taskIdentifier: taskIdentifier) {
                $0.state = .cancelled
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
        let progress = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        DispatchQueue.main.async {
            self.updateItem(taskIdentifier: downloadTask.taskIdentifier) {
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
                self.updateItem(taskIdentifier: taskIdentifier) {
                    $0.progress = 1
                    $0.state = .completed
                    $0.localURL = destination
                    $0.errorDescription = nil
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.updateItem(taskIdentifier: taskIdentifier) {
                    $0.state = .failed
                    $0.errorDescription = error.localizedDescription
                }
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
            self.updateItem(taskIdentifier: task.taskIdentifier) {
                if (error as NSError).code == NSURLErrorCancelled {
                    $0.state = .cancelled
                } else if $0.state != .failed {
                    $0.state = .failed
                    $0.errorDescription = error.localizedDescription
                }
            }
        }
    }

    private func updateItem(taskIdentifier: Int, mutate: (inout Item) -> Void) {
        guard let index = items.lastIndex(where: { $0.taskIdentifier == taskIdentifier }) else {
            return
        }
        var item = items[index]
        mutate(&item)
        items[index] = item
    }

    private static func downloadsDirectory(fileManager: FileManager = .default) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Downloads", isDirectory: true)
    }

    private static func downloadDestination(
        suggestedFilename: String?,
        sourceURL: URL?
    ) throws -> URL {
        let fileManager = FileManager.default
        let directory = Self.downloadsDirectory(fileManager: fileManager)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var fileName = suggestedFilename?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if fileName == nil || fileName?.isEmpty == true {
            fileName = sourceURL?.lastPathComponent
        }
        if fileName == nil || fileName?.isEmpty == true {
            fileName = "download.ipa"
        }

        let sanitized = fileName!
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")

        let base = (sanitized as NSString).deletingPathExtension
        let ext = (sanitized as NSString).pathExtension
        var destination = directory.appendingPathComponent(sanitized)
        var suffix = 2

        while fileManager.fileExists(atPath: destination.path) {
            let candidate: String
            if ext.isEmpty {
                candidate = "\(base)-\(suffix)"
            } else {
                candidate = "\(base)-\(suffix).\(ext)"
            }
            destination = directory.appendingPathComponent(candidate)
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
