//
//  Crypto.swift
//  平台加密层：RSA(手机号) / AES-128-CBC(操作密码) / MD5 / SHA-256 / HMAC-SHA256 / 签名派生
//  全部与 APK 内 HM.kt / Crypto.kt 逐字节对齐，已用 Python 参考实现交叉验证。
//

import Foundation

#if canImport(Security)
import Security
#endif

#if canImport(CommonCrypto)
import CommonCrypto
#endif

enum LeapSign {

    // ---------------------------------------------------------- 哈希

    static func md5Hex(_ input: String) -> String {
        Digest.md5(Array(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// APK 的 md5Short：md5 十六进制串取 [8, 24)
    static func md5Short(_ input: String) -> String {
        let hex = md5Hex(input)
        guard hex.count >= 24 else { return hex }
        let s = hex.index(hex.startIndex, offsetBy: 8)
        let e = hex.index(hex.startIndex, offsetBy: 24)
        return String(hex[s..<e])
    }

    static func sha256Hex(_ input: String) -> String {
        Digest.sha256(Array(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func hmacSHA256Hex(key: Data, _ input: String) -> String {
        Digest.hmacSHA256(key: [UInt8](key), message: Array(input.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    // ---------------------------------------------------------- 排序拼接

    /// 与 APK sortAndConcatValues 一致：nil 跳过、空串保留、按键名排序后拼接“值”
    static func sortAndConcat(_ maps: [String: String?]...) -> String {
        var merged: [String: String] = [:]
        for m in maps {
            for (k, v) in m where v != nil { merged[k] = v }
        }
        return merged.keys.sorted().map { merged[$0]! }.joined()
    }

    // ---------------------------------------------------------- RSA（手机号）

    /// APK 内硬编码的短信登录 RSA 公钥（X.509 SubjectPublicKeyInfo，1024 位）
    static let phonePublicKeyX509 =
        "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDHUIQKhkwNqJFTZPe98mC1lmpbY9r/+7PEWZg8ebqYXT3sumKRaQ0zcoTx42x0iybmCRXy4CcZrgGAbwKzwqwNw0rFquJ6c7mgQA6k3lZU3p96qBlzK7DSkoFR6mO9pjcd2hlJ8wH+IwI5b8IWWZhwVN/4cM7npG0S0zeRn3soEwIDAQAB"

    /// RSA/ECB/PKCS1Padding → base64url 去 '='
    static func rsaEncryptPhone(_ phone: String) throws -> String {
        #if canImport(Security)
        guard let spki = Data(base64Encoded: phonePublicKeyX509) else {
            throw LeapCryptoError.badCertificate
        }
        guard let pkcs1 = extractRSAPublicKey(from: spki) else {
            throw LeapCryptoError.badCertificate
        }
        var err: Unmanaged<CFError>?
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &err) else {
            throw LeapCryptoError.badCertificate
        }
        guard let cipher = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1,
                                                     Data(phone.utf8) as CFData, &err) else {
            throw LeapCryptoError.badCertificate
        }
        return (cipher as Data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #else
        // 非 Apple 平台：自检环境下仅返回占位（iOS 始终走上面分支）
        return "RSA_PLACEHOLDER"
        #endif
    }

    /// 从 SPKI 中取出 PKCS#1 RSAPublicKey（BIT STRING 内容，跳过 unused-bits 字节）
    private static func extractRSAPublicKey(from der: Data) -> Data? {
        let b = [UInt8](der)
        var i = 0

        func readHeader(_ idx: inout Int) -> (tag: UInt8, len: Int, start: Int)? {
            guard idx + 2 <= b.count else { return nil }
            let tag = b[idx]; idx += 1
            var len = Int(b[idx]); idx += 1
            if len & 0x80 != 0 {
                let n = len & 0x7F
                guard n > 0, n <= 4, idx + n <= b.count else { return nil }
                len = 0
                for _ in 0..<n { len = (len << 8) | Int(b[idx]); idx += 1 }
            }
            return (tag, len, idx)
        }

        guard let outer = readHeader(&i), outer.tag == 0x30 else { return nil }
        let outerEnd = min(outer.start + outer.len, b.count)
        i = outer.start
        guard let alg = readHeader(&i), alg.tag == 0x30 else { return nil }
        i = alg.start + alg.len
        guard i < outerEnd, let bits = readHeader(&i), bits.tag == 0x03, bits.len > 1 else { return nil }
        let start = bits.start + 1
        let end = min(start + bits.len - 1, b.count)
        guard start < end else { return nil }
        return der.subdata(in: start..<end)
    }

    // ---------------------------------------------------------- AES 操作密码

    /// AES-128-CBC/PKCS7，key = md5Short(token[0..32])，iv = md5Short(token[32..64])
    static func encryptOperationPassword(_ password: String, token rawToken: String) throws -> String {
        var token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.count >= 32 && token.count < 64 { token += token }
        guard token.count >= 64 else { throw LeapCryptoError.badToken }
        let key = Data(md5Short(String(token.prefix(32))).utf8)
        let iv = Data(md5Short(String(token.dropFirst(32).prefix(32))).utf8)
        let cipher = try aesCBCEncrypt(Data(password.trimmingCharacters(in: .whitespaces).utf8),
                                       key: key, iv: iv)
        return cipher.base64EncodedString()
    }

    static func aesCBCEncrypt(_ plain: Data, key: Data, iv: Data) throws -> Data {
        #if canImport(CommonCrypto)
        var out = Data(count: plain.count + Int(kCCBlockSizeAES128))
        var moved = 0
        var status: CCCryptorStatus = -1
        let outCapacity = out.count
        plain.withUnsafeBytes { (inPtr: UnsafeRawBufferPointer) in
            key.withUnsafeBytes { (keyPtr: UnsafeRawBufferPointer) in
                iv.withUnsafeBytes { (ivPtr: UnsafeRawBufferPointer) in
                    out.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
                        status = CCCrypt(CCOperation(kCCEncrypt),
                                         CCAlgorithm(kCCAlgorithmAES),
                                         CCOptions(kCCOptionPKCS7Padding),
                                         keyPtr.baseAddress, key.count,
                                         ivPtr.baseAddress,
                                         inPtr.baseAddress, plain.count,
                                         outPtr.baseAddress, outCapacity,
                                         &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw LeapCryptoError.badCiphertext }
        return out.prefix(moved)
        #else
        return Data(AESFallback.encryptCBC(plain: [UInt8](plain), key: [UInt8](key), iv: [UInt8](iv)))
        #endif
    }

    static func aesCBCDecrypt(_ cipher: Data, key: Data, iv: Data) throws -> Data {
        #if canImport(CommonCrypto)
        var out = Data(count: cipher.count + Int(kCCBlockSizeAES128))
        var moved = 0
        var status: CCCryptorStatus = -1
        let outCapacity = out.count
        cipher.withUnsafeBytes { (inPtr: UnsafeRawBufferPointer) in
            key.withUnsafeBytes { (keyPtr: UnsafeRawBufferPointer) in
                iv.withUnsafeBytes { (ivPtr: UnsafeRawBufferPointer) in
                    out.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
                        status = CCCrypt(CCOperation(kCCDecrypt),
                                         CCAlgorithm(kCCAlgorithmAES),
                                         CCOptions(kCCOptionPKCS7Padding),
                                         keyPtr.baseAddress, key.count,
                                         ivPtr.baseAddress,
                                         inPtr.baseAddress, cipher.count,
                                         outPtr.baseAddress, outCapacity,
                                         &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw LeapCryptoError.badCiphertext }
        return out.prefix(moved)
        #else
        return Data(try AESFallback.decryptCBC(cipher: [UInt8](cipher),
                                               key: [UInt8](key), iv: [UInt8](iv)))
        #endif
    }

    // ---------------------------------------------------------- 网关 signKey

    /// signKey = base64url(token[2]) XOR base64(r2) XOR base64(r3)，取三者最短长度
    static func deriveSignKey(accessToken: String, r2: String, r3: String) throws -> Data {
        let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let tail = base64UrlDecode(parts[2]),
              let a = Data(base64Encoded: r2, options: .ignoreUnknownCharacters),
              let b = Data(base64Encoded: r3, options: .ignoreUnknownCharacters) else {
            throw LeapCryptoError.badToken
        }
        let n = min(tail.count, a.count, b.count)
        guard n > 0 else { throw LeapCryptoError.badToken }
        var out = Data(count: n)
        for i in 0..<n {
            out[i] = tail[i] ^ a[i] ^ b[i]
        }
        return out
    }

    // ---------------------------------------------------------- JWT

    static func jwtExpiryMs(_ token: String) -> Int64 {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let payload = base64UrlDecode(parts[1]),
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let exp = (obj["exp"] as? NSNumber)?.int64Value, exp > 0 else { return 0 }
        return exp &* 1000
    }

    /// 网关 token 绑定 deviceId，存在时签名必须换用它
    static func jwtDeviceId(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let payload = base64UrlDecode(parts[1]),
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let userName = obj["user_name"] as? String else { return nil }
        guard let re = try? NSRegularExpression(pattern: "deviceId:([a-zA-Z0-9_-]+)") else { return nil }
        let range = NSRange(userName.startIndex..<userName.endIndex, in: userName)
        guard let m = re.firstMatch(in: userName, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: userName) else { return nil }
        return String(userName[r])
    }

    static func base64UrlDecode(_ input: String) -> Data? {
        var s = input.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    // ---------------------------------------------------------- Java URLEncoder 语义

    static func formEncode(_ s: String) -> String {
        var out = ""
        for b in Array(s.utf8) {
            switch b {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E, 0x5F, 0x2A:  // A-Z a-z 0-9 - . _ *
                out.append(Character(UnicodeScalar(b)))
            case 0x20:
                out.append("+")
            default:
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }

    // ---------------------------------------------------------- 工具

    static func randomDeviceId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func randomNonce() -> String {
        String(10000 + Int.random(in: 0..<10_000_000))
    }

    static func hexToBytes(_ hex: String) -> [UInt8]? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0, !clean.isEmpty else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let v = UInt8(clean[idx..<next], radix: 16) else { return nil }
            out.append(v)
            idx = next
        }
        return out
    }

    static func bytesToHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
