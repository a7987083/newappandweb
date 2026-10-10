import Foundation
import UIKit
import Darwin

enum IPAInstallMode: String, CaseIterable {
    case local = "本地 OTA"
    case network = "网络安装"
}

/// Keeps the signed IPA on-device. Never uploads package bytes to the manifest service.
final class IPAInstallCoordinator {
    static let shared = IPAInstallCoordinator()
    private var server: IPAInstallFileServer?
    private init() {}

    func begin(artifact: SignedArtifact, mode: IPAInstallMode, completion: @escaping (Result<Bool, Error>) -> Void) {
        do {
            server?.stop()
            let local = try IPAInstallFileServer(ipa: artifact.ipaURL, identifier: artifact.bundleIdentifier,
                                                 name: artifact.displayName, version: artifact.version)
            try local.start()
            server = local
            let manifest: URL
            if mode == .local {
                manifest = local.manifestURL
                open(manifest, completion: completion)
            } else {
                // The external server supplies only a HTTPS manifest. It must never fetch/store the IPA itself.
                var url = URLComponents(string: "https://app3.zonoeios.xyz/ipa-install/manifest.php")!
                url.queryItems = [
                    URLQueryItem(name: "fetchurl", value: local.ipaURL.absoluteString),
                    URLQueryItem(name: "bundleid", value: artifact.bundleIdentifier),
                    URLQueryItem(name: "name", value: artifact.displayName),
                    URLQueryItem(name: "version", value: artifact.version)
                ]
                guard let value = url.url else { throw NSError(domain: "IPAInstall", code: 1, userInfo: [NSLocalizedDescriptionKey: "安装地址无效"]) }
                manifest = value
                // Verify deployed manifest service before asking iOS to open it.
                URLSession.shared.dataTask(with: manifest) { data, response, error in
                    guard error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200,
                          let data = data,
                          (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil else {
                        DispatchQueue.main.async {
                            completion(.failure(error ?? NSError(domain: "IPAInstall", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "网络安装清单不可用，请先部署服务器端 manifest.php"])))
                        }
                        return
                    }
                    self.open(manifest, completion: completion)
                }.resume()
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func open(_ manifest: URL, completion: @escaping (Result<Bool, Error>) -> Void) {
        OTAInstallService.install(manifestURL: manifest) { accepted in
            completion(.success(accepted)) // URL accepted is NOT proof that installation completed.
        }
    }
}

final class IPAInstallFileServer {
    private let ipa: URL
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let manifest: Data
    private let queue = DispatchQueue(label: "gamestore.ipa.install.server", qos: .utility)
    private let lock = NSLock()
    private var socketFD: Int32 = -1
    private var port: UInt16 = 0
    private let identifier: String
    private let name: String
    private let version: String

    init(ipa: URL, identifier: String, name: String, version: String) throws {
        guard FileManager.default.fileExists(atPath: ipa.path) else { throw NSError(domain: "IPAInstall", code: 3, userInfo: [NSLocalizedDescriptionKey: "签名后的 IPA 不存在"]) }
        self.ipa = ipa
        self.identifier = identifier
        self.name = name
        self.version = version
        self.manifest = Data()
    }

    var ipaURL: URL { URL(string: "http://127.0.0.1:\(port)/\(token).ipa")! }
    var manifestURL: URL { URL(string: "http://127.0.0.1:\(port)/\(token).plist")! }

    func start() throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: "IPAInstall", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法启动安装服务"]) }
        var opt: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw NSError(domain: "IPAInstall", code: 5, userInfo: [NSLocalizedDescriptionKey: "安装服务端口不可用"])
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafeMutablePointer(to: &addr, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(fd, $0, &length) } }) == 0 else {
            Darwin.close(fd)
            throw NSError(domain: "IPAInstall", code: 6)
        }
        port = UInt16(bigEndian: addr.sin_port)
        lock.lock(); socketFD = fd; lock.unlock()
        queue.async { [weak self] in self?.serve(fd) }
    }

    func stop() {
        lock.lock(); let fd = socketFD; socketFD = -1; lock.unlock()
        if fd >= 0 { _ = Darwin.shutdown(fd, SHUT_RDWR); _ = Darwin.close(fd) }
    }
    deinit { stop() }

    private func serve(_ fd: Int32) {
        while true {
            lock.lock(); let active = socketFD == fd; lock.unlock()
            if !active { return }
            var addr = sockaddr_storage()
            var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let client = withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.accept(fd, $0, &len) }
            }
            if client < 0 { return }
            var timeout = timeval(tv_sec: 20, tv_usec: 0)
            _ = setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            handle(client)
            _ = Darwin.shutdown(client, SHUT_RDWR); _ = Darwin.close(client)
        }
    }

    private func handle(_ fd: Int32) {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let size = bytes.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, $0.count, 0) }
        guard size > 0, let request = String(bytes: bytes.prefix(size), encoding: .utf8),
              let first = request.components(separatedBy: "\r\n").first else { return }
        let path = first.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let isHead = first.hasPrefix("HEAD ")
        guard first.hasPrefix("GET ") || isHead else { send(fd, Data(), status: "405 Method Not Allowed", type: "text/plain"); return }
        if path == "/\(token).plist" {
            let payload: [String: Any] = [
                "items": [[
                    "assets": [["kind": "software-package", "url": ipaURL.absoluteString]],
                    "metadata": ["bundle-identifier": identifier, "bundle-version": version,
                                 "kind": "software", "title": name]
                ]]
            ]
            let data = (try? PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)) ?? Data()
            send(fd, isHead ? Data() : data, type: "application/xml", declaredLength: data.count)
        } else if path == "/\(token).ipa" {
            guard let input = InputStream(url: ipa) else { send(fd, Data(), status: "404 Not Found", type: "text/plain"); return }
            let count = (try? FileManager.default.attributesOfItem(atPath: ipa.path)[.size] as? NSNumber)?.intValue ?? 0
            sendHeader(fd, status: "200 OK", type: "application/octet-stream", length: count)
            guard !isHead else { return }
            input.open(); defer { input.close() }
            var buf = [UInt8](repeating: 0, count: 65536)
            while input.hasBytesAvailable {
                let n = input.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                if !writeAll(fd, Array(buf.prefix(n))) { break }
            }
        } else {
            send(fd, Data(), status: "404 Not Found", type: "text/plain")
        }
    }

    private func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        return bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let n = Darwin.send(fd, base.advanced(by: offset), raw.count - offset, 0)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }

    private func sendHeader(_ fd: Int32, status: String, type: String, length: Int) {
        let h = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(length)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        _ = writeAll(fd, Array(h.utf8))
    }
    private func send(_ fd: Int32, _ data: Data, status: String = "200 OK", type: String, declaredLength: Int? = nil) {
        sendHeader(fd, status: status, type: type, length: declaredLength ?? data.count)
        _ = writeAll(fd, Array(data))
    }
}

struct OTAInstallService {
    static func install(manifestURL: URL, completion: @escaping (Bool) -> Void) {
        var components = URLComponents(string: "itms-services://")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: manifestURL.absoluteString)
        ]
        guard let url = components.url else { completion(false); return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: completion)
        }
    }
}
