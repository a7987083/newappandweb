import Foundation
import Security

enum QNQSourcePayloadDecoder {
    static func decode(
        _ data: Data,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let outerObject: Any
        do {
            outerObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            completion(.failure(SourceDecodeError("软件源外层 JSON 无效：\(error.localizedDescription)")))
            return
        }

        if let root = outerObject as? [String: Any],
           let payload = root["appstore_v2"] as? String {
            do {
                completion(.success(try decodeAppstoreV2(payload)))
            } catch {
                completion(.failure(error))
            }
            return
        }

        if let root = outerObject as? [String: Any],
           let payload = root["appstore"] as? String {
            decodeLegacyAppstore(payload, completion: completion)
            return
        }

        completion(.success(data))
    }

    private static func decodeLegacyAppstore(
        _ payload: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let encrypted: Data
        do {
            encrypted = try Base64Codec.decode(payload)
        } catch {
            completion(.failure(error))
            return
        }

        NuosikeLegacyKeyProvider.loadBKey { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let keyResult):
                do {
                    let jsonData = try RC4.decrypt(encrypted, keyText: keyResult.bkey)
                    guard String(data: jsonData, encoding: .utf8) != nil else {
                        throw SourceDecodeError("Legacy RC4 plaintext is not UTF-8")
                    }
                    _ = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed])
                    completion(.success(jsonData))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private static func decodeAppstoreV2(_ payload: String) throws -> Data {
        let raw = try NuosikeAppstoreV2Decoder.decodeCodec(payload)
        let container = try NuosikeAppstoreV2Decoder.parseContainer(raw)
        let keyData = try RSAKeySupport.decrypt(
            container.rsaBlob,
            privateKeyDER: try EmbeddedV2Key.privateKeyDER()
        )
        guard let keyText = String(data: keyData, encoding: .utf8) else {
            throw SourceDecodeError("RSA plaintext is not UTF-8 RC4 key text")
        }

        let jsonData = try RC4.decrypt(container.payload, keyText: keyText)
        guard String(data: jsonData, encoding: .utf8) != nil else {
            throw SourceDecodeError("V2 RC4 plaintext is not UTF-8")
        }
        _ = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed])
        return jsonData
    }
}

private struct HTTPPayload {
    let data: Data
    let status: Int
    let contentType: String?
}

private enum HTTPClient {
    static func get(
        _ url: URL,
        completion: @escaping (Result<HTTPPayload, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("QNQSourceLab/0.7.2", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(SourceDecodeError("非 HTTP 响应: \(url.absoluteString)")))
                return
            }
            completion(.success(HTTPPayload(
                data: data ?? Data(),
                status: http.statusCode,
                contentType: http.value(forHTTPHeaderField: "Content-Type")
            )))
        }.resume()
    }
}

private struct LegacyKeyResult {
    let bkey: String
}

private enum NuosikeLegacyKeyProvider {
    private static let updateURL = URL(string: "https://api.nuosike.com/update.json")!
    private static let keyURL = URL(string: "https://api.nuosike.com/key.json")!

    static func loadBKey(
        completion: @escaping (Result<LegacyKeyResult, Error>) -> Void
    ) {
        HTTPClient.get(updateURL) { updateResult in
            switch updateResult {
            case .failure(let error):
                completion(.failure(error))
            case .success(let update):
                do {
                    guard (200...299).contains(update.status) else {
                        throw SourceDecodeError("update.json HTTP \(update.status)")
                    }
                    let updateRoot = try dictionary(update.data, label: "update.json")
                    guard let encodedAKey = updateRoot["rule"] as? String else {
                        throw SourceDecodeError("update.json missing rule")
                    }
                    let akeyData = try Base64Codec.decode(encodedAKey)
                    guard let akey = String(data: akeyData, encoding: .utf8),
                          akey.contains("BEGIN"),
                          akey.contains("PRIVATE KEY") else {
                        throw SourceDecodeError("update.json rule Base64 is not RSA private-key PEM")
                    }
                    _ = try RSAKeySupport.privateKeyDER(fromPEM: akey)

                    HTTPClient.get(keyURL) { keyResult in
                        switch keyResult {
                        case .failure(let error):
                            completion(.failure(error))
                        case .success(let keyResponse):
                            do {
                                guard (200...299).contains(keyResponse.status) else {
                                    throw SourceDecodeError("key.json HTTP \(keyResponse.status)")
                                }
                                let keyRoot = try dictionary(keyResponse.data, label: "key.json")
                                guard let encodedRule = keyRoot["rule"] as? String else {
                                    throw SourceDecodeError("key.json missing rule")
                                }
                                let rsaCiphertext = try Base64Codec.decode(encodedRule)
                                let bkeyData = try RSAKeySupport.decrypt(
                                    rsaCiphertext,
                                    privateKeyPEM: Data(akey.utf8)
                                )
                                guard let bkey = String(data: bkeyData, encoding: .utf8),
                                      !bkey.isEmpty else {
                                    throw SourceDecodeError("key.json RSA plaintext is not a non-empty UTF-8 bkey")
                                }
                                completion(.success(LegacyKeyResult(bkey: bkey)))
                            } catch {
                                completion(.failure(error))
                            }
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private static func dictionary(_ data: Data, label: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let root = object as? [String: Any] else {
            throw SourceDecodeError("\(label) top-level is not object")
        }
        return root
    }
}

private enum Base64Codec {
    static func decode(_ value: String) throws -> Data {
        let compact = value.components(separatedBy: .whitespacesAndNewlines).joined()
        if let data = Data(base64Encoded: compact, options: [.ignoreUnknownCharacters]) {
            return data
        }

        var padded = compact
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder != 0 {
            padded += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: padded, options: [.ignoreUnknownCharacters]) else {
            throw SourceDecodeError("invalid Base64")
        }
        return data
    }
}

private enum RC4 {
    static func decrypt(_ data: Data, keyText: String) throws -> Data {
        let key = keyText.utf16.map { UInt8(truncatingIfNeeded: $0) }
        guard !key.isEmpty else {
            throw SourceDecodeError("empty RC4 key")
        }

        var state = Array(0...255).map(UInt8.init)
        var j = 0
        for i in 0..<256 {
            j = (j + Int(state[i]) + Int(key[i % key.count])) & 0xff
            state.swapAt(i, j)
        }

        var i = 0
        j = 0
        var output = Data(capacity: data.count)
        for byte in data {
            i = (i + 1) & 0xff
            j = (j + Int(state[i])) & 0xff
            state.swapAt(i, j)
            let k = state[(Int(state[i]) + Int(state[j])) & 0xff]
            output.append(byte ^ k)
        }
        return output
    }
}

private struct V2Container {
    let magic: UInt32
    let rsaBlob: Data
    let payload: Data
    let trailingCount: Int
}

private enum NuosikeAppstoreV2Decoder {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)
    private static let magic: UInt32 = 0xFEEDFACF

    static func decodeCodec(_ text: String) throws -> Data {
        var lookup = [Int](repeating: -1, count: 256)
        for (index, byte) in alphabet.enumerated() {
            lookup[Int(byte)] = index
        }

        var output = Data()
        output.reserveCapacity(text.utf8.count * 3 / 4 + 8)
        var accumulator: UInt64 = 0
        var bitCount = 0

        for (position, byte) in text.utf8.enumerated() {
            let value = byte < 128 ? lookup[Int(byte)] : -1
            guard value >= 0 else {
                throw SourceDecodeError("invalid codec character at index \(position)")
            }

            let width = (value == 30 || value == 31) ? 5 : 6
            accumulator |= UInt64(value & ((1 << width) - 1)) << UInt64(bitCount)
            bitCount += width

            while bitCount >= 8 {
                output.append(UInt8(accumulator & 0xff))
                accumulator >>= 8
                bitCount -= 8
            }
        }

        if bitCount > 0 {
            output.append(UInt8(accumulator & 0xff))
        }
        return output
    }

    static func parseContainer(_ raw: Data) throws -> V2Container {
        guard raw.count >= 12 else {
            throw SourceDecodeError("container too short: \(raw.count)")
        }

        let containerMagic = try u32LE(raw, 0)
        guard containerMagic == magic else {
            throw SourceDecodeError(
                "unexpected magic: 0x\(String(containerMagic, radix: 16)); expected 0xfeedfacf"
            )
        }

        let rsaLength = Int(try u32LE(raw, 4))
        guard rsaLength > 0 else {
            throw SourceDecodeError("invalid RSA blob length: \(rsaLength)")
        }

        let rsaStart = 8
        let rsaEnd = rsaStart + rsaLength
        guard rsaEnd + 4 <= raw.count else {
            throw SourceDecodeError("RSA blob out of bounds: L1=\(rsaLength), decoded=\(raw.count)")
        }

        let payloadLength = Int(try u32LE(raw, rsaEnd))
        let payloadStart = rsaEnd + 4
        let payloadEnd = payloadStart + payloadLength
        guard payloadEnd <= raw.count else {
            throw SourceDecodeError(
                "payload out of bounds: L2=\(payloadLength), remaining=\(raw.count - payloadStart)"
            )
        }

        return V2Container(
            magic: containerMagic,
            rsaBlob: raw.subdata(in: rsaStart..<rsaEnd),
            payload: raw.subdata(in: payloadStart..<payloadEnd),
            trailingCount: raw.count - payloadEnd
        )
    }

    private static func u32LE(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw SourceDecodeError("u32 out of bounds @\(offset)")
        }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

private enum EmbeddedV2Key {
    private static let privateKeyPKCS1Base64 = """
    MIIEowIBAAKCAQEAvgJlkLVTXIrgaUrHYshPUe4PjQRAaU/uwYxbTBw0HzYdF5YymH9vnvcFowTy
    byFHqc5Xe38PBcqZfavp5o0S47R8YSt1Rg7tuI9oW8KWGp0nXJz7hszcyDqtBKquzur1gaigKywN
    uHvRNkLvb76AEPkRKKa7iE7pDeRNNAZpssHO4GMhxXsR0vifXhG6vrFeJUX1Wioky8h7ckPH0Nlo
    MgNxxiVEgjNfefmpAYsOBeR3fWAYx7uM4trWr98fdqvXDhG+gNV9oI/9cF4sUDqmkcW1WSOw1R1a
    sndkDYrdCqCT+xJWeKzLj+TowlP8dnV9KrEoKJ0kBk3zCMkoIjjpMQIDAQABAoIBAA7fLibk4ljw
    b78eALwdFIRDn0j4x7fWb0gL3ct3u6ajvCQv99bSxqBJElJfnUAQeUTzpwo9+CWKZXgeIAkRCqTy
    5/dNCPlKStXyt4bTFJ+RpFaN3OwAldlAKnGekF8Wqc+TrLGkWZCSdF4MYCQ9Y1WwwOSPJEd3catK
    Lra/N7+rZCi1VNKS/EGuwBfco6S9sTnkza1xJ0c31tpz7gocSlmOA0yR3/ZlYmGtFDOdXtVMfs+q
    oBnV1VnYQSVUdildRPPgL+mQidstKOz30RCg7/df1afiXO5OQQ1tuR+mXNhfG/MsqiYzz6q4Koeg
    aatUpYNChGR8GpP65Kt9kze6uk8CgYEA2vbLFYt9a90HzEbV5HqKWZOPUAbjeEXMRZQMZAZOLVom
    G1QYL9bRS2O4zN1NVCALRxvCtUbb0vFfuGXjPZ2NWK1aSCgTH09eJp9M3nb85LXPcuJPIDXBi00Q
    gqGWv4JcKseeGtZZif5cGXrAPBzTVdJeSSv8ctE5F3a5rdOJuyMCgYEA3iXbi8UEeBZhU7iykQAv
    zZ3qEmK7GM3Ly/MwNBpHiE6mq+ICeUtRq4clV5PuJsMr2ugkswIDOeWfZsZ4+bzM1E+kLwQ39Ec2
    YCfLaDo2ERi78Pq8EdMHTI4DQ0WAJ+BbJxWg7w7NCWVsswrXvEVBZByobf8SxwNAGFBLlLF0KZsC
    gYAd6aMawWCT8LEVBgRIXzkxPYhRfW9rydU7GBuNOpNJfMxB5X4cYvNaojfnvL/Io0wHHdK+ovx6
    18Ck1z5w92oM2DnCK79ZAqWxDwgYSBcKQ5AgeKwokU9scU21GtAWP3/J1FVUAz5eLKJ2VJ+YVrPE
    QKXixyCIqu5qtyxsg76IEwKBgQDLjIC4dxP7PPZ9EhV8S2GB1BowMosg1SDRhck7VIEK4pZRlEuT
    /HGe67xJnOBwYBEFCgTmiQePu1jtgRpEKry8JSVZd1IV4FJwlMYKgJwd2j4LNpOw+V4MxWsz7rDY
    2PhsvaKyqSsyWt7YxyyZ9BNQufmSoFACTnYiUSCP5HF91QKBgA3XKDAiVfJFxTuMkSm6a+iEOP1I
    IGXehiH73URUwiRJ213lqF3NiL9a7R12AbpWlfeNkt+WjAP0IzdJ1PMAH/E7xRi6p4zmCFnePi3T
    UPrFO9bZ6p2XDS5jJQnNJuA/9cVKvnjYRv6emsg9Xgwojb9wW5iPRYPTP8jUrIi9/ZXF
    """

    static func privateKeyDER() throws -> Data {
        let compact = privateKeyPKCS1Base64
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard let data = Data(base64Encoded: compact), data.count == 1191 else {
            throw SourceDecodeError("embedded appstore_v2 private key is invalid")
        }
        return data
    }
}

private enum RSAKeySupport {
    static func decrypt(_ ciphertext: Data, privateKeyPEM: Data) throws -> Data {
        guard let pem = String(data: privateKeyPEM, encoding: .utf8) else {
            throw SourceDecodeError("private key PEM is not UTF-8")
        }
        return try decrypt(ciphertext, privateKeyDER: privateKeyDER(fromPEM: pem))
    }

    static func decrypt(_ ciphertext: Data, privateKeyDER: Data) throws -> Data {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 2048
        ]

        var createError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(
            privateKeyDER as CFData,
            attributes as CFDictionary,
            &createError
        ) else {
            let message = createError?.takeRetainedValue().localizedDescription
                ?? "unknown SecKeyCreateWithData error"
            throw SourceDecodeError("RSA private key import failed: \(message)")
        }

        let blockSize = SecKeyGetBlockSize(key)
        guard blockSize > 0,
              ciphertext.count > 0,
              ciphertext.count % blockSize == 0 else {
            throw SourceDecodeError(
                "RSA ciphertext length \(ciphertext.count) is not a multiple of RSA_size \(blockSize)"
            )
        }

        var output = Data()
        for offset in stride(from: 0, to: ciphertext.count, by: blockSize) {
            let block = ciphertext.subdata(in: offset..<(offset + blockSize))
            var decryptError: Unmanaged<CFError>?
            guard let plain = SecKeyCreateDecryptedData(
                key,
                .rsaEncryptionPKCS1,
                block as CFData,
                &decryptError
            ) as Data? else {
                let message = decryptError?.takeRetainedValue().localizedDescription
                    ?? "unknown RSA decrypt error"
                throw SourceDecodeError(
                    "RSA PKCS#1 v1.5 decrypt failed at block \(offset / blockSize): \(message)"
                )
            }
            output.append(plain)
        }
        return output
    }

    static func privateKeyDER(fromPEM pem: String) throws -> Data {
        let body = pem.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
            .joined()

        guard let der = Data(base64Encoded: body, options: [.ignoreUnknownCharacters]) else {
            throw SourceDecodeError("invalid private-key PEM Base64")
        }

        if pem.contains("BEGIN RSA PRIVATE KEY") {
            return der
        }

        if pem.contains("BEGIN PRIVATE KEY") {
            var outer = DERReader(data: der)
            let sequence = try outer.read(expectedTag: 0x30)
            var inner = DERReader(data: sequence)
            _ = try inner.read(expectedTag: 0x02)
            _ = try inner.read(expectedTag: 0x30)
            return try inner.read(expectedTag: 0x04)
        }

        throw SourceDecodeError("unsupported RSA private-key PEM header")
    }
}

private struct DERReader {
    let data: Data
    var index = 0

    mutating func read(expectedTag: UInt8) throws -> Data {
        guard index < data.count else {
            throw SourceDecodeError("DER truncated before tag")
        }

        let tag = data[index]
        index += 1
        guard tag == expectedTag else {
            throw SourceDecodeError(
                "DER tag mismatch: got 0x\(String(tag, radix: 16)), expected 0x\(String(expectedTag, radix: 16))"
            )
        }

        let length = try readLength()
        guard length >= 0, index + length <= data.count else {
            throw SourceDecodeError("DER value out of bounds")
        }

        let value = data.subdata(in: index..<(index + length))
        index += length
        return value
    }

    private mutating func readLength() throws -> Int {
        guard index < data.count else {
            throw SourceDecodeError("DER truncated before length")
        }

        let first = data[index]
        index += 1

        if first & 0x80 == 0 {
            return Int(first)
        }

        let count = Int(first & 0x7f)
        guard count > 0,
              count <= MemoryLayout<Int>.size,
              index + count <= data.count else {
            throw SourceDecodeError("unsupported DER length")
        }

        var length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(data[index])
            index += 1
        }
        return length
    }
}

private struct SourceDecodeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
