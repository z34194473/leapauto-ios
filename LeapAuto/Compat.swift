// ============================================================
//  Compat.swift —— 跨平台加密原语适配层
//
//  iOS  : CryptoKit (MD5/SHA256/HMAC) + CommonCrypto (AES) + Security (RSA/SM2随机)
//  Win  : 纯 Swift 实现（用于算法自检，不参与 iOS 构建）
//
//  通过 #if canImport 自动切换，iOS 构建行为完全不变。
// ============================================================

import Foundation

#if canImport(Security)
import Security
#endif

// ============================================================ 摘要算法（跨平台统一入口）

enum Digest {

    static func md5(_ data: [UInt8]) -> [UInt8] {
        #if canImport(CryptoKit)
        return Array(Insecure.MD5.hash(data: Data(data)))
        #else
        return MD5Fallback.hash(data)
        #endif
    }

    static func sha256(_ data: [UInt8]) -> [UInt8] {
        #if canImport(CryptoKit)
        return Array(SHA256.hash(data: Data(data)))
        #else
        return SHA256Fallback.hash(data)
        #endif
    }

    static func hmacSHA256(key: [UInt8], message: [UInt8]) -> [UInt8] {
        #if canImport(CryptoKit)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message),
                                                  using: SymmetricKey(data: Data(key)))
        return Array(mac)
        #else
        return SHA256Fallback.hmac(key: key, message: message)
        #endif
    }
}

// ============================================================ 安全随机

enum RandomSource {
    static func bytes(_ count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        #if canImport(Security)
        if SecRandomCopyBytes(kSecRandomDefault, count, &out) == errSecSuccess { return out }
        #endif
        // 兜底：时间 + 地址熵（仅自检用，iOS 始终走 SecRandom）
        var seed = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        for i in 0..<count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            out[i] = UInt8(truncatingIfNeeded: seed >> 33)
        }
        return out
    }
}

// ============================================================ MD5（纯 Swift，仅非 Apple 平台使用）

enum MD5Fallback {
    private static let s: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ]

    private static let k: [UInt32] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a,
        0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340,
        0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
        0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
        0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
        0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    ]

    @inline(__always)
    static func rotl(_ x: UInt32, _ c: UInt32) -> UInt32 {
        (x << c) | (x >> (32 - c))
    }

    static func hash(_ input: [UInt8]) -> [UInt8] {
        var data = input
        let bitLen = UInt64(input.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for i in 0..<8 {
            data.append(UInt8(truncatingIfNeeded: bitLen >> (8 * UInt64(i))))
        }

        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xefcdab89
        var h2: UInt32 = 0x98badcfe
        var h3: UInt32 = 0x10325476

        var offset = 0
        while offset < data.count {
            var m = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let b = offset + i * 4
                m[i] = UInt32(data[b]) | (UInt32(data[b + 1]) << 8)
                    | (UInt32(data[b + 2]) << 16) | (UInt32(data[b + 3]) << 24)
            }

            var a = h0, b = h1, c = h2, d = h3
            for i in 0..<64 {
                var f: UInt32
                var g: Int
                switch i / 16 {
                case 0:
                    f = (b & c) | (~b & d)
                    g = i
                case 1:
                    f = (d & b) | (~d & c)
                    g = (5 * i + 1) % 16
                case 2:
                    f = b ^ c ^ d
                    g = (3 * i + 5) % 16
                default:
                    f = c ^ (b | ~d)
                    g = (7 * i) % 16
                }
                f = f &+ a &+ k[i] &+ m[g]
                a = d
                d = c
                c = b
                b = b &+ rotl(f, s[i])
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            offset += 64
        }

        var out = [UInt8]()
        out.reserveCapacity(16)
        for word in [h0, h1, h2, h3] {
            out.append(UInt8(truncatingIfNeeded: word))
            out.append(UInt8(truncatingIfNeeded: word >> 8))
            out.append(UInt8(truncatingIfNeeded: word >> 16))
            out.append(UInt8(truncatingIfNeeded: word >> 24))
        }
        return out
    }
}

// ============================================================ SHA-256（纯 Swift，仅非 Apple 平台使用）

enum SHA256Fallback {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
        0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
        0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    @inline(__always)
    static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x >> n) | (x << (32 - n))
    }

    static func hash(_ input: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]

        var data = input
        let bitLen = UInt64(input.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for i in 0..<8 {
            data.append(UInt8(truncatingIfNeeded: bitLen >> UInt64((7 - i) * 8)))
        }

        var w = [UInt32](repeating: 0, count: 64)
        var offset = 0
        while offset < data.count {
            for i in 0..<16 {
                let b = offset + i * 4
                w[i] = (UInt32(data[b]) << 24) | (UInt32(data[b + 1]) << 16)
                    | (UInt32(data[b + 2]) << 8) | UInt32(data[b + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]

            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e
                e = d &+ t1
                d = c; c = b; b = a
                a = t1 &+ t2
            }

            h[0] = h[0] &+ a; h[1] = h[1] &+ b
            h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f
            h[6] = h[6] &+ g; h[7] = h[7] &+ hh
            offset += 64
        }

        var out = [UInt8]()
        out.reserveCapacity(32)
        for word in h {
            out.append(UInt8(truncatingIfNeeded: word >> 24))
            out.append(UInt8(truncatingIfNeeded: word >> 16))
            out.append(UInt8(truncatingIfNeeded: word >> 8))
            out.append(UInt8(truncatingIfNeeded: word))
        }
        return out
    }

    /// HMAC-SHA256
    static func hmac(key: [UInt8], message: [UInt8]) -> [UInt8] {
        let blockSize = 64
        var k = key
        if k.count > blockSize { k = hash(k) }
        if k.count < blockSize { k += [UInt8](repeating: 0, count: blockSize - k.count) }

        var ipad = [UInt8](repeating: 0, count: blockSize)
        var opad = [UInt8](repeating: 0, count: blockSize)
        for i in 0..<blockSize {
            ipad[i] = k[i] ^ 0x36
            opad[i] = k[i] ^ 0x5C
        }
        return hash(opad + hash(ipad + message))
    }
}

// ============================================================ AES-128-CBC（仅非 Apple 平台自检用）

#if !canImport(CommonCrypto)
enum AESFallback {
    private static let sbox: [UInt8] = [
        0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
        0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
        0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
        0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
        0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
        0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
        0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
        0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
        0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
        0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
        0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
        0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
        0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
        0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
        0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
        0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
    ]
    private static let rcon: [UInt8] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]

    @inline(__always)
    static func xt(_ a: UInt8) -> UInt8 { (a << 1) ^ ((a & 0x80) != 0 ? 0x1b : 0) }

    static func expandKey(_ key: [UInt8]) -> [UInt8] {
        var w = key
        var bytesGenerated = 16
        var rci = 0
        var temp = [UInt8](repeating: 0, count: 4)
        while bytesGenerated < 176 {
            // 取上一轮最后 4 字节（必须先固化，不能随 bytesGenerated 自增漂移）
            let tailStart = bytesGenerated - 4
            for i in 0..<4 { temp[i] = w[tailStart + i] }
            if bytesGenerated % 16 == 0 {
                let t0 = temp[0]
                temp[0] = sbox[Int(temp[1])] ^ rcon[rci]
                temp[1] = sbox[Int(temp[2])]
                temp[2] = sbox[Int(temp[3])]
                temp[3] = sbox[Int(t0)]
                rci += 1
            }
            // 与新 4 字节对齐的基准索引，循环内不可改变
            let baseStart = bytesGenerated - 16
            for i in 0..<4 {
                w.append(w[baseStart + i] ^ temp[i])
            }
            bytesGenerated += 4
        }
        return w
    }

    static func encryptBlock(_ block: [UInt8], _ w: [UInt8]) -> [UInt8] {
        var s = block
        for i in 0..<16 { s[i] ^= w[i] }

        for round in 1...10 {
            for i in 0..<16 { s[i] = sbox[Int(s[i])] }
            // ShiftRows（列主序：state[r + 4c]）
            var t = s
            for c in 0..<4 {
                for r in 0..<4 {
                    t[r + 4 * c] = s[r + 4 * ((c + r) % 4)]
                }
            }
            s = t
            if round != 10 {
                for c in 0..<4 {
                    let i = 4 * c
                    let a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3]
                    let all = a0 ^ a1 ^ a2 ^ a3
                    s[i] = a0 ^ all ^ xt(a0 ^ a1)
                    s[i + 1] = a1 ^ all ^ xt(a1 ^ a2)
                    s[i + 2] = a2 ^ all ^ xt(a2 ^ a3)
                    s[i + 3] = a3 ^ all ^ xt(a3 ^ a0)
                }
            }
            for i in 0..<16 { s[i] ^= w[16 * round + i] }
        }
        return s
    }

    // ---- 逆运算（解密用）

    private static let invSbox: [UInt8] = {
        var t = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 { t[Int(sbox[i])] = UInt8(i) }
        return t
    }()

    @inline(__always)
    private static func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var p: UInt8 = 0
        var x = a
        var y = b
        for _ in 0..<8 {
            if y & 1 != 0 { p ^= x }
            let hi = x & 0x80
            x <<= 1
            if hi != 0 { x ^= 0x1b }
            y >>= 1
        }
        return p
    }

    static func decryptBlock(_ block: [UInt8], _ w: [UInt8]) -> [UInt8] {
        var s = block
        for round in stride(from: 10, through: 1, by: -1) {
            for i in 0..<16 { s[i] ^= w[16 * round + i] }
            // InvMixColumns
            if round != 10 {
                for c in 0..<4 {
                    let i = 4 * c
                    let a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3]
                    s[i] = mul(a0, 14) ^ mul(a1, 11) ^ mul(a2, 13) ^ mul(a3, 9)
                    s[i + 1] = mul(a0, 9) ^ mul(a1, 14) ^ mul(a2, 11) ^ mul(a3, 13)
                    s[i + 2] = mul(a0, 13) ^ mul(a1, 9) ^ mul(a2, 14) ^ mul(a3, 11)
                    s[i + 3] = mul(a0, 11) ^ mul(a1, 13) ^ mul(a2, 9) ^ mul(a3, 14)
                }
            }
            // InvShiftRows
            var t = s
            for c in 0..<4 {
                for r in 0..<4 {
                    t[r + 4 * ((c + r) % 4)] = s[r + 4 * c]
                }
            }
            s = t
            for i in 0..<16 { s[i] = invSbox[Int(s[i])] }
        }
        for i in 0..<16 { s[i] ^= w[i] }
        return s
    }

    static func encryptCBC(plain: [UInt8], key: [UInt8], iv: [UInt8]) -> [UInt8] {
        let w = expandKey(key)
        let pad = 16 - (plain.count % 16)
        var data = plain
        data += [UInt8](repeating: UInt8(pad), count: pad)

        var out = [UInt8]()
        var prev = iv
        var offset = 0
        while offset < data.count {
            var block = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 { block[i] = data[offset + i] ^ prev[i] }
            let enc = encryptBlock(block, w)
            out += enc
            prev = enc
            offset += 16
        }
        return out
    }

    static func decryptCBC(cipher: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        guard !cipher.isEmpty, cipher.count % 16 == 0 else {
            throw LeapCryptoError.badCiphertext
        }
        let w = expandKey(key)
        var out = [UInt8]()
        var prev = iv
        var offset = 0
        while offset < cipher.count {
            let block = Array(cipher[offset..<(offset + 16)])
            let dec = decryptBlock(block, w)
            for i in 0..<16 { out.append(dec[i] ^ prev[i]) }
            prev = block
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
#endif
