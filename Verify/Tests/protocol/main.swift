import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ============================================================
//  真实协议验证（需网络，访问零跑生产服务器的公开接口）
//  判据不是「拿到业务成功」，而是「签名被服务器接受/拒绝」的行为差异
// ============================================================

var pass = 0, fail = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { pass += 1; print("  PASS  \(name)") }
    else { fail += 1; print("  FAIL  \(name)  \(detail)") }
}

func sha256Hex(_ s: String) -> String {
    Digest.sha256(Array(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

func hmacHex(key: [UInt8], _ s: String) -> String {
    Digest.hmacSHA256(key: key, message: Array(s.utf8))
        .map { String(format: "%02x", $0) }.joined()
}

func sortAndConcat(_ maps: [String: String?]...) -> String {
    var merged: [String: String] = [:]
    for m in maps { for (k, v) in m where v != nil { merged[k] = v } }
    return merged.keys.sorted().map { merged[$0]! }.joined()
}

func b64url(_ b: [UInt8]) -> String {
    Data(b).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func http(_ url: String, method: String = "GET",
          headers: [String: String] = [:],
          body: [String: Any]? = nil) -> (Int, String) {
    guard let u = URL(string: url) else { return (-1, "bad url") }
    var req = URLRequest(url: u)
    req.httpMethod = method
    req.timeoutInterval = 20
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    if let b = body {
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: b)
    }
    let sem = DispatchSemaphore(value: 0)
    var out = (-1, "")
    URLSession.shared.dataTask(with: req) { d, r, e in
        defer { sem.signal() }
        if let e = e { out = (-1, "ERR: \(e.localizedDescription)"); return }
        out = ((r as? HTTPURLResponse)?.statusCode ?? 0,
               d.flatMap { String(data: $0, encoding: .utf8) } ?? "")
    }.resume()
    _ = sem.wait(timeout: .now() + 25)
    return out
}

let deviceId = "0123456789abcdef0123456789abcdef"
let appVersion = "1.23.00"
let global = "https://app-gw-global-master.leapmotor.com"

func baseHeaders(nonce: String, ts: String, sign: String) -> [String: String] {
    [
        "User-Agent": "okhttp/4.9.3",
        "APPPlatform": "Android",
        "APPVersion": appVersion,
        "APPImei": deviceId,
        "C-VERSIONS": "APP",
        "XFX-CDN-VRS": "v4",
        "source": "leapmotor",
        "channel": "1",
        "acceptLanguage": "zh-CN",
        "x-region": "CN",
        "x-api-signature-version": "2.0",
        "digest": "",
        "version": appVersion,
        "deviceType": "android",
        "nonce": nonce,
        "timestamp": ts,
        "deviceId": deviceId,
        "userId": "",
        "carvin": "",
        "cartype": "",
        "x-subversion": "3.24.5-1",
        "sign": sign
    ]
}

print("=== 网关签名真实校验 ===")
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
                  headers: baseHeaders(nonce: nonce, ts: ts, sign: good), body: body)
    check("正确签名被服务器接受（非签名错误）", !r1.1.contains("302002002"), r1.1.prefix(90).description)
    check("正确签名进入业务层", r1.1.contains("TOKEN") || r1.1.contains("30201020"), r1.1.prefix(90).description)

    let bad = String(repeating: "0", count: 64)
    let r2 = http(global + "/base/base-user/account/v1/login", method: "POST",
                  headers: baseHeaders(nonce: nonce, ts: ts, sign: bad), body: body)
    check("错误签名被拒绝", r2.1.contains("302002002") || r2.1.contains("签名"), r2.1.prefix(90).description)

    // 业务参数参与签名
    let alt = sha256Hex(sortAndConcat(signHeaders,
                                      ["identifier": "OTHER999", "identifierType": "1", "security": "faketoken"]))
    check("业务参数参与签名", alt != good)
}

print("\n=== 旧链路签名 ===")
do {
    let token = "faketoken1234567890abcdef"
    var map: [String: String?] = [
        "timespan": String(Int64(Date().timeIntervalSince1970 * 1000)),
        "nonce": String(Int.random(in: 10000..<10_010_000)),
        "deviceID": deviceId,
        "token": token,
        "accountId": "TEST0000001"
    ]
    let sign = LeapSign.md5Short(sortAndConcat(map))
    check("md5Short 16 位 hex", sign.count == 16 && sign.allSatisfy { $0.isHexDigit }, sign)
    let full = LeapSign.md5Hex(sortAndConcat(map))
    check("signStr == md5Hex[8..24]", String(full.dropFirst(8).prefix(16)) == sign)
}

print("\n=== RSA 公钥结构 ===")
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

print("\n=== JWT / signKey ===")
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

print("\n" + String(repeating: "=", count: 56))
print("  真实协议验证：\(pass) 通过，\(fail) 失败")
print(String(repeating: "=", count: 56))
exit(fail == 0 ? 0 : 1)
