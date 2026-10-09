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

    private var resumeDataByURL: [URL: Data] = [:]
    private var pausingTaskIDs = Set<Int>()

    // Resume data is persisted to Application Support, not UserDefaults.
    private struct PausedRecord: Codable {
        let sourceURL: URL
        let progress: Double
        let resumeData: Data
    }

    private static var pauseArchiveURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return base.appendingPathComponent("download-pauses.json")
    }

    private func savePausedRecords() {
        let records: [PausedRecord] = activeItems.compactMap { item in
            guard item.state == .paused,
                  let data = resumeDataByURL[item.sourceURL] else { return nil }
            return PausedRecord(
                sourceURL: item.sourceURL, progress: item.progress, resumeData: data
            )
        }
        do {
            let destination = Self.pauseArchiveURL
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try JSONEncoder().encode(records).write(to: destination, options: .atomic)
        } catch {
            // Save failure must not abort the download state transition.
            NSLog("DownloadCenter: could not persist pause data: %@", String(describing: error))
        }
    }

    private func restorePausedRecords() {
        guard let data = try? Data(contentsOf: Self.pauseArchiveURL),
              let records = try? JSONDecoder().decode([PausedRecord].self, from: data)
        else { return }

        for record in records {
            guard !activeItems.contains(where: { $0.sourceURL == record.sourceURL }) else {
                continue
            }
            resumeDataByURL[record.sourceURL] = record.resumeData
            activeItems.append(Item(
                id: UUID(), sourceURL: record.sourceURL,
                progress: record.progress, state: .paused,
                localURL: nil, errorDescription: nil, taskIdentifier: nil
            ))
        }
    }

    var items: [Item] {
        activeItems + completedItems + terminalItems
    }

    override init() {
        super.init()
        restorePausedRecords()
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

        // All observable queue mutations and duplicate checks run on main.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.enqueue(url) }
            return
        }

        guard !activeItems.contains(where: { $0.sourceURL == url }) else {
            return
        }

        terminalItems.removeAll { $0.sourceURL == url }
        // A manual retry starts a fresh transfer, not stale resume bytes.
        resumeDataByURL.removeValue(forKey: url)
        savePausedRecords()

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
        activeItems.append(item)
        updateActiveItem(taskIdentifier: task.taskIdentifier) {
            $0.state = .downloading
        }
        task.resume()
    }

    func pause(_ item: Item) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.pause(item) }
            return
        }
        guard item.state == .downloading, let identifier = item.taskIdentifier,
              !pausingTaskIDs.contains(identifier) else { return }
        pausingTaskIDs.insert(identifier)
        session.getAllTasks { [weak self] tasks in
            guard let self = self else { return }
            guard let download = tasks.first(where: { $0.taskIdentifier == identifier })
                as? URLSessionDownloadTask else {
                DispatchQueue.main.async {
                    self.pausingTaskIDs.remove(identifier)
                }
                return
            }
            download.cancel(byProducingResumeData: { data in
                DispatchQueue.main.async {
                    self.pausingTaskIDs.remove(identifier)
                    if let data = data {
                        self.resumeDataByURL[item.sourceURL] = data
                        self.updateActiveItem(taskIdentifier: identifier) {
                            $0.state = .paused
                            $0.taskIdentifier = nil
                        }
                        self.savePausedRecords()
                    } else {
                        self.finishActiveItem(
                            taskIdentifier: identifier,
                            state: .cancelled,
                            localURL: nil,
                            errorDescription: nil
                        )
                    }
                }
            })
        }
    }

    func resume(_ item: Item) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.resume(item) }
            return
        }
        guard item.state == .paused,
              let index = activeItems.firstIndex(where: { $0.id == item.id }),
              let data = resumeDataByURL.removeValue(forKey: item.sourceURL) else {
            return
        }
        let task = session.downloadTask(withResumeData: data)
        activeItems[index].taskIdentifier = task.taskIdentifier
        activeItems[index].state = .downloading
        savePausedRecords()
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
            if let task = tasks.first(where: { $0.taskIdentifier == taskIdentifier }) {
                // Let URLSession's completion decide the terminal state.
                // A download that already completed must not become cancelled.
                task.cancel()
            } else {
                DispatchQueue.main.async {
                    self.finishActiveItem(
                        taskIdentifier: taskIdentifier,
                        state: .cancelled,
                        localURL: nil,
                        errorDescription: nil
                    )
                }
            }
        }
    }

    func deleteDownloadedItem(_ item: Item) throws {
        guard item.state == .completed,
              let localURL = item.localURL else {
            return
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }

        let path = localURL.standardizedFileURL.path
        completedItems.removeAll {
            $0.localURL?.standardizedFileURL.path == path
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

            // Never delete an existing IPA. downloadDestination already chooses
            // a unique filename; moveItem fails safely if another writer wins.
            try FileManager.default.moveItem(at: location, to: destination)

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
            if self.pausingTaskIDs.contains(task.taskIdentifier) { return }
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
