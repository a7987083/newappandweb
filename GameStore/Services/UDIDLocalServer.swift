import Foundation
import Darwin

final class UDIDLocalServer {
    enum ServerError: Error {
        case socketCreationFailed
        case bindFailed
        case listenFailed
    }

    static let port: UInt16 = 14302

    private let queue = DispatchQueue(label: "com.GameStore.udid.local-server")
    private var socketFD: Int32 = -1
    private var isRunning = false
    private let profileData: Data
    private let onUDID: (String) -> Void

    init(profileData: Data, onUDID: @escaping (String) -> Void) {
        self.profileData = profileData
        self.onUDID = onUDID
    }

    deinit {
        stop()
    }

    func start() throws {
        guard !isRunning else { return }

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketCreationFailed }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Self.port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            Darwin.close(fd)
            throw ServerError.bindFailed
        }

        guard Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            throw ServerError.listenFailed
        }

        socketFD = fd
        isRunning = true

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        let fd = socketFD
        socketFD = -1
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    private func acceptLoop() {
        while isRunning {
            var clientAddress = sockaddr_storage()
            var clientLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(socketFD, $0, &clientLength)
                }
            }

            guard clientFD >= 0 else {
                if isRunning { continue }
                break
            }

            handleClient(clientFD)
            Darwin.shutdown(clientFD, SHUT_RDWR)
            Darwin.close(clientFD)
        }
    }

    private func handleClient(_ clientFD: Int32) {
        guard let request = readRequest(from: clientFD) else {
            send(status: "400 Bad Request", headers: [:], body: Data(), to: clientFD)
            return
        }

        if request.method == "GET", request.path == "/profile.mobileconfig" {
            send(
                status: "200 OK",
                headers: [
                    "Content-Type": "application/x-apple-aspen-config",
                    "Cache-Control": "no-store"
                ],
                body: profileData,
                to: clientFD
            )
            return
        }

        if request.method == "POST", request.path == "/udid" {
            guard let udid = extractUDID(from: request.body), !udid.isEmpty else {
                send(status: "400 Bad Request", headers: [:], body: Data(), to: clientFD)
                return
            }

            DispatchQueue.main.async { [onUDID] in
                onUDID(udid)
            }

            var callback = URLComponents()
            callback.scheme = "gamestore"
            callback.host = "udid-complete"
            callback.queryItems = [URLQueryItem(name: "udid", value: udid)]

            guard let location = callback.url?.absoluteString else {
                send(status: "500 Internal Server Error", headers: [:], body: Data(), to: clientFD)
                return
            }

            send(
                status: "301 Moved Permanently",
                headers: ["Location": location],
                body: Data(),
                to: clientFD
            )
            return
        }

        send(status: "404 Not Found", headers: [:], body: Data(), to: clientFD)
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let body: Data
    }

    private func readRequest(from fd: Int32) -> HTTPRequest? {
        let maxBodySize = 2 * 1024 * 1024
        var data = Data()
        var expectedTotalLength: Int?
        var buffer = [UInt8](repeating: 0, count: 8192)

        while data.count <= maxBodySize + 64 * 1024 {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            data.append(buffer, count: count)

            if expectedTotalLength == nil,
               let headerRange = data.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = data[..<headerRange.lowerBound]
                guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
                let contentLength = headerText
                    .components(separatedBy: "\r\n")
                    .first(where: { $0.lowercased().hasPrefix("content-length:") })
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0

                guard contentLength <= maxBodySize else { return nil }
                expectedTotalLength = headerRange.upperBound + contentLength
            }

            if let expected = expectedTotalLength, data.count >= expected {
                break
            }
        }

        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0]).uppercased()
        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath

        let contentLength = lines
            .first(where: { $0.lowercased().hasPrefix("content-length:") })
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0

        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))

        return HTTPRequest(method: method, path: path, body: body)
    }

    private func send(status: String, headers: [String: String], body: Data, to fd: Int32) {
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = "close"

        var text = "HTTP/1.1 \(status)\r\n"
        for (name, value) in allHeaders {
            text += "\(name): \(value)\r\n"
        }
        text += "\r\n"

        var response = Data(text.utf8)
        response.append(body)

        response.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < response.count {
                let result = Darwin.send(fd, base.advanced(by: sent), response.count - sent, 0)
                if result <= 0 { break }
                sent += result
            }
        }
    }

    private func extractUDID(from input: Data) -> String? {
        let plistData: Data

        if let start = input.range(of: Data("<?xml".utf8)),
           let end = input.range(of: Data("</plist>".utf8), options: [], in: start.lowerBound..<input.endIndex) {
            plistData = input.subdata(in: start.lowerBound..<end.upperBound)
        } else {
            plistData = input
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) else {
            return nil
        }

        return findUDID(in: plist)
    }

    private func findUDID(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if key.caseInsensitiveCompare("UDID") == .orderedSame,
                   let string = child as? String,
                   !string.isEmpty {
                    return string
                }
                if let nested = findUDID(in: child) { return nested }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let nested = findUDID(in: child) { return nested }
            }
        }

        return nil
    }
}
