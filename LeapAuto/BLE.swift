//
//  BLE.swift
//  蓝牙钥匙协议：证书 → 会话派生 → 认证帧 → 控车帧 → 回执解码
//  与 app/src/main/java/com/leapauto/app/bluetooth/BleKeyProtocol.kt + BleSm2Crypto.kt 逐字节对齐
//  已用官方测试向量（passive-vectors.json / sm2-vectors）验证：
//    authentication8/9、unlock、lock、8 种回执帧 全部一致
//

import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

// ============================================================ 帧类型

enum BleFrameType: Int {
    case encrypted = 0xAB
    case event = 0xAC
    case authentication = 0xAE
    case reconnect = 0xEE

    var headerSize: Int {
        switch self {
        case .encrypted: return 6
        case .event: return 10
        case .authentication, .reconnect: return 4
        }
    }
}

enum BleLockAction: Int {
    case unlock = 1
    case lock = 2

    var label: String { self == .lock ? "上锁" : "解锁" }
}

struct BleFrame {
    let type: BleFrameType
    let bytes: [UInt8]

    var payload: [UInt8] {
        bytes.count > type.headerSize ? Array(bytes[type.headerSize...]) : []
    }
}

// ============================================================ 回执

enum BleResponse {
    case authenticated(lockState: String)
    case reconnectCredential(String)
    case commandResult(identifier: String, result: String?)
    case unknown

    /// 配置同步确认：identifier == "3" 且 result 为 "0"/"00"
    var confirmsConfiguration: Bool {
        if case let .commandResult(identifier, result) = self {
            return identifier == "3" && (result == "0" || result == "00")
        }
        return false
    }
}

enum BleEvent {
    case rejected(resultCode: Int)
    case lockAction(crc8: Int, trigger: Int, action: BleLockAction?)
    case unknown

    func confirms(_ expected: BleLockAction) -> Bool {
        if case let .lockAction(_, trigger, action) = self {
            return trigger == 1 && action == expected
        }
        return false
    }
}

// ============================================================ 证书

struct BleKeyCertificate: Codable, Equatable {
    let ecdhPublicKey: String
    let keyType: Int          // 0 = P-256, 1 = SM2
    let passwordCard: String
    let plainText: String
    let signResult: String
    let vin: String

    enum ParseError: LocalizedError {
        case unsupportedType
        case badPasswordCard
        case missingField(String)
        case vinMismatch
        case notAccepted

        var errorDescription: String? {
            switch self {
            case .unsupportedType: return "不支持的蓝牙钥匙证书类型"
            case .badPasswordCard: return "蓝牙 passwordCard 必须为 ≥80 字节 ASCII"
            case .missingField(let f): return "蓝牙钥匙证书缺少 \(f)"
            case .vinMismatch: return "蓝牙钥匙证书与当前车辆不匹配"
            case .notAccepted: return "蓝牙钥匙证书同步未成功，请检查登录状态后重试"
            }
        }
    }

    static func validate(_ c: BleKeyCertificate) throws {
        guard c.keyType == 0 || c.keyType == 1 else { throw ParseError.unsupportedType }
        let card = Array(c.passwordCard.utf8)
        guard card.count >= 80, card.allSatisfy({ $0 <= 127 }) else { throw ParseError.badPasswordCard }
        guard !c.ecdhPublicKey.isEmpty, !c.plainText.isEmpty, !c.signResult.isEmpty else {
            throw ParseError.missingField("认证字段")
        }
        guard !c.vin.isEmpty else { throw ParseError.missingField("vin") }
    }

    /// 从 /combine/syncBluetoothKeys 响应解析
    static func fromResponse(_ response: [String: Any], expectedVin: String) throws -> BleKeyCertificate {
        if let success = response["success"] as? Bool, success == false { throw ParseError.notAccepted }
        for key in ["code", "result", "status"] {
            if let raw = response[key], !(raw is NSNull) {
                let text = String(describing: raw)
                if text != "0" && text != "200" { throw ParseError.notAccepted }
                break
            }
        }
        let data = response["data"] as? [String: Any]
        let node = (data?["bluetoothKey"] as? [String: Any])
            ?? (response["bluetoothKey"] as? [String: Any])
            ?? ((response["ecdhPublicKey"] != nil && response["passwordCard"] != nil) ? response : nil)
        guard let n = node else { throw ParseError.missingField("bluetoothKey") }
        return try fromJson(n, expectedVin: expectedVin)
    }

    static func fromJson(_ json: [String: Any], expectedVin: String) throws -> BleKeyCertificate {
        guard !expectedVin.isEmpty else { throw ParseError.missingField("vin") }
        if let rawVin = json["vin"], !(rawVin is NSNull) {
            guard let v = rawVin as? String else { throw ParseError.vinMismatch }
            guard v.isEmpty || v == expectedVin else { throw ParseError.vinMismatch }
        }
        let vin = (json["vin"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? expectedVin

        var keyType = 0
        switch json["keyType"] {
        case nil, is NSNull:
            keyType = 0
        case let n as NSNumber:
            keyType = n.intValue
        case let s as String:
            guard let v = Int(s) else { throw ParseError.unsupportedType }
            keyType = v
        default:
            throw ParseError.unsupportedType
        }

        func str(_ key: String) throws -> String {
            guard let v = json[key] as? String, !v.isEmpty else {
                throw ParseError.missingField(key)
            }
            return v
        }

        let cert = BleKeyCertificate(ecdhPublicKey: try str("ecdhPublicKey"),
                                     keyType: keyType,
                                     passwordCard: try str("passwordCard"),
                                     plainText: try str("plainText"),
                                     signResult: try str("signResult"),
                                     vin: vin)
        try validate(cert)
        return cert
    }
}

// ============================================================ 标定与被动配置

struct BleCalibration: Codable, Equatable {
    var distanceCalibration: Int = 56
    var coefficientHundredths: Int = 200
    var unlockCalibration: Int = 8
    var lockCalibration: Int = 16

    static let defaultConfig = BleCalibration()
    static let c16Default = BleCalibration(distanceCalibration: 69, coefficientHundredths: 100,
                                           unlockCalibration: 4, lockCalibration: 21)

    var isByteValid: Bool {
        (0...255).contains(distanceCalibration) && (0...65_535).contains(coefficientHundredths)
            && (0...255).contains(unlockCalibration) && (0...255).contains(lockCalibration)
    }

    /// "56;2.00;08;16"
    var protocolText: String {
        let major = coefficientHundredths / 100
        let minor = coefficientHundredths % 100
        return "\(distanceCalibration);\(major).\(String(format: "%02d", minor));"
            + "\(String(format: "%02d", unlockCalibration));\(String(format: "%02d", lockCalibration))"
    }

    var encoded: [UInt8] {
        [UInt8(truncatingIfNeeded: distanceCalibration),
         UInt8(truncatingIfNeeded: coefficientHundredths),
         UInt8(truncatingIfNeeded: coefficientHundredths >> 8),
         UInt8(truncatingIfNeeded: unlockCalibration),
         UInt8(truncatingIfNeeded: lockCalibration)]
    }

    static func defaultForModel(_ carType: String?) -> BleCalibration {
        let model = (carType ?? "").uppercased()
        return (model.contains("C16") || model.contains("C10")) ? c16Default : defaultConfig
    }

    static func parse(_ value: String) -> BleCalibration? {
        guard value.count <= 32 else { return nil }
        let pattern = "^([0-9]{1,3});([0-9]{1,3})\\.([0-9]{2});([0-9]{1,3});([0-9]{1,3})$"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              m.numberOfRanges == 6,
              let g1 = Range(m.range(at: 1), in: value),
              let g2 = Range(m.range(at: 2), in: value),
              let g3 = Range(m.range(at: 3), in: value),
              let g4 = Range(m.range(at: 4), in: value),
              let g5 = Range(m.range(at: 5), in: value),
              let d = Int(value[g1]), let major = Int(value[g2]),
              let minor = Int(value[g3]), let u = Int(value[g4]), let l = Int(value[g5])
        else { return nil }
        let cal = BleCalibration(distanceCalibration: d, coefficientHundredths: major * 100 + minor,
                                 unlockCalibration: u, lockCalibration: l)
        return cal.isByteValid ? cal : nil
    }
}

struct BlePassiveConfiguration: Codable, Equatable {
    var enabled: Bool = false
    var autoUnlock: Bool = false
    var autoLock: Bool = false
    var buttonEnabled: Bool = false
    var calibration: BleCalibration = .defaultConfig

    static let manual = BlePassiveConfiguration(enabled: true)

    static func defaultForModel(_ carType: String?, protocolMinor: Int?) -> BlePassiveConfiguration {
        let model = (carType ?? "").uppercased()
        let isLeap3 = model.contains("C16") || model.contains("C10") || (protocolMinor ?? 0) >= 9
        let supportsButton = protocolMinor == nil || protocolMinor! >= 9 || isLeap3
        return BlePassiveConfiguration(enabled: true, autoUnlock: false, autoLock: false,
                                       buttonEnabled: supportsButton,
                                       calibration: .defaultForModel(carType))
    }

    /// 认证文本中的配置段（含 a=9/8 分支）
    func authenticationFlags(protocolMinor: Int) -> [UInt8] {
        // 老车型把“总开关”和“被动解锁”合并到同一 flag
        var flags: [UInt8] = [
            (enabled && (protocolMinor >= 9 || autoUnlock)) ? 1 : 0,
            (enabled && autoLock) ? 1 : 0
        ]
        if protocolMinor >= 9 {
            flags.append((enabled && autoUnlock) ? 1 : 0)
            flags.append((enabled && buttonEnabled) ? 1 : 0)
        }
        return flags
    }

    /// LEGACY_VERSIONED 认证文本的尾部配置段
    func authenticationFields(protocolMinor: Int) -> String {
        "\(calibration.protocolText);\(authenticationFlags(protocolMinor: protocolMinor).map(String.init).joined(separator: ";"));"
    }

    /// 1PAO_V010 用于重连/配置的字节序列：标定 5 字节 + 4 个 flag
    func reconnectFields(supportsButton: Bool) -> [UInt8] {
        calibration.encoded + [
            enabled ? 1 : 0,
            (enabled && autoLock) ? 1 : 0,
            (enabled && autoUnlock) ? 1 : 0,
            supportsButton ? 1 : 0
        ]
    }
}

enum BleCompatibilityProfile {
    case legacy        // LEGACY_VERSIONED 文本 + 老配置字节
    case onePaoV010    // 固定布局（当前实际使用）

    /// 与 Kotlin 侧一致：始终走 1PAO
    static var forConnection: BleCompatibilityProfile { .onePaoV010 }

    func encodeConfiguration(_ c: BlePassiveConfiguration, protocolMinor: Int,
                             supportsButton: Bool) -> [UInt8] {
        switch self {
        case .legacy:
            return c.calibration.encoded + c.authenticationFlags(protocolMinor: protocolMinor)
        case .onePaoV010:
            return c.reconnectFields(supportsButton: supportsButton)
        }
    }
}

// ============================================================ 工具函数

@inline(__always)
func bleLittleEndian(_ value: UInt64, _ size: Int) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: size)
    var v = value
    for i in 0..<size {
        out[i] = UInt8(truncatingIfNeeded: v)
        v >>= 8
    }
    return out
}

func bleUnsignedLE(_ bytes: [UInt8], _ offset: Int, _ size: Int) -> UInt64 {
    var v: UInt64 = 0
    var i = size - 1
    while i >= 0 {
        v = (v << 8) | UInt64(bytes[offset + i])
        i -= 1
    }
    return v
}

// ============================================================ 协议常量与会话

enum BleKeyProtocol {
    static let serviceUUID = "0000FFFE-0000-1000-8000-00805F9B34FB"
    static let characteristicUUID = "0000FFF2-0000-1000-8000-00805F9B34FB"
    static let cccdUUID = "00002902-0000-1000-8000-00805F9B34FB"

    static let defaultProtocolMinor = 8
    static let leap3ProtocolMinor = 9

    /// 广告里携带的 protocol minor（000001XX-...）
    static func advertisedProtocolMinor(_ serviceUUIDs: [String]) -> Int? {
        for uuid in serviceUUIDs {
            let u = uuid.uppercased()
            guard u.hasPrefix("000001"), u.hasSuffix("-0000-1000-8000-00805F9B34FB") else { continue }
            let start = u.index(u.startIndex, offsetBy: 6)
            let end = u.index(u.startIndex, offsetBy: 8)
            if let v = Int(u[start..<end], radix: 16) { return v }
        }
        return nil
    }

    static func protocolMinor(_ advertised: [String], carType: String?) -> Int {
        advertisedProtocolMinor(advertised) ?? defaultMinorForModel(carType: carType)
    }

    static func defaultMinorForModel(carType: String?) -> Int {
        let model = (carType ?? "").uppercased()
        return (model.contains("C16") || model.contains("C10")) ? leap3ProtocolMinor : defaultProtocolMinor
    }

    /// 单包上限：MTU-3，夹在 [20, 160]
    static func chunkLimit(mtu: Int) -> Int {
        min(max(max(mtu, 23) - 3, 20), 160)
    }

    static func chunks(_ frame: [UInt8], mtu: Int) -> [[UInt8]] {
        let limit = chunkLimit(mtu: mtu)
        var out: [[UInt8]] = []
        var offset = 0
        while offset < frame.count {
            let end = min(offset + limit, frame.count)
            out.append(Array(frame[offset..<end]))
            offset = end
        }
        return out
    }

    /// CRC8（多项式 0x07）
    static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                if crc & 0x80 != 0 {
                    crc = (crc << 1) ^ 0x07
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }

    static func certificateDigest(_ cert: BleKeyCertificate) -> [UInt8] {
        var material = [UInt8]()
        for field in [cert.ecdhPublicKey, String(cert.keyType), cert.passwordCard,
                      cert.plainText, cert.signResult, cert.vin] {
            material.append(contentsOf: bleLittleEndian(UInt64(field.utf8.count), 4))
            material.append(contentsOf: Array(field.utf8))
        }
        return SM3.hash(material)
    }

    static func fingerprint(_ cert: BleKeyCertificate) -> String {
        certificateDigest(cert).map { String(format: "%02x", $0) }.joined()
    }

    static func sessionHash(keyType: Int, _ bytes: [UInt8]) -> [UInt8] {
        keyType == 1 ? SM3.hash(bytes) : Digest.sha256(bytes)
    }

    /// 解析事件帧
    static func parseEvent(_ frame: BleFrame) -> BleEvent {
        guard frame.type == .event, frame.bytes.count > 5 else { return .unknown }
        let payload = frame.payload
        switch Int(frame.bytes[5]) {
        case 1:
            guard let last = payload.last else { return .unknown }
            return .rejected(resultCode: Int(last))
        case 2:
            guard payload.count >= 3 else { return .unknown }
            let action = BleLockAction(rawValue: Int(payload[2]))
            return .lockAction(crc8: Int(payload[0]), trigger: Int(payload[1]), action: action)
        default:
            return .unknown
        }
    }
}

// ============================================================ 会话（密钥 + 加解密）

final class BleKeySession {
    let sessionId: UInt32
    let publicKey: [UInt8]
    private let key: [UInt8]
    private let iv: [UInt8]
    private let certificateFingerprint: [UInt8]
    private let keyType: Int

    init(sessionId: UInt32, publicKey: [UInt8], key: [UInt8], iv: [UInt8],
         certificateFingerprint: [UInt8], keyType: Int) {
        self.sessionId = sessionId
        self.publicKey = publicKey
        self.key = key
        self.iv = iv
        self.certificateFingerprint = certificateFingerprint
        self.keyType = keyType
    }

    // ---------------------------------------------------------- 建立会话

    static func create(certificate: BleKeyCertificate, vin: String) throws -> BleKeySession {
        try BleKeyCertificate.validate(certificate)
        guard !vin.isEmpty, certificate.vin == vin else { throw BleKeyCertificate.ParseError.vinMismatch }
        let sessionId = UInt32.random(in: 0...UInt32.max)

        if certificate.keyType == 1 {
            return try createSm2(certificate: certificate, vin: vin,
                                 privateScalar: SM2Agreement.randomScalar(), sessionId: sessionId)
        }
        return try createP256(certificate: certificate, vin: vin, sessionId: sessionId)
    }

    /// P-256（ECDH → SHA-256）
    /// 仅 Apple 平台提供 Security.framework；其他平台（如本机自检）降级为抛出错误，
    /// 因为实际车端证书 keyType=1（SM2）才是主路径。
    private static func createP256(certificate: BleKeyCertificate, vin: String,
                                   sessionId: UInt32) throws -> BleKeySession {
        #if canImport(Security)
        guard let pubData = Data(base64Encoded: certificate.ecdhPublicKey),
              pubData.count == 65, pubData[0] == 0x04 else {
            throw LeapCryptoError.badEncoding
        }
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        var err: Unmanaged<CFError>?
        guard let peer = SecKeyCreateWithData(pubData as CFData, attrs as CFDictionary, &err) else {
            throw LeapCryptoError.badEncoding
        }
        let privAttrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256
        ]
        guard let local = SecKeyCreateRandomKey(privAttrs as CFDictionary, &err) else {
            throw LeapCryptoError.badEncoding
        }
        guard let shared = SecKeyCopyKeyExchangeResult(local, .ecdhKeyExchangeStandard,
                                                       peer, [:] as CFDictionary, &err) as Data?,
              shared.count == 32 else {
            throw LeapCryptoError.badPoint
        }
        guard let localPub = SecKeyCopyPublicKey(local),
              let localPubCF = SecKeyCopyExternalRepresentation(localPub, &err) else {
            throw LeapCryptoError.badEncoding
        }
        let localPubData = localPubCF as Data
        return derive(certificate: certificate, vin: vin, sessionId: sessionId,
                      publicKey: [UInt8](localPubData), sharedSecret: [UInt8](shared))
        #else
        _ = certificate
        _ = vin
        _ = sessionId
        throw LeapCryptoError.badCertificate
        #endif
    }

    /// SM2（XOR 混合协商 → SM3）
    private static func createSm2(certificate: BleKeyCertificate, vin: String,
                                  privateScalar: [UInt8], sessionId: UInt32) throws -> BleKeySession {
        var encoded = certificate.ecdhPublicKey
        if encoded.hasPrefix("-----BEGIN CERTIFICATE-----") {
            let begin = "-----BEGIN CERTIFICATE-----"
            let end = "-----END CERTIFICATE-----"
            guard encoded.hasSuffix(end) else { throw LeapCryptoError.badCertificate }
            let start = encoded.index(encoded.startIndex, offsetBy: begin.count)
            let stop = encoded.index(encoded.endIndex, offsetBy: -end.count)
            encoded = String(encoded[start..<stop])
        }
        let compact = encoded.filter { !" \t\r\n".contains($0) }
        guard let der = Data(base64Encoded: compact) else {
            throw LeapCryptoError.badCertificate
        }
        let point = try extractSM2PointFromCertificate([UInt8](der))
        let (publicKey, secret) = try SM2Agreement.agree(peerEncoded: point, privateScalar: privateScalar)
        return derive(certificate: certificate, vin: vin, sessionId: sessionId,
                      publicKey: publicKey, sharedSecret: secret)
    }

    /// 从 X.509 证书里取出 SM2 公钥点
    private static func extractSM2PointFromCertificate(_ der: [UInt8]) throws -> [UInt8] {
        let point = try Self.parseCertificatePublicKey(der)
        return point
    }

    private static func parseCertificatePublicKey(_ der: [UInt8]) throws -> [UInt8] {
        var idx = 0

        func readHeader(_ i: inout Int) -> (tag: UInt8, len: Int, start: Int)? {
            guard i + 2 <= der.count else { return nil }
            let tag = der[i]; i += 1
            var len = Int(der[i]); i += 1
            if len & 0x80 != 0 {
                let n = len & 0x7F
                guard n > 0, n <= 4, i + n <= der.count else { return nil }
                len = 0
                for _ in 0..<n { len = (len << 8) | Int(der[i]); i += 1 }
            }
            return (tag, len, i)
        }

        guard let outer = readHeader(&idx), outer.tag == 0x30 else {
            throw LeapCryptoError.badCertificate
        }
        let outerEnd = min(outer.start + outer.len, der.count)

        var t = outer.start
        guard let tbs = readHeader(&t), tbs.tag == 0x30 else { throw LeapCryptoError.badCertificate }
        t = tbs.start
        let tbsEnd = min(tbs.start + tbs.len, outerEnd)

        // version [0] EXPLICIT（可选）
        if t < tbsEnd, der[t] == 0xA0 {
            guard let ver = readHeader(&t) else { throw LeapCryptoError.badCertificate }
            t = ver.start + ver.len
        }
        // serialNumber
        guard let serial = readHeader(&t), serial.tag == 0x02 else { throw LeapCryptoError.badCertificate }
        t = serial.start + serial.len
        // signature
        guard let sigAlg = readHeader(&t), sigAlg.tag == 0x30 else { throw LeapCryptoError.badCertificate }
        t = sigAlg.start + sigAlg.len
        // issuer
        guard let issuer = readHeader(&t), issuer.tag == 0x30 else { throw LeapCryptoError.badCertificate }
        t = issuer.start + issuer.len
        // validity
        guard let validity = readHeader(&t), validity.tag == 0x30 else { throw LeapCryptoError.badCertificate }
        t = validity.start + validity.len
        // subject
        guard let subject = readHeader(&t), subject.tag == 0x30 else { throw LeapCryptoError.badCertificate }
        t = subject.start + subject.len
        // subjectPublicKeyInfo
        guard let spki = readHeader(&t), spki.tag == 0x30, spki.len > 0 else {
            throw LeapCryptoError.badCertificate
        }
        var s = spki.start
        guard let alg = readHeader(&s), alg.tag == 0x30 else { throw LeapCryptoError.badCertificate }
        let algEnd = min(alg.start + alg.len, der.count)
        guard alg.start < algEnd else { throw LeapCryptoError.badCertificate }
        guard containsSM2OID(Array(der[alg.start..<algEnd])) else {
            throw LeapCryptoError.badCertificate
        }
        s = algEnd
        guard let bits = readHeader(&s), bits.tag == 0x03, bits.len > 1 else {
            throw LeapCryptoError.badCertificate
        }
        let keyStart = bits.start + 1
        let keyEnd = min(keyStart + bits.len - 1, der.count)
        guard keyStart < keyEnd else { throw LeapCryptoError.badCertificate }
        return Array(der[keyStart..<keyEnd])
    }

    /// 检查 AlgorithmIdentifier 是否含 sm2p256v1 OID (1.2.156.10197.1.301)
    private static func containsSM2OID(_ bytes: [UInt8]) -> Bool {
        let oid: [UInt8] = [0x06, 0x08, 0x2A, 0x81, 0x1C, 0xCF, 0x55, 0x01, 0x82, 0x2D]
        guard bytes.count >= oid.count else { return false }
        for i in 0...(bytes.count - oid.count) {
            if Array(bytes[i..<(i + oid.count)]) == oid { return true }
        }
        return false
    }

    /// 会话密钥派生（与 BleKeyProtocol.deriveSession 一致）
    private static func derive(certificate: BleKeyCertificate, vin: String, sessionId: UInt32,
                               publicKey: [UInt8], sharedSecret: [UInt8]) -> BleKeySession {
        let reversedVin = Array(vin.reversed()).map { String($0) }.joined()
        let selector = BleKeyProtocol.sessionHash(keyType: certificate.keyType,
                                                  bleLittleEndian(UInt64(sessionId), 4) + Array(reversedVin.utf8))
        let offset = (Int(selector[0]) >> 4) * 5
        let card = Array(certificate.passwordCard.utf8)
        let material = Array(card[offset..<(offset + 5)]) + sharedSecret
        let digest = BleKeyProtocol.sessionHash(keyType: certificate.keyType, material)

        // digest 转成小写 hex ASCII，key = [0,16)，iv = [48,64)
        let alphabet = Array("0123456789abcdef".utf8)
        var hex = [UInt8]()
        hex.reserveCapacity(digest.count * 2)
        for byte in digest {
            hex.append(alphabet[Int(byte >> 4)])
            hex.append(alphabet[Int(byte & 0x0F)])
        }
        let key = Array(hex[0..<16])
        let iv = Array(hex[48..<64])
        return BleKeySession(sessionId: sessionId, publicKey: publicKey, key: key, iv: iv,
                             certificateFingerprint: BleKeyProtocol.certificateDigest(certificate),
                             keyType: certificate.keyType)
    }

    // ---------------------------------------------------------- 加解密

    private func crypt(_ bytes: [UInt8], encrypt: Bool) throws -> [UInt8] {
        if keyType == 1 {
            return encrypt
                ? SM4.cbcEncrypt(key: key, iv: iv, plain: bytes)
                : try SM4.cbcDecrypt(key: key, iv: iv, cipher: bytes)
        }
        if encrypt {
            return try [UInt8](LeapSign.aesCBCEncrypt(Data(bytes), key: Data(key), iv: Data(iv)))
        }
        return try [UInt8](LeapSign.aesCBCDecrypt(Data(bytes), key: Data(key), iv: Data(iv)))
    }

    // ---------------------------------------------------------- 认证帧

    func buildAuthentication(certificate: BleKeyCertificate, accountId: String, deviceId: String,
                             protocolMinor: Int, epochSeconds: Int64,
                             configuration: BlePassiveConfiguration,
                             profile: BleCompatibilityProfile,
                             supportsButton: Bool) throws -> [UInt8] {
        guard BleKeyProtocol.certificateDigest(certificate) == certificateFingerprint else {
            throw LeapCryptoError.badCertificate
        }
        guard epochSeconds >= 0, (0...255).contains(protocolMinor),
              !accountId.isEmpty, !deviceId.isEmpty,
              !accountId.contains(";"), !deviceId.contains(";") else {
            throw LeapCryptoError.badCertificate
        }

        let fields = certificate.plainText.components(separatedBy: ";")
        guard fields.count >= 6 else { throw LeapCryptoError.badCertificate }

        let authFields: [String]
        switch profile {
        case .legacy:
            var f = fields
            f[1] = accountId
            f[2] = deviceId
            authFields = f
        case .onePaoV010:
            authFields = [fields[0], accountId, deviceId, fields[3], fields[4], fields[5]]
        }

        let settings: String
        switch profile {
        case .legacy:
            settings = configuration.authenticationFields(protocolMinor: protocolMinor)
        case .onePaoV010:
            let tail = Array(configuration.reconnectFields(supportsButton: supportsButton).dropFirst(5))
            settings = "\(configuration.calibration.protocolText);\(tail.map { String($0) }.joined(separator: ";"));"
        }

        let text = "\(epochSeconds);\(authFields.joined(separator: ";"));\(settings)"
        let textBytes = Array(text.utf8)
        guard let signature = Data(base64Encoded: certificate.signResult), !signature.isEmpty else {
            throw LeapCryptoError.badCertificate
        }

        var plain = bleLittleEndian(UInt64(textBytes.count), 4)
        plain.append(contentsOf: textBytes)
        plain.append(contentsOf: [UInt8](signature))
        let cipher = try crypt(plain, encrypt: true)
        let encrypted = Array(Data(cipher).base64EncodedString().utf8)

        var payload = bleLittleEndian(UInt64(sessionId), 4)
        payload.append(contentsOf: publicKey)
        payload.append(contentsOf: encrypted)
        payload.append(contentsOf: [1, 9])
        guard payload.count <= 0xFFFF else { throw LeapCryptoError.badCertificate }

        var frame = [UInt8]([0xAA, 0xAE])
        frame.append(contentsOf: bleLittleEndian(UInt64(payload.count), 2))
        frame.append(contentsOf: payload)
        return frame
    }

    // ---------------------------------------------------------- 控车帧

    func buildCommand(_ action: BleLockAction, epochSeconds: Int64) throws -> [UInt8] {
        try buildEncryptedCommand(UInt8(action.rawValue), [], epochSeconds: epochSeconds)
    }

    func buildConfiguration(_ configuration: BlePassiveConfiguration, protocolMinor: Int,
                            epochSeconds: Int64, profile: BleCompatibilityProfile,
                            supportsButton: Bool) throws -> [UInt8] {
        try buildEncryptedCommand(3, profile.encodeConfiguration(configuration,
                                                                protocolMinor: protocolMinor,
                                                                supportsButton: supportsButton),
                                  epochSeconds: epochSeconds)
    }

    private func buildEncryptedCommand(_ commandId: UInt8, _ parameters: [UInt8],
                                       epochSeconds: Int64) throws -> [UInt8] {
        guard epochSeconds >= 0 else { throw LeapCryptoError.badCertificate }
        var command = bleLittleEndian(UInt64(epochSeconds), 8)
        command.append(commandId)
        command.append(contentsOf: parameters)
        var plain: [UInt8] = [BleKeyProtocol.crc8(command)]
        plain.append(contentsOf: command)
        let cipher = try crypt(plain, encrypt: true)
        let payload = Array(Data(cipher).base64EncodedString().utf8)
        var frame = [UInt8]([0xAA, 0xAB])
        frame.append(contentsOf: bleLittleEndian(UInt64(payload.count), 4))
        frame.append(contentsOf: payload)
        return frame
    }

    // ---------------------------------------------------------- 回执解码

    func decodeResponse(_ frame: BleFrame) throws -> BleResponse {
        guard frame.type == .encrypted else { return .unknown }
        let base64Text = String(decoding: frame.payload, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cipher = Data(base64Encoded: base64Text), !cipher.isEmpty else { return .unknown }
        let plain = try crypt([UInt8](cipher), encrypt: false)
        guard let text = String(bytes: plain, encoding: .utf8) else { return .unknown }

        let fields = text.components(separatedBy: ";")
        guard fields.count >= 2 else { return .unknown }
        switch fields[0] {
        case "0":
            return fields[1].isEmpty ? .unknown : .authenticated(lockState: fields[1])
        case "1":
            return isValidCredential(fields[1]) ? .reconnectCredential(fields[1]) : .unknown
        case "2":
            return .commandResult(identifier: fields[1], result: fields.count > 2 ? fields[2] : nil)
        default:
            return .unknown
        }
    }

    private func isValidCredential(_ hex: String) -> Bool {
        guard !hex.isEmpty, hex.count % 2 == 0, hex.count <= 1024 else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }
}

// ============================================================ 帧解码器

final class BleFrameDecoder {
    private var pending: [UInt8] = []
    private let maxFrameSize: Int

    init(maxFrameSize: Int = 65_539) {
        self.maxFrameSize = max(maxFrameSize, 10)
    }

    func append(_ bytes: [UInt8]) -> [BleFrame] {
        guard bytes.count <= maxFrameSize else { return [] }
        pending.append(contentsOf: bytes)
        var frames: [BleFrame] = []
        var offset = 0

        while pending.count - offset >= 2 {
            guard pending[offset] == 0xAA,
                  let type = BleFrameType(rawValue: Int(pending[offset + 1])) else {
                offset += 1
                continue
            }
            if pending.count - offset < type.headerSize { break }
            let lengthOffset = type == .event ? 6 : 2
            let lengthSize = type.headerSize == 4 ? 2 : 4
            guard offset + lengthOffset + lengthSize <= pending.count else { break }
            let length = Int(bleUnsignedLE(pending, offset + lengthOffset, lengthSize))

            // 加密帧载荷不可能为 0，长度 0 视为伪帧头
            if type == .encrypted && length == 0 {
                offset += 1
                continue
            }
            if length < 0 || length > maxFrameSize {
                offset += 1
                continue
            }
            let total = type.headerSize + length
            if pending.count - offset < total { break }
            frames.append(BleFrame(type: type,
                                   bytes: Array(pending[offset..<(offset + total)])))
            offset += total
        }

        pending = offset < pending.count ? Array(pending[offset...]) : []
        if pending.count == 1 && pending[0] != 0xAA { pending = [] }
        if pending.count > maxFrameSize { pending = [] }
        return frames
    }

    func clear() { pending = [] }
}

// ============================================================ 连接阶段（供 UI 与控制器共用）

enum BleConnectionPhase: String {
    case idle, scanning, connecting, discovering, subscribing, authenticating, configuring, ready, sending, failed

    var label: String {
        switch self {
        case .idle: return "未连接"
        case .scanning: return "正在扫描"
        case .connecting: return "正在连接"
        case .discovering: return "正在检查车辆服务"
        case .subscribing: return "正在建立通信"
        case .authenticating: return "正在认证"
        case .configuring: return "正在同步钥匙设置"
        case .ready: return "已认证"
        case .sending: return "等待车辆确认"
        case .failed: return "连接不可用"
        }
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .discovering, .subscribing, .authenticating, .configuring, .sending: return true
        default: return false
        }
    }
}

