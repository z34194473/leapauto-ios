//
//  SM.swift
//  国密算法纯 Swift 实现（SM2 / SM3 / SM4），零第三方依赖。
//
//  所有常量均由小端 8×UInt32 分肢精确给出，已用参考实现逐字节校验：
//    SM3("abc")        = 66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0
//    SM3("abcd"×16)    = debe9ff92275b8a138604889c18e5a4d6fdb70e5387e5765293dcba39c0c5732
//    SM4 单块           = 0123456789abcdeffedcba9876543210 -> 681edf34d206965e86b3e94f536e4246
//    SM2 点乘/Z A/协商 = 与 node-crypto 官方向量一致
//

import Foundation

#if canImport(Security)
import Security
#endif

enum LeapCryptoError: Error, LocalizedError {
    case badCiphertext
    case badPoint
    case badEncoding
    case notOnCurve
    case badCertificate
    case badToken
    case badPasswordCard

    var errorDescription: String? {
        switch self {
        case .badCiphertext: return "密文无效或解密失败"
        case .badPoint: return "SM2 协商点无效"
        case .badEncoding: return "SM2 公钥编码无效"
        case .notOnCurve: return "SM2 公钥不在曲线上"
        case .badCertificate: return "蓝牙证书无效"
        case .badToken: return "Token 长度不足，无法加密操作密码"
        case .badPasswordCard: return "蓝牙 passwordCard 无效"
        }
    }
}

// ============================================================ 256 位整数：8×UInt32 小端

typealias Limb8 = [UInt32]

@inline(__always)
func limb(_ value: UInt64) -> Limb8 {
    var out = [UInt32](repeating: 0, count: 8)
    out[0] = UInt32(truncatingIfNeeded: value)
    let hi = value >> 32
    if hi != 0 { out[1] = UInt32(truncatingIfNeeded: hi) }
    return out
}

@inline(__always)
func limbAdd(_ a: Limb8, _ b: Limb8) -> (Limb8, UInt32) {
    var out = [UInt32](repeating: 0, count: 8)
    var carry: UInt64 = 0
    for i in 0..<8 {
        let s = UInt64(a[i]) &+ UInt64(b[i]) &+ carry
        out[i] = UInt32(truncatingIfNeeded: s)
        carry = s >> 32
    }
    return (out, UInt32(truncatingIfNeeded: carry))
}

/// 相减并丢弃借位（补码语义，用于已知不借位或需要 wrap 的场景）
@inline(__always)
func limbSubWrap(_ a: Limb8, _ b: Limb8) -> Limb8 {
    var out = [UInt32](repeating: 0, count: 8)
    var borrow: UInt64 = 0
    for i in 0..<8 {
        let bi = UInt64(b[i]) &+ borrow
        let ai = UInt64(a[i])
        if ai >= bi {
            out[i] = UInt32(truncatingIfNeeded: ai &- bi)
            borrow = 0
        } else {
            out[i] = UInt32(truncatingIfNeeded: (ai &+ (1 << 32)) &- bi)
            borrow = 1
        }
    }
    return out
}

/// 带借位的相减
@inline(__always)
func limbSub(_ a: Limb8, _ b: Limb8) -> (Limb8, UInt32) {
    var out = [UInt32](repeating: 0, count: 8)
    var borrow: UInt64 = 0
    for i in 0..<8 {
        let bi = UInt64(b[i]) &+ borrow
        let ai = UInt64(a[i])
        if ai >= bi {
            out[i] = UInt32(truncatingIfNeeded: ai &- bi)
            borrow = 0
        } else {
            out[i] = UInt32(truncatingIfNeeded: (ai &+ (1 << 32)) &- bi)
            borrow = 1
        }
    }
    return (out, UInt32(truncatingIfNeeded: borrow))
}

@inline(__always)
func limbCmp(_ a: Limb8, _ b: Limb8) -> Int {
    var i = 7
    while i >= 0 {
        if a[i] != b[i] { return a[i] > b[i] ? 1 : -1 }
        i -= 1
    }
    return 0
}

@inline(__always)
func limbIsZero(_ a: Limb8) -> Bool {
    for x in a where x != 0 { return false }
    return true
}

// ============================================================ 模运算（CIOS Montgomery）

struct Modulus {
    let m: Limb8
    let n0: UInt32        // -m⁻¹ mod 2³²
    let r2: Limb8         // R² mod m
    let one: Limb8        // R mod m
    let minus2: Limb8     // m-2
}

@inline(__always)
func addMod(_ a: Limb8, _ b: Limb8, _ mod: Modulus) -> Limb8 {
    let (sum, carry) = limbAdd(a, b)
    if carry != 0 || limbCmp(sum, mod.m) >= 0 {
        return limbSubWrap(sum, mod.m)
    }
    return sum
}

@inline(__always)
func subMod(_ a: Limb8, _ b: Limb8, _ mod: Modulus) -> Limb8 {
    let (diff, borrow) = limbSub(a, b)
    if borrow == 0 { return diff }
    // diff 是 a-b+2²⁵⁶；再补 m 并丢掉进位即得 a-b+m
    let (res, carry) = limbAdd(diff, mod.m)
    if carry == 0 && limbCmp(res, mod.m) >= 0 {
        return limbSubWrap(res, mod.m)
    }
    return res
}

@inline(__always)
func dblMod(_ a: Limb8, _ mod: Modulus) -> Limb8 { addMod(a, a, mod) }

/// 乘以 1/2/3
@inline(__always)
func mulSmall(_ a: Limb8, _ k: UInt32, _ mod: Modulus) -> Limb8 {
    if k == 1 { return a }
    let twice = addMod(a, a, mod)
    if k == 2 { return twice }
    return addMod(twice, a, mod)
}

/// CIOS Montgomery 乘法：返回 a·b·R⁻¹ mod m
@inline(__always)
func montMul(_ a: Limb8, _ b: Limb8, _ mod: Modulus) -> Limb8 {
    var t = [UInt32](repeating: 0, count: 10)
    let mm = mod.m
    let n0 = mod.n0

    for i in 0..<8 {
        // 累加 a·b[i]
        var c: UInt64 = 0
        let bi = UInt64(b[i])
        for j in 0..<8 {
            let v = UInt64(t[j]) &+ UInt64(a[j]) &* bi &+ c
            t[j] = UInt32(truncatingIfNeeded: v)
            c = v >> 32
        }
        var v0 = UInt64(t[8]) &+ c
        t[8] = UInt32(truncatingIfNeeded: v0)
        t[9] = UInt32(truncatingIfNeeded: v0 >> 32)

        // 约化：t += m·(t[0]·n0 mod 2³²)，随后整字右移
        let u = t[0] &* n0
        var cy = (UInt64(t[0]) &+ UInt64(u) &* UInt64(mm[0])) >> 32
        for j in 1..<8 {
            let v = UInt64(t[j]) &+ UInt64(u) &* UInt64(mm[j]) &+ cy
            t[j - 1] = UInt32(truncatingIfNeeded: v)
            cy = v >> 32
        }
        v0 = UInt64(t[8]) &+ cy
        t[7] = UInt32(truncatingIfNeeded: v0)
        t[8] = UInt32(truncatingIfNeeded: UInt64(t[9]) &+ (v0 >> 32))
        t[9] = 0
    }

    var out = Array(t[0..<8])
    if t[8] != 0 || limbCmp(out, mm) >= 0 {
        out = limbSubWrap(out, mm)
    }
    return out
}

@inline(__always)
func toMont(_ a: Limb8, _ mod: Modulus) -> Limb8 { montMul(a, mod.r2, mod) }

@inline(__always)
func fromMont(_ a: Limb8, _ mod: Modulus) -> Limb8 { montMul(a, [1, 0, 0, 0, 0, 0, 0, 0], mod) }

/// Montgomery 域幂运算 base^exp（exp 为 Montgomery 域中的普通指数绝对值）
func montPow(_ base: Limb8, _ exp: Limb8, _ mod: Modulus) -> Limb8 {
    var result = mod.one
    var b = base
    for i in 0..<8 {
        var word = exp[i]
        var bit = 0
        while bit < 32 {
            if word & 1 == 1 { result = montMul(result, b, mod) }
            b = montMul(b, b, mod)
            word >>= 1
            bit += 1
        }
    }
    return result
}

/// Montgomery 域求逆 = a^(m-2)（m 为素数）
@inline(__always)
func montInverse(_ a: Limb8, _ mod: Modulus) -> Limb8 { montPow(a, mod.minus2, mod) }

/// 普通（非 Montgomery）模乘，用于模 n 的标量运算
func modMulNormal(_ a: Limb8, _ b: Limb8, _ mod: Modulus) -> Limb8 {
    var result = limb(0)
    var addend = a
    for wordIndex in 0..<8 {
        var word = b[wordIndex]
        for _ in 0..<32 {
            if word & 1 == 1 { result = addMod(result, addend, mod) }
            addend = addMod(addend, addend, mod)
            word >>= 1
        }
    }
    return result
}

// ============================================================ SM2 曲线

enum SM2Curve {
    static let p = Modulus(
        m: [0xFFFFFFFF, 0xFFFFFFFF, 0x00000000, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE],
        n0: 0x00000001,
        r2: [0x00000003, 0x00000002, 0xFFFFFFFF, 0x00000002, 0x00000001, 0x00000001, 0x00000002, 0x00000004],
        one: [0x00000001, 0x00000000, 0xFFFFFFFF, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000001],
        minus2: [0xFFFFFFFD, 0xFFFFFFFF, 0x00000000, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE])

    static let n = Modulus(
        m: [0x39D54123, 0x53BBF409, 0x21C6052B, 0x7203DF6B, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE],
        n0: 0x72350975,
        r2: [0x7C114F20, 0x901192AF, 0xDE6FA2FA, 0x3464504A, 0x3AFFE0D4, 0x620FC84C, 0xA22B3D3B, 0x1EB5E412],
        one: [0xC62ABEDD, 0xAC440BF6, 0xDE39FAD4, 0x8DFC2094, 0x00000000, 0x00000000, 0x00000000, 0x00000001],
        minus2: [0x39D54121, 0x53BBF409, 0x21C6052B, 0x7203DF6B, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE])

    static let gx: Limb8 = [0x334C74C7, 0x715A4589, 0xF2660BE1, 0x8FE30BBF, 0x6A39C994, 0x5F990446, 0x1F198119, 0x32C4AE2C]
    static let gy: Limb8 = [0x2139F0A0, 0x02DF32E5, 0xC62A4740, 0xD0A9877C, 0x6B692153, 0x59BDCEE3, 0xF4F6779C, 0xBC3736A2]

    /// 曲线系数 b（a = p-3）
    static let b: Limb8 = [0x4D940E93, 0xDDBCBD41, 0x15AB8F92, 0xF39789F5, 0xCF6509A7, 0x4D5A9E4B, 0x9D9F5E34, 0x28E9FA9E]

    /// a = p-3
    static let a: Limb8 = [0xFFFFFFFC, 0xFFFFFFFF, 0x00000000, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE]

    /// 模平方根指数 (p+1)/4
    static let sqrtExponent: Limb8 = [0x00000000, 0x40000000, 0xC0000000, 0xFFFFFFFF,
                                      0xFFFFFFFF, 0xFFFFFFFF, 0xBFFFFFFF, 0x3FFFFFFF]

    static let gAffine: JPoint = {
        JPoint(x: toMont(gx, p), y: toMont(gy, p), z: p.one)
    }()
}

// ============================================================ Jacobian 坐标

struct JPoint {
    var x: Limb8
    var y: Limb8
    var z: Limb8

    static var infinity: JPoint { JPoint(x: SM2Curve.p.one, y: SM2Curve.p.one, z: limb(0)) }

    var isInfinity: Bool { limbIsZero(z) }

    /// 仿射坐标（仍在 Montgomery 域）
    var affine: (Limb8, Limb8)? {
        if isInfinity { return nil }
        let p = SM2Curve.p
        let zi = montInverse(z, p)
        let zi2 = montMul(zi, zi, p)
        return (montMul(x, zi2, p), montMul(y, montMul(zi2, zi, p), p))
    }
}

/// 倍点（曲线 a = -3 的专用公式）
func pointDouble(_ pt: JPoint) -> JPoint {
    if pt.isInfinity || limbIsZero(pt.y) { return .infinity }
    let p = SM2Curve.p
    let z2 = montMul(pt.z, pt.z, p)
    // M = 3(X - Z²)(X + Z²) = 3(X² - Z⁴)
    let m = mulSmall(montMul(subMod(pt.x, z2, p), addMod(pt.x, z2, p), p), 3, p)
    let y2 = montMul(pt.y, pt.y, p)
    let s4 = mulSmall(mulSmall(montMul(pt.x, y2, p), 2, p), 2, p)   // 4XY²
    let x3 = subMod(montMul(m, m, p), dblMod(s4, p), p)
    let y4 = montMul(y2, y2, p)
    let y8 = mulSmall(mulSmall(mulSmall(y4, 2, p), 2, p), 2, p)     // 8Y⁴
    let y3 = subMod(montMul(m, subMod(s4, x3, p), p), y8, p)
    let z3 = dblMod(montMul(pt.y, pt.z, p), p)
    return JPoint(x: x3, y: y3, z: z3)
}

/// 点加（Jacobian + Jacobian）
func pointAdd(_ a: JPoint, _ b: JPoint) -> JPoint {
    if a.isInfinity { return b }
    if b.isInfinity { return a }
    let p = SM2Curve.p
    let z1z1 = montMul(a.z, a.z, p)
    let z2z2 = montMul(b.z, b.z, p)
    let u1 = montMul(a.x, z2z2, p)
    let u2 = montMul(b.x, z1z1, p)
    let s1 = montMul(a.y, montMul(b.z, z2z2, p), p)
    let s2 = montMul(b.y, montMul(a.z, z1z1, p), p)

    if limbCmp(u1, u2) == 0 {
        if limbCmp(s1, s2) != 0 { return .infinity }
        return pointDouble(a)
    }

    let h = subMod(u2, u1, p)
    let i = montMul(dblMod(h, p), dblMod(h, p), p)
    let j = montMul(h, i, p)
    let r = dblMod(subMod(s2, s1, p), p)
    let v = montMul(u1, i, p)
    let x3 = subMod(subMod(montMul(r, r, p), j, p), dblMod(v, p), p)
    let s1j = montMul(s1, j, p)
    let y3 = subMod(montMul(r, subMod(v, x3, p), p), dblMod(s1j, p), p)
    let zs = addMod(a.z, b.z, p)
    let z3 = montMul(subMod(subMod(montMul(zs, zs, p), z1z1, p), z2z2, p), h, p)
    return JPoint(x: x3, y: y3, z: z3)
}

/// 标量乘 k·P，k 为 32 字节大端（MSB-first double-and-add）
///
/// 注意：遍历是从最高位到最低位，因此必须用「先倍点、后累加」的顺序。
/// 若写成「先累加、后倍点」则会等价于 LSB-first，结果完全错误。
func pointMultiply(_ k: [UInt8], _ pt: JPoint) -> JPoint {
    var result = JPoint.infinity
    for byte in k {
        var b = byte
        var bit = 0
        while bit < 8 {
            // 先倍点：result = 2·result
            result = pointDouble(result)
            if b & 0x80 != 0 {
                result = pointAdd(result, pt)
            }
            b <<= 1
            bit += 1
        }
    }
    return result
}

/// 标量乘：k 为 8×UInt32 小端分肢
func pointMultiply(_ k: Limb8, _ pt: JPoint) -> JPoint {
    pointMultiply(limbToBytes(k), pt)
}

// ============================================================ 字节工具

func limbToBytes(_ v: Limb8) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: 32)
    for i in 0..<8 {
        let w = v[i]
        let base = (7 - i) * 4
        out[base] = UInt8(truncatingIfNeeded: w >> 24)
        out[base + 1] = UInt8(truncatingIfNeeded: w >> 16)
        out[base + 2] = UInt8(truncatingIfNeeded: w >> 8)
        out[base + 3] = UInt8(truncatingIfNeeded: w)
    }
    return out
}

func bytesToLimb(_ b: [UInt8]) -> Limb8 {
    var out = [UInt32](repeating: 0, count: 8)
    var padded = b
    if padded.count > 32 { padded = Array(padded.suffix(32)) }
    if padded.count < 32 { padded = [UInt8](repeating: 0, count: 32 - padded.count) + padded }
    for i in 0..<8 {
        let base = (7 - i) * 4
        out[i] = (UInt32(padded[base]) << 24) | (UInt32(padded[base + 1]) << 16)
            | (UInt32(padded[base + 2]) << 8) | UInt32(padded[base + 3])
    }
    return out
}

// ============================================================ SM2 点编解码

enum SM2Point {
    enum DecodeError: Error { case badEncoding, notOnCurve }

    /// 65 字节未压缩 / 33 字节压缩 → 仿射坐标（Montgomery 域）
    static func decode(_ bytes: [UInt8]) throws -> (Limb8, Limb8) {
        let px: Limb8
        let py: Limb8

        if bytes.count == 65 && bytes[0] == 0x04 {
            px = bytesToLimb(Array(bytes[1..<33]))
            py = bytesToLimb(Array(bytes[33..<65]))
        } else if bytes.count == 33 && (bytes[0] == 0x02 || bytes[0] == 0x03) {
            px = bytesToLimb(Array(bytes[1..<33]))
            let p = SM2Curve.p
            let mx = toMont(px, p)
            let x3 = montMul(montMul(mx, mx, p), mx, p)
            let sum = addMod(subMod(x3, mulSmall(mx, 3, p), p), toMont(SM2Curve.b, p), p)
            var yMont = montPow(sum, SM2Curve.sqrtExponent, p)
            let yPlain = fromMont(yMont, p)
            let wantOdd = bytes[0] == 0x03
            if (yPlain[0] & 1 == 1) != wantOdd {
                yMont = subMod(p.m, yMont, p)
            }
            py = fromMont(yMont, p)
        } else {
            throw DecodeError.badEncoding
        }

        // y² = x³ - 3x + b mod p
        let p = SM2Curve.p
        let mx = toMont(px, p)
        let my = toMont(py, p)
        let lhs = montMul(my, my, p)
        let x3 = montMul(montMul(mx, mx, p), mx, p)
        let rhs = addMod(subMod(x3, mulSmall(mx, 3, p), p), toMont(SM2Curve.b, p), p)
        guard limbCmp(lhs, rhs) == 0 else { throw DecodeError.notOnCurve }
        return (mx, my)
    }

    static func encodeUncompressed(_ affine: (Limb8, Limb8)) -> [UInt8] {
        [0x04] + limbToBytes(fromMont(affine.0, SM2Curve.p))
            + limbToBytes(fromMont(affine.1, SM2Curve.p))
    }
}

// ============================================================ SM2 密钥协商（与 BleSm2Crypto.agree 一致）

enum SM2Agreement {
    /// 返回 (本地未压缩公钥 65 字节, 共享密钥 SM3 的 32 字节)
    static func agree(peerEncoded: [UInt8], privateScalar: [UInt8]) throws -> ([UInt8], [UInt8]) {
        let peer = try SM2Point.decode(peerEncoded)
        let peerPoint = JPoint(x: peer.0, y: peer.1, z: SM2Curve.p.one)

        let localJ = pointMultiply(privateScalar, SM2Curve.gAffine)
        guard let localAff = localJ.affine else { throw LeapCryptoError.badPoint }

        // localFactor = (xbar(local) + 1) · d mod n
        let localFactor = modMulNormal(addMod(xBar(localAff.0), limb(1), SM2Curve.n),
                                       bytesToLimb(privateScalar), SM2Curve.n)
        // peerFactor = (xbar(peer) + 1) mod n
        let peerFactor = addMod(xBar(peer.0), limb(1), SM2Curve.n)

        let t = pointMultiply(limbToBytes(peerFactor), peerPoint)
        guard let tAff = t.affine else { throw LeapCryptoError.badPoint }
        let sharedJ = pointMultiply(limbToBytes(localFactor),
                                    JPoint(x: tAff.0, y: tAff.1, z: SM2Curve.p.one))
        guard let shared = sharedJ.affine else { throw LeapCryptoError.badPoint }

        var material = [UInt8]()
        material.reserveCapacity(96)
        material.append(contentsOf: limbToBytes(fromMont(shared.0, SM2Curve.p)))
        material.append(contentsOf: limbToBytes(fromMont(shared.1, SM2Curve.p)))
        material.append(contentsOf: identityDigest(localAff.0, localAff.1))
        material.append(contentsOf: identityDigest(peer.0, peer.1))
        material.append(contentsOf: [0, 0, 0, 1])

        return (SM2Point.encodeUncompressed(localAff), SM3.hash(material))
    }

    /// xbar(x) = (x mod 2¹²⁷) + 2¹²⁷
    private static func xBar(_ montX: Limb8) -> Limb8 {
        var x = fromMont(montX, SM2Curve.p)
        x[3] &= 0x7FFFFFFF          // 清掉 bit 127（limb 3 最高位）
        for i in 4..<8 { x[i] = 0 }
        x[3] |= 0x80000000          // setBit(127)
        return x
    }

    /// ZA = SM3(ENTL ‖ ID ‖ a ‖ b ‖ Gx ‖ Gy ‖ Px ‖ Py)
    private static func identityDigest(_ x: Limb8, _ y: Limb8) -> [UInt8] {
        let userId = Array("1234567812345678".utf8)
        let bitLength = userId.count * 8
        var material = [UInt8]()
        material.reserveCapacity(2 + userId.count + 32 * 6)
        material.append(UInt8(truncatingIfNeeded: bitLength >> 8))
        material.append(UInt8(truncatingIfNeeded: bitLength))
        material.append(contentsOf: userId)
        material.append(contentsOf: limbToBytes(SM2Curve.a))
        material.append(contentsOf: limbToBytes(SM2Curve.b))
        material.append(contentsOf: limbToBytes(SM2Curve.gx))
        material.append(contentsOf: limbToBytes(SM2Curve.gy))
        material.append(contentsOf: limbToBytes(fromMont(x, SM2Curve.p)))
        material.append(contentsOf: limbToBytes(fromMont(y, SM2Curve.p)))
        return SM3.hash(material)
    }

    /// [1, n-1] 内随机私钥标量（32 字节大端）
    static func randomScalar() -> [UInt8] {
        while true {
            let bytes = RandomSource.bytes(32)
            let v = bytesToLimb(bytes)
            if limbIsZero(v) { continue }
            if limbCmp(v, SM2Curve.n.m) >= 0 { continue }
            return bytes
        }
    }
}

// ============================================================ SM3

enum SM3 {
    private static let iv: [UInt32] = [
        0x7380166F, 0x4914B2B9, 0x172442D7, 0xDA8A0600,
        0xA96F30BC, 0x163138AA, 0xE38DEE4D, 0xB0FB0E4E
    ]

    @inline(__always)
    static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
        let s = n & 31
        if s == 0 { return x }
        return (x << s) | (x >> (32 - s))
    }

    @inline(__always)
    static func p0(_ x: UInt32) -> UInt32 { x ^ rotl(x, 9) ^ rotl(x, 17) }

    @inline(__always)
    static func p1(_ x: UInt32) -> UInt32 { x ^ rotl(x, 15) ^ rotl(x, 23) }

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var data = message
        let bitLen = UInt64(message.count) &* 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for i in 0..<8 {
            data.append(UInt8(truncatingIfNeeded: bitLen >> (56 - i * 8)))
        }

        var v = iv
        var offset = 0
        var w = [UInt32](repeating: 0, count: 68)
        var w1 = [UInt32](repeating: 0, count: 64)

        while offset < data.count {
            for i in 0..<16 {
                let b = offset + i * 4
                w[i] = (UInt32(data[b]) << 24) | (UInt32(data[b + 1]) << 16)
                    | (UInt32(data[b + 2]) << 8) | UInt32(data[b + 3])
            }
            for j in 16..<68 {
                w[j] = p1(w[j - 16] ^ w[j - 9] ^ rotl(w[j - 3], 15))
                    ^ rotl(w[j - 13], 7) ^ w[j - 6]
            }
            for j in 0..<64 { w1[j] = w[j] ^ w[j + 4] }

            var a = v[0], b = v[1], c = v[2], d = v[3]
            var e = v[4], f = v[5], g = v[6], h = v[7]

            for j in 0..<64 {
                let t: UInt32 = j < 16 ? 0x79CC4519 : 0x7A879D8A
                let ss1 = rotl(rotl(a, 12) &+ e &+ rotl(t, UInt32(j)), 7)
                let ss2 = ss1 ^ rotl(a, 12)
                let ff: UInt32 = j < 16 ? (a ^ b ^ c) : ((a & b) | (a & c) | (b & c))
                let gg: UInt32 = j < 16 ? (e ^ f ^ g) : ((e & f) | (~e & g))
                let tt1 = ff &+ d &+ ss2 &+ w1[j]
                let tt2 = gg &+ h &+ ss1 &+ w[j]
                d = c
                c = rotl(b, 9)
                b = a
                a = tt1
                h = g
                g = rotl(f, 19)
                f = e
                e = p0(tt2)
            }

            v[0] ^= a; v[1] ^= b; v[2] ^= c; v[3] ^= d
            v[4] ^= e; v[5] ^= f; v[6] ^= g; v[7] ^= h
            offset += 64
        }

        var out = [UInt8]()
        out.reserveCapacity(32)
        for word in v {
            out.append(UInt8(truncatingIfNeeded: word >> 24))
            out.append(UInt8(truncatingIfNeeded: word >> 16))
            out.append(UInt8(truncatingIfNeeded: word >> 8))
            out.append(UInt8(truncatingIfNeeded: word))
        }
        return out
    }
}

// ============================================================ SM4

enum SM4 {
    static let sbox: [UInt8] = [
        0xd6, 0x90, 0xe9, 0xfe, 0xcc, 0xe1, 0x3d, 0xb7, 0x16, 0xb6, 0x14, 0xc2, 0x28, 0xfb, 0x2c, 0x05,
        0x2b, 0x67, 0x9a, 0x76, 0x2a, 0xbe, 0x04, 0xc3, 0xaa, 0x44, 0x13, 0x26, 0x49, 0x86, 0x06, 0x99,
        0x9c, 0x42, 0x50, 0xf4, 0x91, 0xef, 0x98, 0x7a, 0x33, 0x54, 0x0b, 0x43, 0xed, 0xcf, 0xac, 0x62,
        0xe4, 0xb3, 0x1c, 0xa9, 0xc9, 0x08, 0xe8, 0x95, 0x80, 0xdf, 0x94, 0xfa, 0x75, 0x8f, 0x3f, 0xa6,
        0x47, 0x07, 0xa7, 0xfc, 0xf3, 0x73, 0x17, 0xba, 0x83, 0x59, 0x3c, 0x19, 0xe6, 0x85, 0x4f, 0xa8,
        0x68, 0x6b, 0x81, 0xb2, 0x71, 0x64, 0xda, 0x8b, 0xf8, 0xeb, 0x0f, 0x4b, 0x70, 0x56, 0x9d, 0x35,
        0x1e, 0x24, 0x0e, 0x5e, 0x63, 0x58, 0xd1, 0xa2, 0x25, 0x22, 0x7c, 0x3b, 0x01, 0x21, 0x78, 0x87,
        0xd4, 0x00, 0x46, 0x57, 0x9f, 0xd3, 0x27, 0x52, 0x4c, 0x36, 0x02, 0xe7, 0xa0, 0xc4, 0xc8, 0x9e,
        0xea, 0xbf, 0x8a, 0xd2, 0x40, 0xc7, 0x38, 0xb5, 0xa3, 0xf7, 0xf2, 0xce, 0xf9, 0x61, 0x15, 0xa1,
        0xe0, 0xae, 0x5d, 0xa4, 0x9b, 0x34, 0x1a, 0x55, 0xad, 0x93, 0x32, 0x30, 0xf5, 0x8c, 0xb1, 0xe3,
        0x1d, 0xf6, 0xe2, 0x2e, 0x82, 0x66, 0xca, 0x60, 0xc0, 0x29, 0x23, 0xab, 0x0d, 0x53, 0x4e, 0x6f,
        0xd5, 0xdb, 0x37, 0x45, 0xde, 0xfd, 0x8e, 0x2f, 0x03, 0xff, 0x6a, 0x72, 0x6d, 0x6c, 0x5b, 0x51,
        0x8d, 0x1b, 0xaf, 0x92, 0xbb, 0xdd, 0xbc, 0x7f, 0x11, 0xd9, 0x5c, 0x41, 0x1f, 0x10, 0x5a, 0xd8,
        0x0a, 0xc1, 0x31, 0x88, 0xa5, 0xcd, 0x7b, 0xbd, 0x2d, 0x74, 0xd0, 0x12, 0xb8, 0xe5, 0xb4, 0xb0,
        0x89, 0x69, 0x97, 0x4a, 0x0c, 0x96, 0x77, 0x7e, 0x65, 0xb9, 0xf1, 0x09, 0xc5, 0x6e, 0xc6, 0x84,
        0x18, 0xf0, 0x7d, 0xec, 0x3a, 0xdc, 0x4d, 0x20, 0x79, 0xee, 0x5f, 0x3e, 0xd7, 0xcb, 0x39, 0x48
    ]

    private static let fk: [UInt32] = [0xA3B1BAC6, 0x56AA3350, 0x677D9197, 0xB27022DC]

    private static let ck: [UInt32] = (0..<32).map { i in
        var w: UInt32 = 0
        for j in 0..<4 {
            w = (w << 8) | UInt32(truncatingIfNeeded: ((4 * i + j) * 7) & 0xFF)
        }
        return w
    }

    @inline(__always)
    static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
        let s = n & 31
        if s == 0 { return x }
        return (x << s) | (x >> (32 - s))
    }

    @inline(__always)
    static func tau(_ a: UInt32) -> UInt32 {
        (UInt32(sbox[Int((a >> 24) & 0xFF)]) << 24)
            | (UInt32(sbox[Int((a >> 16) & 0xFF)]) << 16)
            | (UInt32(sbox[Int((a >> 8) & 0xFF)]) << 8)
            | UInt32(sbox[Int(a & 0xFF)])
    }

    @inline(__always)
    static func t(_ a: UInt32) -> UInt32 {
        let b = tau(a)
        return b ^ rotl(b, 2) ^ rotl(b, 10) ^ rotl(b, 18) ^ rotl(b, 24)
    }

    @inline(__always)
    static func tPrime(_ a: UInt32) -> UInt32 {
        let b = tau(a)
        return b ^ rotl(b, 13) ^ rotl(b, 23)
    }

    static func roundKeys(_ key: [UInt8]) -> [UInt32] {
        var kk = [UInt32](repeating: 0, count: 36)
        for i in 0..<4 {
            kk[i] = ((UInt32(key[i * 4]) << 24) | (UInt32(key[i * 4 + 1]) << 16)
                | (UInt32(key[i * 4 + 2]) << 8) | UInt32(key[i * 4 + 3])) ^ fk[i]
        }
        var rk = [UInt32](repeating: 0, count: 32)
        for i in 0..<32 {
            let v = kk[i] ^ tPrime(kk[i + 1] ^ kk[i + 2] ^ kk[i + 3] ^ ck[i])
            kk[i + 4] = v
            rk[i] = v
        }
        return rk
    }

    @inline(__always)
    private static func block(_ rk: [UInt32], _ src: [UInt8], _ offset: Int, _ reverse: Bool) -> [UInt8] {
        var x = [UInt32](repeating: 0, count: 36)
        for i in 0..<4 {
            let b = offset + i * 4
            x[i] = (UInt32(src[b]) << 24) | (UInt32(src[b + 1]) << 16)
                | (UInt32(src[b + 2]) << 8) | UInt32(src[b + 3])
        }
        for i in 0..<32 {
            let k = reverse ? rk[31 - i] : rk[i]
            x[i + 4] = x[i] ^ t(x[i + 1] ^ x[i + 2] ^ x[i + 3] ^ k)
        }
        var out = [UInt8](repeating: 0, count: 16)
        for k in 0..<4 {
            let word = x[35 - k]
            out[k * 4] = UInt8(truncatingIfNeeded: word >> 24)
            out[k * 4 + 1] = UInt8(truncatingIfNeeded: word >> 16)
            out[k * 4 + 2] = UInt8(truncatingIfNeeded: word >> 8)
            out[k * 4 + 3] = UInt8(truncatingIfNeeded: word)
        }
        return out
    }

    /// 单块加密（测试用）
    static func encryptBlock(_ key: [UInt8], _ block16: [UInt8]) -> [UInt8] {
        self.block(roundKeys(key), block16, 0, false)
    }

    /// SM4-CBC + PKCS7 加密
    static func cbcEncrypt(key: [UInt8], iv: [UInt8], plain: [UInt8]) -> [UInt8] {
        let rk = roundKeys(key)
        let pad = 16 - (plain.count % 16)
        var data = plain
        data.append(contentsOf: [UInt8](repeating: UInt8(pad), count: pad))
        var out = [UInt8]()
        out.reserveCapacity(data.count)
        var prev = iv
        var offset = 0
        while offset < data.count {
            var xored = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 { xored[i] = data[offset + i] ^ prev[i] }
            let enc = block(rk, xored, 0, false)
            out.append(contentsOf: enc)
            prev = enc
            offset += 16
        }
        return out
    }

    /// SM4-CBC + PKCS7 解密
    static func cbcDecrypt(key: [UInt8], iv: [UInt8], cipher: [UInt8]) throws -> [UInt8] {
        guard !cipher.isEmpty, cipher.count % 16 == 0 else { throw LeapCryptoError.badCiphertext }
        let rk = roundKeys(key)
        var out = [UInt8]()
        out.reserveCapacity(cipher.count)
        var prev = iv
        var offset = 0
        while offset < cipher.count {
            let dec = block(rk, cipher, offset, true)
            for i in 0..<16 { out.append(dec[i] ^ prev[i]) }
            prev = Array(cipher[offset..<(offset + 16)])
            offset += 16
        }
        guard let pad = out.last, pad >= 1, pad <= 16, out.count >= Int(pad) else {
            throw LeapCryptoError.badCiphertext
        }
        for i in (out.count - Int(pad))..<out.count where out[i] != pad {
            throw LeapCryptoError.badCiphertext
        }
        return Array(out[0..<(out.count - Int(pad))])
    }
}
