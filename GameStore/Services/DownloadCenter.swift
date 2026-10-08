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

            try Self.validateIPA(at: location)
            let destination = try Self.importDestination(for: downloadTask.originalRequest?.url)
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

    private static func validateIPA(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
            throw DownloadCenterError.emptyFile
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let signature = handle.readData(ofLength: 4)
        let bytes = [UInt8](signature)

        guard bytes.count >= 4,
              bytes[0] == 0x50,
              bytes[1] == 0x4B,
              (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07),
              (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08) else {
            throw DownloadCenterError.invalidIPA
        }
    }

    private static func importDestination(for sourceURL: URL?) throws -> URL {
        let fileManager = FileManager.default
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("ImportedApps", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var fileName = sourceURL?.lastPathComponent ?? "download.ipa"
        if fileName.isEmpty {
            fileName = "download.ipa"
        }
        fileName = fileName.replacingOccurrences(of: "/", with: "_")
        if !fileName.lowercased().hasSuffix(".ipa") {
            fileName += ".ipa"
        }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var destination = directory.appendingPathComponent(fileName)
        var suffix = 2

        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base)-\(suffix).\(ext)")
            suffix += 1
        }

        return destination
    }
}

enum DownloadCenterError: LocalizedError {
    case httpStatus(Int)
    case emptyFile
    case invalidIPA

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "下载服务器返回 HTTP \(code)"
        case .emptyFile:
            return "下载文件为空"
        case .invalidIPA:
            return "下载内容不是有效的 IPA/ZIP 文件"
        }
    }
}
