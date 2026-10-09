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
    private var resumedTaskIDs = Set<Int>()
    private let persistenceQueue = DispatchQueue(label: "com.GameStore.download.persistence")
    private static let completedSourcesKey = "zonoe.downloadCompletedSources.v1"

    private static func completedSources() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: completedSourcesKey) as? [String: String] ?? [:]
    }

    private static func updateCompletedSource(filename: String, source: URL?) {
        // Keep metadata mutations on main to avoid lost read-modify-write updates.
        precondition(Thread.isMainThread)
        var entries = completedSources()
        if let source = source {
            entries[filename] = source.absoluteString
        } else {
            entries.removeValue(forKey: filename)
        }
        UserDefaults.standard.set(entries, forKey: completedSourcesKey)
    }

    private static func pruneCompletedSources(existingFilenames: Set<String>) {
        precondition(Thread.isMainThread)
        var entries = completedSources()
        let before = entries.count
        entries = entries.filter { existingFilenames.contains($0.key) }
        if entries.count != before {
            UserDefaults.standard.set(entries, forKey: completedSourcesKey)
        }
    }

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
        // Snapshot on main, encode and atomically write on a serial IO queue.
        persistenceQueue.async {
            do {
                let destination = Self.pauseArchiveURL
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                try JSONEncoder().encode(records).write(to: destination, options: .atomic)
            } catch {
                NSLog("DownloadCenter: could not persist pause data: %@", String(describing: error))
            }
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
        guard let current = activeItems.first(where: { $0.id == item.id }),
              current.state == .downloading,
              let identifier = current.taskIdentifier,
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
                    guard self.pausingTaskIDs.remove(identifier) != nil else { return }
                    guard self.activeItems.contains(where: { $0.taskIdentifier == identifier }) else { return }
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
        resumedTaskIDs.insert(task.taskIdentifier)
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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.cancel(item) }
            return
        }
        guard let current = activeItems.first(where: { $0.id == item.id }),
              let taskIdentifier = current.taskIdentifier,
              !pausingTaskIDs.contains(taskIdentifier) else { return }

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
        precondition(Thread.isMainThread, "DownloadCenter mutations must run on main")
        guard item.state == .completed,
              let localURL = item.localURL,
              completedItems.contains(where: { $0.id == item.id && $0.localURL == localURL }),
              localURL.deletingLastPathComponent().standardizedFileURL == Self.downloadsDirectory().standardizedFileURL else {
            return
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }

        Self.updateCompletedSource(filename: localURL.lastPathComponent, source: nil)
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
            .filter { url in
                guard url.pathExtension.lowercased() == "ipa",
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
                    return false
                }
                return values.isRegularFile == true
            }
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
                // Check current filesystem state before pruning: a download may
                // have finished after the directory snapshot was enumerated.
                let folder = Self.downloadsDirectory()
                let validFiles = Set(Self.completedSources().keys.filter { name in
                    let candidate = folder.appendingPathComponent(name)
                    return FileManager.default.fileExists(atPath: candidate.path)
                })
                Self.pruneCompletedSources(existingFilenames: validFiles)
                let sourceMap = Self.completedSources()
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

                    let original = sourceMap[fileURL.lastPathComponent]
                        .flatMap(URL.init(string:)) ?? fileURL
                    return Item(
                        id: UUID(),
                        sourceURL: original,
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
            guard !self.pausingTaskIDs.contains(downloadTask.taskIdentifier) else { return }
            self.updateActiveItem(taskIdentifier: downloadTask.taskIdentifier) {
                guard $0.state == .downloading else { return }
                $0.progress = progress
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
            let originalSource = downloadTask.originalRequest?.url
            DispatchQueue.main.async {
                // Publish the source map and the completed item in one main-queue
                // transition. Do not let a stale callback overwrite a newer task.
                guard self.activeItems.contains(where: { $0.taskIdentifier == taskIdentifier }) else {
                    return
                }
                Self.updateCompletedSource(
                    filename: destination.lastPathComponent,
                    source: originalSource
                )
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
            if self.resumedTaskIDs.remove(task.taskIdentifier) != nil,
               (error as NSError).code != NSURLErrorCancelled,
               let index = self.activeItems.firstIndex(where: { $0.taskIdentifier == task.taskIdentifier }) {
                // The saved resume metadata can become invalid after a relaunch
                // or server-side resource change. Retry once from byte zero.
                let old = self.activeItems[index]
                let fresh = self.session.downloadTask(with: old.sourceURL)
                self.activeItems[index].taskIdentifier = fresh.taskIdentifier
                self.activeItems[index].progress = 0
                self.activeItems[index].state = .downloading
                fresh.resume()
                return
            }
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

        resumedTaskIDs.remove(taskIdentifier)
        pausingTaskIDs.remove(taskIdentifier)
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
