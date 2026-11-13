// ============================================================
//  main.swift —— 算法自检（可在 Windows/Linux Swift 上直接运行）
//  只依赖 Foundation + CryptoKit(或自实现)，不涉及 UIKit/CoreBluetooth
//  运行：swift run  或 swiftc SM.swift Crypto.swift main.swift -o verify && ./verify
// ============================================================

import Foundation

var passCount = 0
var failCount = 0
var failures: [String] = []

func check(_ name: String, _ got: String, _ expect: String) {
    if got.lowercased() == expect.lowercased() {
        passCount += 1
        print("  ✅ \(name)")
    } else {
        failCount += 1
        failures.append("\(name)\n     got:    \(got)\n     expect: \(expect)")
        print("  ❌ \(name)")
        print("     got:    \(got)")
        print("     expect: \(expect)")
    }
}

func checkInt(_ name: String, _ got: Int, _ expect: Int) {
    check(name, "\(got)", "\(expect)")
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

// ============================================================ SM3

print("=== SM3 标准向量（GB/T 32905-2016）===")
check("SM3(\"\")",
      hex(SM3.hash([])),
      "1ab21d8355cfa17f8e61194831e81a8f22bec8c728fefb747ed035eb5082aa2b")
check("SM3(\"abc\")",
      hex(SM3.hash(Array("abc".utf8))),
      "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0")
check("SM3(\"abcd\"x16)",
      hex(SM3.hash(Array(String(repeating: "abcd", count: 16).utf8))),
      "debe9ff92275b8a138604889c18e5a4d6fdb70e5387e5765293dcba39c0c5732")

// ============================================================ SM4

print("\n=== SM4 标准向量（GB/T 32907-2016）===")
let sm4Key = LeapSign.hexToBytes("0123456789abcdeffedcba9876543210")!
let sm4Plain = LeapSign.hexToBytes("0123456789abcdeffedcba9876543210")!
check("SM4 单块加密",
      hex(SM4.encryptBlock(sm4Key, sm4Plain)),
      "681edf34d206965e86b3e94f536e4246")

// CBC 往返
let cbcKey = Array("0123456789abcdef".utf8)
let cbcIv = Array("fedcba9876543210".utf8)
let message = Array("hello sm4 world".utf8)
do {
    let enc = SM4.cbcEncrypt(key: cbcKey, iv: cbcIv, plain: message)
    let dec = try SM4.cbcDecrypt(key: cbcKey, iv: cbcIv, cipher: enc)
    check("SM4-CBC 往返", String(decoding: dec, as: UTF8.self), "hello sm4 world")
    checkInt("SM4-CBC 密文长度", enc.count, 16)
} catch {
    check("SM4-CBC 往返", "throw \(error)", "hello sm4 world")
}

// ============================================================ AES（CommonCrypto 替代：Windows 无 CommonCrypto，跳过）
// Windows 上没有 CommonCrypto，AES 部分只在 iOS 构建时验证。

// ============================================================ MD5 / SHA256 / HMAC

print("\n=== 哈希与签名 ===")
check("MD5(\"abc\")",
      LeapSign.md5Hex("abc"),
      "900150983cd24fb0d6963f7d28e17f72")
check("md5Short(\"abc\")（取 [8,24)）",
      LeapSign.md5Short("abc"),
      LeapSign.md5Hex("abc").dropFirst(8).prefix(16).description.lowercased())

check("SHA256(\"abc\")",
      LeapSign.sha256Hex("abc"),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

// HMAC-SHA256 RFC 4231 Test Case 2
let hmacKey = Data([UInt8](repeating: 0x0b, count: 20))
check("HMAC-SHA256（RFC 4231 TC2）",
      LeapSign.hmacSHA256Hex(key: hmacKey, "what do ya want for nothing?"),
      "6a055afb1295ef9de35605919cbb8f86f51ee183901f001e6dc53ec3d2480ba9")

// ============================================================ sortAndConcat

print("\n=== 签名拼接（sortAndConcat）===")
check("键排序、nil 跳过、空串保留",
      LeapSign.sortAndConcat(["b": "2", "a": "1", "c": nil, "d": ""]),
      "12")

// ============================================================ SM2 曲线运算

print("\n=== Montgomery 基础算术诊断 ===")
do {
    // toMont/fromMont 往返
    let gxLimb = SM2Curve.gx
    let rt = fromMont(toMont(gxLimb, SM2Curve.p), SM2Curve.p)
    check("toMont/fromMont 往返", "\(rt == gxLimb)", "true")

    // montMul(1,1) 应等于 1 的 Montgomery 表示
    let one = limb(1)
    let oneM = toMont(one, SM2Curve.p)
    let prod = montMul(oneM, oneM, SM2Curve.p)
    check("montMul(1R,1R) == 1R", "\(fromMont(prod, SM2Curve.p) == limb(1))", "true")

    // montInverse
    let inv = montInverse(oneM, SM2Curve.p)
    check("montInverse(1R) == 1R", "\(fromMont(inv, SM2Curve.p) == limb(1))", "true")

    // G 的 affine 还原（Z=1）
    let g = JPoint(x: toMont(gxLimb, SM2Curve.p),
                   y: toMont(SM2Curve.gy, SM2Curve.p), z: SM2Curve.p.one)
    if let aff = g.affine {
        check("G.affine.x == Gx", "\(aff.0 == toMont(gxLimb, SM2Curve.p))", "true")
        check("G.affine.y == Gy", "\(aff.1 == toMont(SM2Curve.gy, SM2Curve.p))", "true")
    } else {
        check("G.affine", "nil", "非 nil")
    }

    // pointDouble(G) 与 affine 公式对比
    let g2 = pointDouble(g)
    if let a2 = g2.affine {
        let x2 = fromMont(a2.0, SM2Curve.p)
        print("    pointDouble(G).x = \(limbToBytes(x2).map { String(format: "%02x", $0) }.joined())")
        print("    期望 2G.x        = 56cefd60d7c87c000d58ef57fa73ba4d9c0dfa08c08a7331495c2e1da3f2bd52")
    }
}

    // 单步：∞ + G
    let gPoint = JPoint(x: toMont(SM2Curve.gx, SM2Curve.p),
                        y: toMont(SM2Curve.gy, SM2Curve.p), z: SM2Curve.p.one)
    let inf = JPoint.infinity
    let sum0 = pointAdd(inf, gPoint)
    if let a0 = sum0.affine {
        print("    (∞+G).x (plain) = " + limbToBytes(fromMont(a0.0, SM2Curve.p)).map { String(format: "%02x", $0) }.joined())
        print("    期望 Gx         = 32c4ae2c1f1981195f9904466a39c9948fe30bbff2660be1715a4589334c74c7")
    } else {
        print("    (∞+G) 为无穷远 —— 错误")
    }
    print("    ∞ isInfinity = \(inf.isInfinity)")
    print("    sum0.z == p.one ? \(limbCmp(sum0.z, SM2Curve.p.one) == 0)")

    // 单步：pointMultiply 1
    let k1 = LeapSign.hexToBytes("0000000000000000000000000000000000000000000000000000000000000001")!
    let pm = pointMultiply(k1, gPoint)
    print("    pointMultiply(1,G).z == p.one ? \(limbCmp(pm.z, SM2Curve.p.one) == 0)")
    print("    pointMultiply(1,G).isInfinity = \(pm.isInfinity)")
    print("    pointDouble(G).isInfinity = \(pointDouble(gPoint).isInfinity)")

print("\n=== SM2 曲线运算 ===")

// G 必须在曲线上
do {
    let decoded = try SM2Point.decode(LeapSign.hexToBytes(
        "0432c4ae2c1f1981195f9904466a39c9948fe30bbff2660be1715a4589334c74c7"
        + "bc3736a2f4f6779c59bdcee36b692153d0a9877cc62a474002df32e52139f0a0")!)
    print("  ✅ G 在曲线上（decode 成功）")
    passCount += 1

    // G*1 应还原 G
    let g = JPoint(x: decoded.0, y: decoded.1, z: SM2Curve.p.one)
    let scalar1 = LeapSign.hexToBytes("0000000000000000000000000000000000000000000000000000000000000001")!
    let p1 = pointMultiply(scalar1, g)
    let encoded1 = SM2Point.encodeUncompressed(p1.affine!)
    check("1·G == G",
          hex(encoded1),
          "0432c4ae2c1f1981195f9904466a39c9948fe30bbff2660be1715a4589334c74c7"
          + "bc3736a2f4f6779c59bdcee36b692153d0a9877cc62a474002df32e52139f0a0")

    // G*2 与官方向量比对
    let scalar2 = LeapSign.hexToBytes("0000000000000000000000000000000000000000000000000000000000000002")!
    let p2 = pointMultiply(scalar2, g)
    check("2·G（对齐 node-crypto）",
          hex(SM2Point.encodeUncompressed(p2.affine!)),
          "0456cefd60d7c87c000d58ef57fa73ba4d9c0dfa08c08a7331495c2e1da3f2bd52"
          + "31b7e7e6cc8189f668535ce0f8eaf1bd6de84c182f6c8e716f780d3a970a23c3")

    // 大标量：(k·G) + ((n-k)·G) == 无穷远点
    let kHex = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    let k = LeapSign.hexToBytes(kHex)!
    // n - k
    let nLimb = SM2Curve.n.m
    let kLimb = bytesToLimb(k)
    let nMinusK = subMod(nLimb, kLimb, SM2Curve.n)
    let pA = pointMultiply(kLimb, g)
    let pB = pointMultiply(nMinusK, g)
    let sum = pointAdd(pA, pB)
    check("k·G + (n-k)·G == ∞", sum.isInfinity ? "true" : "false", "true")

    // 压缩点解码（与未压缩一致）
    let full = SM2Point.encodeUncompressed(decoded)
    var compressed = [UInt8](repeating: 0, count: 33)
    compressed[0] = (full[64] & 1 == 1) ? 0x03 : 0x02
    for i in 0..<32 { compressed[i + 1] = full[i + 1] }
    let fromCompressed = try SM2Point.decode(compressed)
    check("压缩点解码 == 未压缩",
          hex(SM2Point.encodeUncompressed(fromCompressed)),
          hex(full))
} catch {
    print("  ❌ SM2 点解码异常: \(error)")
    failCount += 1
}

// ============================================================ SM2 密钥协商（官方向量）

print("\n=== SM2 密钥协商（官方 sm2-vectors）===")
do {
    let peerHex = "0456cefd60d7c87c000d58ef57fa73ba4d9c0dfa08c08a7331495c2e1da3f2bd52"
        + "31b7e7e6cc8189f668535ce0f8eaf1bd6de84c182f6c8e716f780d3a970a23c3"
    let peerBytes = LeapSign.hexToBytes(peerHex)!
    let scalar = LeapSign.hexToBytes(
        "0000000000000000000000000000000000000000000000000000000000000001")!
    let (pub, secret) = try SM2Agreement.agree(peerEncoded: peerBytes, privateScalar: scalar)
    check("agree 返回公钥（1·G）",
          hex(pub),
          "0432c4ae2c1f1981195f9904466a39c9948fe30bbff2660be1715a4589334c74c7"
          + "bc3736a2f4f6779c59bdcee36b692153d0a9877cc62a474002df32e52139f0a0")
    check("共享密钥（SM3）",
          hex(secret),
          "5f86e6b17708f60dfb5d8e3f3ce2b35d3d29744d51c46fc14cdb7bb95fdaf48b")
} catch {
    print("  ❌ 协商异常: \(error)")
    failCount += 1
}

// ============================================================ BLE 帧

print("\n=== BLE 协议帧（官方 passive-vectors）===")

// CRC8 校验（官方向量 off8 配置的命令体）
let ts: UInt64 = 1800000000
let body = bleLittleEndian(ts, 8) + [3] + LeapSign.hexToBytes("38c80008100000")!
checkInt("CRC8(off8 命令体)", Int(BleKeyProtocol.crc8(body)), 0xd1)

// 分包
let frame = [UInt8](repeating: 0xAA, count: 300)
checkInt("MTU 23 → 每包 20 字节", BleKeyProtocol.chunkLimit(mtu: 23), 20)
checkInt("MTU 247 → 每包 160（上限）", BleKeyProtocol.chunkLimit(mtu: 247), 160)
checkInt("300 字节 / 20 = 15 包", BleKeyProtocol.chunks(frame, mtu: 23).count, 15)

// 帧解码器
let decoder = BleFrameDecoder()
// aaab + len=2 + "aa"
var testFrame: [UInt8] = [0xAA, 0xAB]
testFrame += bleLittleEndian(2, 4)
testFrame += [0x61, 0x61]
let decoded = decoder.append(testFrame)
checkInt("解码 AAAB 帧数量", decoded.count, 1)
if let first = decoded.first {
    checkInt("帧类型", first.type.rawValue, 0xAB)
    check("载荷", hex(first.payload), "6161")
}

// 证书摘要稳定性
let cert = BleKeyCertificate(ecdhPublicKey: "test-key", keyType: 0,
                             passwordCard: String(repeating: "0123456789abcdef", count: 5),
                             plainText: "v1;acc;dev;VIN123456;1;2", signResult: "c2ln",
                             vin: "TESTVIN0000000001")
checkInt("证书摘要长度", BleKeyProtocol.certificateDigest(cert).count, 32)
check("指纹稳定性",
      BleKeyProtocol.fingerprint(cert),
      BleKeyProtocol.fingerprint(cert))

// 标定文本
let cal = BleCalibration(distanceCalibration: 56, coefficientHundredths: 200,
                         unlockCalibration: 8, lockCalibration: 16)
check("标定文本", cal.protocolText, "56;2.00;08;16")
check("标定字节", hex(cal.encoded), "38c8000810")
check("C16 默认", BleCalibration.defaultForModel("C16").protocolText, "69;1.00;04;21")
check("普通默认", BleCalibration.defaultForModel("C11").protocolText, "56;2.00;08;16")

// 解析往返
if let parsed = BleCalibration.parse("56;2.00;08;16") {
    check("标定解析往返", parsed.protocolText, "56;2.00;08;16")
} else {
    check("标定解析往返", "nil", "56;2.00;08;16")
}

// 被动配置 flags：reconnectFields = 标定5字节 + 4 flag
let off8 = BlePassiveConfiguration(enabled: false, autoUnlock: false, autoLock: false,
                                   buttonEnabled: false, calibration: cal)
check("off8 reconnectFields（2 档）", hex(off8.reconnectFields(supportsButton: false)), "38c800081000000000")
let manual9 = BlePassiveConfiguration(enabled: true, autoUnlock: false, autoLock: false,
                                      buttonEnabled: false, calibration: cal)
check("manual9 reconnectFields", hex(manual9.reconnectFields(supportsButton: true)), "38c800081001000001")

// ============================================================ 星期编解码

print("\n=== 星期编解码 ===")
check("工作日掩码", LeapDays.toVehicleMask(Set(1...5)), "1,1,1,1,1,0,0")
check("全部解析", "\(LeapDays.parseToDaySet("1,1,1,1,1,0,0").sorted())", "\([1, 2, 3, 4, 5])")
check("数字列表解析", "\(LeapDays.parseToDaySet("1,2,3,4,5").sorted())", "\([1, 2, 3, 4, 5])")
checkInt("周日映射为 0", LeapDays.toScheduleDaysIntList(Set(1...7)).last!, 6)
check("描述-工作日", LeapDays.summary(Set(1...5)), "工作日")
check("描述-周末", LeapDays.summary(Set([6, 7])), "周末")
check("描述-每天", LeapDays.summary(Set(1...7)), "每天")

// ============================================================ 指令表

print("\n=== 控车指令 ===")
check("上锁", "\(LeapCommands.lock.cmdid)|\(LeapCommands.lock.state)", #"110|{"value":"lock"}"#)
check("解锁", "\(LeapCommands.unlock.cmdid)|\(LeapCommands.unlock.state)", #"110|{"value":"unlock"}"#)
check("开后备箱", "\(LeapCommands.trunkOpen.cmdid)|\(LeapCommands.trunkOpen.state)",
      #"130|{"value":"true"}"#)
check("鸣笛", "\(LeapCommands.horn.cmdid)|\(LeapCommands.horn.state)", #"120|{"value":"true"}"#)
check("哨兵开", "\(LeapCommands.sentryOn.cmdid)|\(LeapCommands.sentryOn.state)",
      #"400|{"operation":"on"}"#)
check("充电开", "\(LeapCommands.chargeStart.cmdid)|\(LeapCommands.chargeStart.state)",
      #"193|{"value":"start"}"#)
check("座椅加热1档", "\(LeapCommands.seatHeating("left_front", level: 1).cmdid)|\(LeapCommands.seatHeating("left_front", level: 1).state)",
      #"301|{"position":"left_front","level":"1"}"#)
check("方向盘加热2档", "\(LeapCommands.steeringWheelHeating(2).cmdid)|\(LeapCommands.steeringWheelHeating(2).state)",
      #"320|{"level":"2"}"#)
check("空调18度（制冷）", LeapCommands.ac(18).state.contains("\"mode\":\"cold\"") ? "cold" : "?", "cold")
check("空调30度（制热）", LeapCommands.ac(30).state.contains("\"mode\":\"hot\"") ? "hot" : "?", "hot")

// ============================================================ 信号解码

print("\n=== 信号表解码 ===")
let rawSignal: [String: Any] = [
    "1204": 78, "100003": 77.6, "3260": 412, "1318": 12345,
    "3235": 45, "1149": 1, "1938": 1, "2646": 2.4,
    "1298": 1, "3636": 0, "1693": 0
]
let decodedSignal = LeapSignalTable.decode(rawSignal)
checkInt("字段数", decodedSignal.count, 11)
checkInt("SOC 解码", decodedSignal["soc"] as? Int ?? -1, 78)
checkInt("续航解码", decodedSignal["expectedMileage"] as? Int ?? -1, 412)
checkInt("总里程解码", decodedSignal["totalMileage"] as? Int ?? -1, 12345)
checkInt("油量解码", decodedSignal["fuelSoc"] as? Int ?? -1, 45)

let status = LeapStatus(raw: decodedSignal)
checkInt("电量百分比（preciseSoc 向上取整）", status.socPercent ?? -1, 78)
check("充电状态", status.chargeLabel, "充电中")
checkInt("是否充电中", status.isCharging ? 1 : 0, 1)
checkInt("是否增程", status.isReev ? 1 : 0, 1)
check("可续驶程", status.remainingRange ?? "nil", "412")
checkInt("已上锁", status.isLocked == true ? 1 : 0, 1)
checkInt("哨兵关闭", status.sentryMode == false ? 1 : 0, 1)
checkInt("车门项数", status.doors.count, 0)
checkInt("车窗项数", status.windows.count, 1)

// ============================================================ BLE 端到端（完整帧字节比对）

print("\n=== BLE 端到端：完整帧构造与回执解码 ===")
do {
    // 用官方 sm2-vectors 的会话参数构造完整会话
    // peer = G*2, privateScalar = 1  →  local = G, shared = 官方 kdf
    let peerBytes = LeapSign.hexToBytes(
        "0456cefd60d7c87c000d58ef57fa73ba4d9c0dfa08c08a7331495c2e1da3f2bd52"
        + "31b7e7e6cc8189f668535ce0f8eaf1bd6de84c182f6c8e716f780d3a970a23c3")!
    let scalar1 = LeapSign.hexToBytes(
        "0000000000000000000000000000000000000000000000000000000000000001")!
    let (pubKey, sharedSecret) = try SM2Agreement.agree(peerEncoded: peerBytes, privateScalar: scalar1)

    // 手工走 deriveSession 的等价流程，验证 key/iv 与官方一致
    let sessionId: UInt32 = 0x78563412
    let vin = "TESTVIN0000000001"
    let card = String(repeating: "0123456789abcdef", count: 5)

    let reversedVin = String(vin.reversed())
    let selector = SM3.hash(bleLittleEndian(UInt64(sessionId), 4) + Array(reversedVin.utf8))
    check("selector", hex(selector),
          "391cd9d91dd3036cb8026b94ec7e901fdf417af97cea60f9c027d3ee0b0cf663")
    let offset = (Int(selector[0]) >> 4) * 5
    checkInt("card offset", offset, 15)

    let cardBytes = Array(card.utf8)
    let material = Array(cardBytes[offset..<(offset + 5)]) + sharedSecret
    let digest = SM3.hash(material)
    check("derived key material", hex(digest),
          "6fa340d39f4141fea70453772e7dc265248f0c0a1fe1dc3e437410132db0dd25")

    let alphabet = Array("0123456789abcdef".utf8)
    var hexBuf = [UInt8]()
    for byte in digest {
        hexBuf.append(alphabet[Int(byte >> 4)])
        hexBuf.append(alphabet[Int(byte & 0x0F)])
    }
    let sessionKey = Array(hexBuf[0..<16])
    let sessionIv = Array(hexBuf[48..<64])
    check("session key", String(decoding: sessionKey, as: UTF8.self), "6fa340d39f4141fe")
    check("session iv", String(decoding: sessionIv, as: UTF8.self), "437410132db0dd25")

    // 控车帧（timestamp = 1800000000，unlock=1）
    func buildCommandFrame(_ cmdId: UInt8, _ tsValue: UInt64) -> [UInt8] {
        var cmd = bleLittleEndian(tsValue, 8)
        cmd.append(cmdId)
        var plain: [UInt8] = [BleKeyProtocol.crc8(cmd)]
        plain += cmd
        let cipher = SM4.cbcEncrypt(key: sessionKey, iv: sessionIv, plain: plain)
        let payload = Array(Data(cipher).base64EncodedString().utf8)
        var frame: [UInt8] = [0xAA, 0xAB]
        frame += bleLittleEndian(UInt64(payload.count), 4)
        frame += payload
        return frame
    }

    check("unlock 帧", hex(buildCommandFrame(1, 1800000000)),
          "aaab1800000065447542464750772f3477547866484335386b3336773d3d")
    check("lock 帧", hex(buildCommandFrame(2, 1800000000)),
          "aaab18000000594c565a4144765a4155776d6433354a394855584e773d3d")

    // 回执解码（用官方帧）
    let session = BleKeySession(sessionId: sessionId,
                                publicKey: pubKey,
                                key: sessionKey, iv: sessionIv,
                                certificateFingerprint: [UInt8](repeating: 0, count: 32),
                                keyType: 1)
    let decoder2 = BleFrameDecoder()

    // 官方回执：0;locked;
    let replyAuth = LeapSign.hexToBytes("aaab180000005a6a6a2b4c4b686d627a487135704b74454d643633673d3d")!
    if let f = decoder2.append(replyAuth).first, let resp = try? session.decodeResponse(f) {
        if case .authenticated(let state) = resp {
            check("回执 0;locked; 解码", state, "locked")
        } else {
            check("回执 0;locked; 解码", "\(resp)", "authenticated")
        }
    } else {
        check("回执 0;locked; 解码", "decode failed", "locked")
    }

    // 官方回执：2;3;00;（配置确认）
    let replyCfg = LeapSign.hexToBytes("aaab18000000574e444634653936644c36785a554e69672b634131513d3d")!
    if let f = decoder2.append(replyCfg).first, let resp = try? session.decodeResponse(f) {
        check("回执 2;3;00; 配置确认", "\(resp.confirmsConfiguration)", "true")
    } else {
        check("回执 2;3;00; 配置确认", "decode failed", "true")
    }

    // 官方回执：0;;（空状态 → unknown）
    let replyEmpty = LeapSign.hexToBytes("aaab18000000726e6b436878633845583564777443465767634e52673d3d")!
    if let f = decoder2.append(replyEmpty).first, let resp = try? session.decodeResponse(f) {
        if case .unknown = resp {
            check("回执 0;; → unknown", "unknown", "unknown")
        } else {
            check("回执 0;; → unknown", "\(resp)", "unknown")
        }
    } else {
        check("回执 0;; → unknown", "decode failed", "unknown")
    }

    // 官方回执：1;1234abcd;（重连凭据）
    let replyCred = LeapSign.hexToBytes("aaab18000000523555335a59674c6961396c477564472b577a3070773d3d")!
    if let f = decoder2.append(replyCred).first, let resp = try? session.decodeResponse(f) {
        if case .reconnectCredential(let hexStr) = resp {
            check("回执 1;1234abcd; 重连凭据", hexStr, "1234abcd")
        } else {
            check("回执 1;1234abcd; 重连凭据", "\(resp)", "1234abcd")
        }
    } else {
        check("回执 1;1234abcd; 重连凭据", "decode failed", "1234abcd")
    }
}

// ============================================================ 报告

print("\n" + String(repeating: "=", count: 56))
if failCount == 0 {
    print("  全部通过：\(passCount) 项")
} else {
    print("  通过 \(passCount) 项，失败 \(failCount) 项")
    print("\n失败明细：")
    for f in failures { print("  · \(f)") }
}
print(String(repeating: "=", count: 56))

exit(failCount == 0 ? 0 : 1)
