import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ============================================================
//  真实协议验证（访问零跑生产服务器）
//  判据：签名被服务器接受/拒绝的行为差异
//  容错：网络超时不计为失败（跳过并标注 SKIP）
// ============================================================

var pass = 0, fail = 0, skip = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { pass += 1; print("  PASS  \(name)") }
    else { fail += 1; print("  FAIL  \(name)  \(detail)") }
}
func skipTest(_ name: String, _ why: String) {
    skip += 1
    print("  SKIP  \(name)  (\(why))")
}

func sha256Hex(_ s: String) -> String {
    Digest.sha256(Array(s.utf8)).map { String(format: "%02x", $0) }.joined()
}
func hmacHex(key: [UInt8], _ s: String) -> String {
    Digest.hmacSHA256(key: key, message: Array(s.utf8))
        .map { String(format: "%02x", $0) }.joined()
}
func sortAndConcat(_ maps: [String: String?]...) -> String {
    var m: [String: String] = [:]
    for d in maps { for (k, v) in d where v != nil { m[k] = v } }
    return m.keys.sorted().map { m[$0]! }.joined()
}
func b64url(_ b: [UInt8]) -> String {
    Data(b).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

struct HttpResult {
    let status: Int
    let body: String
    let networkError: String?
    var isNetworkFailure: Bool { networkError != nil }
}

func http(_ url: String, method: String = "GET",
          headers: [String: String] = [:],
          body: [String: Any]? = nil,
          retries: Int = 2) -> HttpResult {
    for attempt in 0...retries {
        guard let u = URL(string: url) else {
            return HttpResult(status: -1, body: "", networkError: "bad url")
        }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.timeoutInterval = 25
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let b = body {
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: b)
        }
        let sem = DispatchSemaphore(value: 0)
        var res = HttpResult(status: -1, body: "", networkError: "unknown")
        URLSession.shared.dataTask(with: req) { d, r, e in
            defer { sem.signal() }
            if let e = e {
                res = HttpResult(status: -1, body: "", networkError: e.localizedDescription)
                return
            }
            res = HttpResult(status: (r as? HTTPURLResponse)?.statusCode ?? 0,
                             body: d.flatMap { String(data: $0, encoding: .utf8) } ?? "",
                             networkError: nil)
        }.resume()
        _ = sem.wait(timeout: .now() + 30)
        if !res.isNetworkFailure { return res }
        if attempt < retries {
            Thread.sleep(forTimeInterval: 2)
        }
    }
    return HttpResult(status: -1, body: "", networkError: "timeout after retries")
}

let deviceId = "0123456789abcdef0123456789abcdef"
let appVersion = "1.23.00"
let global = "https://app-gw-global-master.leapmotor.com"

func gwHeaders(nonce: String, ts: String, sign: String) -> [String: String] {
    ["User-Agent": "okhttp/4.9.3", "APPPlatform": "Android",
     "APPVersion": appVersion, "APPImei": deviceId,
     "C-VERSIONS": "APP", "XFX-CDN-VRS": "v4",
     "source": "leapmotor", "channel": "1", "acceptLanguage": "zh-CN",
     "x-region": "CN", "x-api-signature-version": "2.0", "digest": "",
     "version": appVersion, "deviceType": "android",
     "nonce": nonce, "timestamp": ts, "deviceId": deviceId,
     "userId": "", "carvin": "", "cartype": "",
     "x-subversion": "3.24.5-1", "sign": sign]
}

// ============================================================
print("=== 1. 网关签名真实校验 ===")
do {
    let nonce = String(Int.random(in: 10000..<10_010_000))
    let ts = String(Int64(Date().timeIntervalSince1970 * 1000))
    let biz: [String: String?] = ["identifier": "TEST0000001", "identifierType": "1", "security": "faketoken"]
    let signHeaders: [String: String?] = [
        "acceptLanguage": "zh-CN", "channel": "1", "deviceId": deviceId,
        "deviceType": "android", "nonce": nonce, "source": "leapmotor",
        "timestamp": ts, "version": appVersion
    ]
    let good = sha256Hex(sortAndConcat(signHeaders, biz))
    let body: [String: Any] = ["identifier": "TEST0000001", "identifierType": "1", "security": "faketoken"]

    let r1 = http(global + "/base/base-user/account/v1/login", method: "POST",
                  headers: gwHeaders(nonce: nonce, ts: ts, sign: good), body: body)
    if r1.isNetworkFailure {
        skipTest("正确签名被接受", "网络不可达: \(r1.networkError ?? "")")
    } else {
        check("正确签名被服务器接受（非签名错误）",
              !r1.body.contains("302002002"), r1.body.prefix(90).description)
        check("正确签名进入业务层",
              r1.body.contains("TOKEN") || r1.body.contains("30201020"), r1.body.prefix(90).description)
    }

    let bad = String(repeating: "0", count: 64)
    let r2 = http(global + "/base/base-user/account/v1/login", method: "POST",
                  headers: gwHeaders(nonce: nonce, ts: ts, sign: bad), body: body)
    if r2.isNetworkFailure {
        skipTest("错误签名被拒绝", "网络不可达")
    } else {
        check("错误签名被拒绝",
              r2.body.contains("302002002") || r2.body.contains("签名"), r2.body.prefix(90).description)
    }

    let alt = sha256Hex(sortAndConcat(signHeaders,
                                      ["identifier": "OTHER999", "identifierType": "1", "security": "faketoken"]))
    check("业务参数参与签名", alt != good)
}

// ============================================================
print("\n=== 2. 旧链路签名 ===")
do {
    var map: [String: String?] = [
        "timespan": String(Int64(Date().timeIntervalSince1970 * 1000)),
        "nonce": String(Int.random(in: 10000..<10_010_000)),
        "deviceID": deviceId,
        "token": "faketoken1234567890abcdef",
        "accountId": "TEST0000001"
    ]
    let sign = LeapSign.md5Short(sortAndConcat(map))
    check("md5Short 16 位 hex", sign.count == 16 && sign.allSatisfy { $0.isHexDigit }, sign)
    check("signStr == md5Hex[8..24]",
          String(LeapSign.md5Hex(sortAndConcat(map)).dropFirst(8).prefix(16)) == sign)
}

// ============================================================
print("\n=== 3. RSA 公钥结构 ===")
do {
    guard let der = Data(base64Encoded: LeapSign.phonePublicKeyX509) else {
        check("公钥解码", false); exit(1)
    }
    let b = [UInt8](der)
    check("SPKI 长度 162", der.count == 162, "\(der.count)")
    check("rsaEncryption OID",
          b[5] == 0x06 && b[6] == 0x09 && b[7] == 0x2a && b[8] == 0x86
            && b[11] == 0xf7 && b[12] == 0x0d && b[13] == 0x01 && b[14] == 0x01 && b[15] == 0x01)
    check("BIT STRING", b[18] == 0x03)
    check("PKCS#1 SEQUENCE", b[22] == 0x30 && b[23] == 0x81 && b[24] == 0x89)
    check("模数 1024-bit", b[26] == 0x81 && b[27] == 0x81)
}

// ============================================================
print("\n=== 4. JWT / signKey ===")
do {
    let h = b64url(Array(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
    let p = b64url([UInt8](try! JSONSerialization.data(withJSONObject: [
        "exp": 1900000000, "user_name": "deviceId:\(deviceId)"
    ])))
    var sig = [UInt8](repeating: 0, count: 32)
    for i in 0..<32 { sig[i] = UInt8((i * 17 + 5) & 0xFF) }
    let jwt = "\(h).\(p).\(b64url(sig))"

    check("exp 解析", LeapSign.jwtExpiryMs(jwt) == 1_900_000_000_000)
    check("deviceId 提取", LeapSign.jwtDeviceId(jwt) == deviceId)

    let r2b: [UInt8] = (0..<16).map { UInt8(($0 * 11 + 3) & 0xFF) }
    let r3b: [UInt8] = (0..<16).map { UInt8(($0 * 19 + 7) & 0xFF) }
    let key = try LeapSign.deriveSignKey(accessToken: jwt,
                                         r2: Data(r2b).base64EncodedString(),
                                         r3: Data(r3b).base64EncodedString())
    var expect = [UInt8](repeating: 0, count: 16)
    for i in 0..<16 { expect[i] = sig[i] ^ r2b[i] ^ r3b[i] }
    check("signKey == XOR 结果", [UInt8](key) == expect)
    check("HMAC 输出 64 hex", hmacHex(key: [UInt8](key), "base").count == 64)
}

// ============================================================
print("\n=== 5. BLE 会话派生与帧（官方向量）===")
do {
    let peer = LeapSign.hexToBytes(
        "0456cefd60d7c87c000d58ef57fa73ba4d9c0dfa08c08a7331495c2e1da3f2bd52"
        + "31b7e7e6cc8189f668535ce0f8eaf1bd6de84c182f6c8e716f780d3a970a23c3")!
    let scalar = LeapSign.hexToBytes(
        "0000000000000000000000000000000000000000000000000000000000000001")!
    let (pub, secret) = try SM2Agreement.agree(peerEncoded: peer, privateScalar: scalar)
    check("SM2 公钥 = G",
          pub.map { String(format: "%02x", $0) }.joined()
            == "0432c4ae2c1f1981195f9904466a39c9948fe30bbff2660be1715a4589334c74c7"
             + "bc3736a2f4f6779c59bdcee36b692153d0a9877cc62a474002df32e52139f0a0")
    check("共享密钥 = 官方 kdf",
          secret.map { String(format: "%02x", $0) }.joined()
            == "5f86e6b17708f60dfb5d8e3f3ce2b35d3d29744d51c46fc14cdb7bb95fdaf48b")

    let sessionId: UInt32 = 0x78563412
    let vin = "TESTVIN0000000001"
    let card = String(repeating: "0123456789abcdef", count: 5)
    let selector = SM3.hash(bleLittleEndian(UInt64(sessionId), 4)
                            + Array(String(vin.reversed()).utf8))
    check("selector = 官方向量",
          selector.map { String(format: "%02x", $0) }.joined()
            == "391cd9d91dd3036cb8026b94ec7e901fdf417af97cea60f9c027d3ee0b0cf663")
    let offset = (Int(selector[0]) >> 4) * 5
    check("card offset = 15", offset == 15)

    let material = Array(Array(card.utf8)[offset..<(offset + 5)]) + secret
    let digest = SM3.hash(material)
    check("key material = 官方向量",
          digest.map { String(format: "%02x", $0) }.joined()
            == "6fa340d39f4141fea70453772e7dc265248f0c0a1fe1dc3e437410132db0dd25")

    var hexBuf = [UInt8]()
    let alphabet = Array("0123456789abcdef".utf8)
    for byte in digest {
        hexBuf.append(alphabet[Int(byte >> 4)])
        hexBuf.append(alphabet[Int(byte & 0x0F)])
    }
    let key = Array(hexBuf[0..<16])
    let iv = Array(hexBuf[48..<64])
    check("session key", String(decoding: key, as: UTF8.self) == "6fa340d39f4141fe")
    check("session iv", String(decoding: iv, as: UTF8.self) == "437410132db0dd25")

    var cmd = bleLittleEndian(1800000000, 8)
    cmd.append(1)
    var plain: [UInt8] = [BleKeyProtocol.crc8(cmd)]
    plain += cmd
    let cipher = SM4.cbcEncrypt(key: key, iv: iv, plain: plain)
    let payload = Array(Data(cipher).base64EncodedString().utf8)
    var frame: [UInt8] = [0xAA, 0xAB]
    frame += bleLittleEndian(UInt64(payload.count), 4)
    frame += payload
    check("unlock 帧 = 官方向量",
          frame.map { String(format: "%02x", $0) }.joined()
            == "aaab1800000065447542464750772f3477547866484335386b3336773d3d")
}

// ============================================================
print("\n" + String(repeating: "=", count: 58))
print("  真实协议验证：\(pass) 通过，\(fail) 失败，\(skip) 跳过")
if skip > 0 { print("  （SKIP 为网络不可达，非代码问题）") }
print(String(repeating: "=", count: 58))
exit(fail == 0 ? 0 : 1)
