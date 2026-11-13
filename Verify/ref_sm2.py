"""SM2 密钥协商 + 1PAO 会话派生参考实现，对齐 BleSm2Crypto.kt / BleKeyProtocol.kt"""
import base64, json
from ref_sm import sm3, sm4_cbc_encrypt, sm4_cbc_decrypt

P = 0xFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF
A = 0xFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFC
B = 0x28E9FA9E9D9F5E344D5A9E4BCF6509A7F39789F515AB8F92DDBCBD414D940E93
N = 0xFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFF7203DF6B21C6052B53BBF40939D54123
GX = 0x32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7
GY = 0xBC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0


def inv(a, m=P):
    return pow(a, m - 2, m)


def add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    x1, y1 = p1
    x2, y2 = p2
    if x1 == x2:
        if (y1 + y2) % P == 0:
            return None
        lam = (3 * x1 * x1 + A) * inv(2 * y1) % P
    else:
        lam = (y2 - y1) * inv(x2 - x1) % P
    x3 = (lam * lam - x1 - x2) % P
    return (x3, (lam * (x1 - x3) - y1) % P)


def mul(k, pt):
    r = None
    while k:
        if k & 1:
            r = add(r, pt)
        pt = add(pt, pt)
        k >>= 1
    return r


G = (GX, GY)


def decode_point(b):
    if len(b) == 65 and b[0] == 4:
        return (int.from_bytes(b[1:33], 'big'), int.from_bytes(b[33:65], 'big'))
    if len(b) == 33 and b[0] in (2, 3):
        x = int.from_bytes(b[1:], 'big')
        y = pow((pow(x, 3, P) + A * x + B) % P, (P + 1) // 4, P)
        if (y & 1) != (b[0] & 1):
            y = P - y
        return (x, y)
    raise ValueError("bad point")


def enc_point(pt):
    return b'\x04' + pt[0].to_bytes(32, 'big') + pt[1].to_bytes(32, 'big')


def coord(v):
    return v.to_bytes(32, 'big')


def xbar(pt):
    return (pt[0] & ((1 << 127) - 1)) | (1 << 127)


USER_ID = b"1234567812345678"


def identity_digest(pt):
    bitlen = len(USER_ID) * 8
    material = (bytes([bitlen >> 8, bitlen & 0xFF]) + USER_ID
                + coord(A) + coord(B) + coord(GX) + coord(GY)
                + coord(pt[0]) + coord(pt[1]))
    return sm3(material)


def agree(peer_point, priv_scalar):
    local = mul(priv_scalar, G)
    local_factor = (xbar(local) + 1) * priv_scalar % N
    peer_factor = (xbar(peer_point) + 1) % N
    shared = mul(local_factor, mul(peer_factor, peer_point))
    material = (coord(shared[0]) + coord(shared[1])
                + identity_digest(local) + identity_digest(peer_point) + bytes([0, 0, 0, 1]))
    return enc_point(local), sm3(material)


# ---------- BleKeyProtocol.deriveSession ----------
def le(v, n):
    return v.to_bytes(n, 'little')


def derive_session(peer_point, priv_scalar, session_id, vin, password_card):
    pub, secret = agree(peer_point, priv_scalar)
    selector = sm3(le(session_id, 4) + vin[::-1].encode())
    offset = (selector[0] >> 4) * 5
    card = password_card.encode('ascii')
    material = card[offset:offset + 5] + secret
    digest = sm3(material)
    alphabet = b"0123456789abcdef"
    hx = bytearray()
    for byte in digest:
        hx.append(alphabet[(byte >> 4) & 0xF])
        hx.append(alphabet[byte & 0xF])
    key = bytes(hx[0:16])
    iv = bytes(hx[48:64])
    return pub, key, iv, digest, offset, selector


if __name__ == "__main__":
    v = json.load(open(r'D:\DP\tv_sm2-vectors.json', encoding='utf-8'))
    local_pt = decode_point(bytes.fromhex(v["local"]))
    peer_pt = decode_point(bytes.fromhex(v["peer"]))

    # 用 scalar=1 复现 local，scalar=2 复现 peer，验证曲线上运算
    assert enc_point(mul(1, G)) == bytes.fromhex(v["local"]), "G*1 不符"
    assert enc_point(mul(2, G)) == bytes.fromhex(v["peer"]), "G*2 不符"
    print("EC 点乘 OK")

    assert identity_digest(local_pt).hex() == v["zLocal"], identity_digest(local_pt).hex()
    assert identity_digest(peer_pt).hex() == v["zPeer"], identity_digest(peer_pt).hex()
    print("ZA 摘要 OK  (identityDigest 完全对齐)")

    # 联合标量 = 2 * (xbar(peer)+1) * 1 * (xbar(local)+1) mod n
    combined = 2 * (xbar(peer_pt) + 1) * 1 * (xbar(local_pt) + 1) % N
    shared_pt = mul(combined, G)
    assert enc_point(shared_pt).hex() == v["shared"], "shared 不符"
    print("共享点 OK")

    kdf = sm3(enc_point(shared_pt)[1:] + identity_digest(local_pt) + identity_digest(peer_pt)
              + bytes.fromhex("00000001"))
    assert kdf.hex() == v["kdf"], (kdf.hex(), v["kdf"])
    print("KDF OK  (agree() 的 SM3 材料完全对齐)")

    # 验证 agree() 函数本身
    pub, secret = agree(peer_pt, 1)
    assert pub == bytes.fromhex(v["local"]), "agree publicKey 不符"
    assert secret.hex() == v["kdf"], "agree sharedSecret 不符"
    print("agree() OK")

    vin = "TESTVIN0000000001"
    sid = 0x78563412
    card = "0123456789abcdef" * 5
    pub2, key, iv, digest, off, sel = derive_session(peer_pt, 1, sid, vin, card)
    assert sel.hex() == v["selector"], (sel.hex(), v["selector"])
    assert off == v["cardOffset"]
    assert digest.hex() == v["derived"], (digest.hex(), v["derived"])
    # JS 侧 key/iv 存的是 ASCII 字符串本身，不是 hex
    assert key.decode() == v["key"], (key.decode(), v["key"])
    assert iv.decode() == v["iv"], (iv.decode(), v["iv"])
    print("deriveSession OK  key=%s iv=%s offset=%d" % (key.decode(), iv.decode(), off))

    # ---------- 帧构造 ----------
    def wrap(plain):
        ct = sm4_cbc_encrypt(key, iv, plain)
        payload = base64.b64encode(ct)
        return b'\xaa\xab' + le(len(payload), 4) + payload

    def crc8(b):
        c = 0
        for byte in b:
            c ^= byte
            for _ in range(8):
                c = ((c << 1) ^ (7 if c & 0x80 else 0)) & 0xFF
        return c

    ts = 1800000000
    for name, cid in (("unlock", 1), ("lock", 2)):
        body = le(ts, 8) + bytes([cid])
        assert wrap(bytes([crc8(body)]) + body).hex() == v[name], (name, wrap(bytes([crc8(body)]) + body).hex())
    print("控车帧 OK (unlock/lock 字节级一致)")

    for item in v["responses"]:
        assert wrap(item["text"].encode()).hex() == item["frame"], item["text"]
        # 反向解密
        raw = bytes.fromhex(item["frame"])
        n = int.from_bytes(raw[2:6], 'little')
        dec = sm4_cbc_decrypt(key, iv, base64.b64decode(raw[6:6 + n]))
        assert dec.decode() == item["text"], (dec, item["text"])
    print("响应解码 OK")

    # malformed UTF-8
    raw = bytes.fromhex(v["malformedUtf8Frame"])
    n = int.from_bytes(raw[2:6], 'little')
    dec = sm4_cbc_decrypt(key, iv, base64.b64decode(raw[6:6 + n]))
    try:
        dec.decode('utf-8')
        print("malformed: 意外解码成功")
    except UnicodeDecodeError:
        print("malformed UTF-8 帧 -> 解码失败（应判为 Unknown）OK")

    # ---------- 认证帧 ----------
    sig = bytes(range(1, 17))
    for minor, expect in ((8, v["authentication8"]), (9, v["authentication9"])):
        cfg = "56;2.00;08;16;1;0;0;0;" if minor >= 9 else "56;2.00;08;16;0;0;"
        text = "%d;v1;test-account;test-device;%s;1700000000;1900000000;%s" % (ts, vin, cfg)
        t = text.encode()
        plain = le(len(t), 4) + t + sig
        payload = le(sid, 4) + pub + base64.b64encode(sm4_cbc_encrypt(key, iv, plain)) + bytes([1, 9])
        frame = b'\xaa\xae' + le(len(payload), 2) + payload
        assert base64.b64encode(frame).decode() == expect, minor
    print("认证帧 OK (minor 8 / 9 均字节级一致)")
    print("\n===== 全部 SM2/SM3/SM4/BLE 协议验证通过 =====")
