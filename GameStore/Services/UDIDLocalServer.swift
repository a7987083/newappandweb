import Foundation
import Darwin

/// A single Profile Service transaction on loopback, bound to a fresh session.
/// No persisted server state; the coordinator owns its lifetime.
final class UDIDLocalServer {
    static let port: UInt16 = 14302

    enum ServerError: LocalizedError {
        case socket, occupied, listen
        var errorDescription: String? {
            switch self {
            case .socket: return "本机 UDID 服务无法创建套接字"
            case .occupied: return "14302 端口已被占用。请关闭其他正在提供 UDID 服务的应用后重试"
            case .listen: return "本机 UDID 服务无法启动监听"
            }
        }
    }

    private let profileData: Data
    private let token: String
    private let receive: (String) -> Void
    private let queue = DispatchQueue(label: "zonoe.udid.profile.listener", qos: .userInitiated)
    private let state = NSLock()
    private var listener: Int32 = -1

    init(profileData: Data, sessionToken: String, onUDID: @escaping (String) -> Void) {
        self.profileData = profileData
        self.token = sessionToken
        self.receive = onUDID
    }

    deinit { stop() }

    func start() throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socket }
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Self.port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { Darwin.close(fd); throw ServerError.occupied }
        guard Darwin.listen(fd, 8) == 0 else { Darwin.close(fd); throw ServerError.listen }
        state.lock()
        listener = fd
        state.unlock()
        queue.async { [weak self] in self?.serve(fd) }
    }

    func stop() {
        state.lock()
        let fd = listener
        listener = -1
        state.unlock()
        if fd >= 0 {
            _ = Darwin.shutdown(fd, SHUT_RDWR)
            _ = Darwin.close(fd)
        }
    }

    private func serve(_ fd: Int32) {
        while true {
            state.lock()
            let active = listener == fd
            state.unlock()
            guard active else { return }
            var address = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let client = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(fd, $0, &length)
                }
            }
            if client < 0 { return }
            var timeout = timeval(tv_sec: 10, tv_usec: 0)
            _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            handle(client)
            _ = Darwin.shutdown(client, SHUT_RDWR)
            _ = Darwin.close(client)
        }
    }

    private func handle(_ fd: Int32) {
        guard let request = read(fd) else {
            reply(fd, "400 Bad Request", [:], Data())
            return
        }
        if request.method == "GET" && request.path == "/profile.mobileconfig" {
            reply(fd, "200 OK", [
                "Content-Type": "application/x-apple-aspen-config",
                "Cache-Control": "no-store"
            ], profileData)
            return
        }
        guard request.method == "POST" && request.path == "/udid" else {
            reply(fd, "404 Not Found", [:], Data())
            return
        }
        guard request.session == token else {
            reply(fd, "403 Forbidden", [:], Data())
            return
        }
        guard let udid = Self.parseUDID(request.body) else {
            reply(fd, "400 Bad Request", [:], Data())
            return
        }
        DispatchQueue.main.async { [receive] in receive(udid) }
        var callback = URLComponents()
        callback.scheme = "zonoe"
        callback.host = "udid-complete"
        callback.queryItems = [
            URLQueryItem(name: "udid", value: udid),
            URLQueryItem(name: "session", value: token)
        ]
        guard let location = callback.url?.absoluteString else {
            reply(fd, "500 Internal Server Error", [:], Data())
            return
        }
        reply(fd, "301 Moved Permanently", ["Location": location, "Cache-Control": "no-store"], Data())
    }

    private struct Request {
        let method: String
        let path: String
        let session: String?
        let body: Data
    }

    private func read(_ fd: Int32) -> Request? {
        let maxHeader = 32 * 1024
        let maxBody = 1024 * 1024
        let separator = Data("\r\n\r\n".utf8)
        var accumulated = Data()
        var expected: Int?
        var bytes = [UInt8](repeating: 0, count: 8192)

        while accumulated.count <= maxHeader + maxBody {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.recv(fd, buffer.baseAddress, buffer.count, 0)
            }
            guard count > 0 else { return nil }
            accumulated.append(contentsOf: bytes.prefix(count))
            if expected == nil, let range = accumulated.range(of: separator) {
                guard range.lowerBound <= maxHeader,
                      let headers = String(data: accumulated[..<range.lowerBound], encoding: .utf8)
                else { return nil }
                let lengthValue = headers.components(separatedBy: "\r\n")
                    .first(where: { $0.lowercased().hasPrefix("content-length:") })
                    .flatMap { $0.split(separator: ":", maxSplits: 1).last }
                    .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
                guard lengthValue >= 0 && lengthValue <= maxBody else { return nil }
                expected = range.upperBound + lengthValue
            }
            if let expected = expected, accumulated.count >= expected { break }
            if expected == nil && accumulated.count > maxHeader { return nil }
        }
        guard let range = accumulated.range(of: separator),
              let headers = String(data: accumulated[..<range.lowerBound], encoding: .utf8),
              let line = headers.components(separatedBy: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let route = String(parts[1])
        let comps = URLComponents(string: "http://127.0.0.1" + route)
        let lengthValue = headers.components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("content-length:") })
            .flatMap { $0.split(separator: ":", maxSplits: 1).last }
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        guard lengthValue >= 0, lengthValue <= maxBody,
              accumulated.count >= range.upperBound + lengthValue else { return nil }
        return Request(
            method: String(parts[0]).uppercased(),
            path: comps?.path ?? "",
            session: comps?.queryItems?.first(where: { $0.name == "session" })?.value,
            body: accumulated.subdata(in: range.upperBound..<(range.upperBound + lengthValue))
        )
    }

    private func reply(_ fd: Int32, _ status: String, _ headers: [String: String], _ body: Data) {
        var text = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (key, value) in headers { text += "\(key): \(value)\r\n" }
        var data = Data((text + "\r\n").utf8)
        data.append(body)
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.send(fd, base.advanced(by: offset), buffer.count - offset, 0)
                if n <= 0 { return }
                offset += n
            }
        }
    }

    private static func parseUDID(_ data: Data) -> String? {
        let body: Data
        if let start = data.range(of: Data("<?xml".utf8)),
           let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) {
            body = data.subdata(in: start.lowerBound..<end.upperBound)
        } else {
            body = data
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: body, options: [], format: nil) else { return nil }
        return searchUDID(plist)
    }

    private static func searchUDID(_ value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let entry = dict.first(where: { $0.key.lowercased() == "udid" })?.value as? String,
               !entry.isEmpty { return entry }
            for child in dict.values {
                if let found = searchUDID(child) { return found }
            }
        }
        if let list = value as? [Any] {
            for child in list {
                if let found = searchUDID(child) { return found }
            }
        }
        return nil
    }
}
