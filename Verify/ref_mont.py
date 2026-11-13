"""32-bit limb Montgomery + Jacobian SM2 —— 与 Swift 版逐行对应的镜像实现，用于验证算法正确性。"""
import json, sys
sys.path.insert(0, r'D:\DP')

M32 = 0xFFFFFFFF

P = 0xFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF
N = 0xFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFF7203DF6B21C6052B53BBF40939D54123
A = 0xFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFC
B = 0x28E9FA9E9D9F5E344D5A9E4BCF6509A7F39789F515AB8F92DDBCBD414D940E93
GX = 0x32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7
GY = 0xBC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0


def to_limbs(v):
    return [(v >> (32 * i)) & M32 for i in range(8)]


def from_limbs(l):
    out = 0
    for i in range(7, -1, -1):
        out = (out << 32) | l[i]
    return out


def n0inv(m):
    return (-pow(m & M32, -1, 1 << 32)) & M32


def r2(m):
    return (1 << 512) % m


def rmod(m):
    return (1 << 256) % m


P_L = to_limbs(P); N_L = to_limbs(N)
P_N0 = n0inv(P); N_N0 = n0inv(N)
P_R2 = to_limbs(r2(P)); N_R2 = to_limbs(r2(N))
P_ONE = to_limbs(rmod(P)); N_ONE = to_limbs(rmod(N))


def cmp_l(a, b, n=8):
    for i in range(n - 1, -1, -1):
        if a[i] != b[i]:
            return 1 if a[i] > b[i] else -1
    return 0


def sub_mod(a, b, mod):
    """模减 a-b (mod m)，a,b < m"""
    out = [0] * 8
    borrow = 0
    for i in range(8):
        d = a[i] - b[i] - borrow
        if d < 0:
            d += 1 << 32
            borrow = 1
        else:
            borrow = 0
        out[i] = d
    if borrow:
        # 之前少了借位，结果等价于 a-b+2^256；补回 mod 并处理可能的溢出
        carry = 0
        for i in range(8):
            s = out[i] + mod[i] + carry
            out[i] = s & M32
            carry = s >> 32
        # carry 表示 a-b+2^256+mod >= 2^256，即 a-b+mod 已正确（语义上丢弃进位）
        if not carry and cmp_l(out, mod) >= 0:
            out = sub_mod_plain(out, mod)
    return out


def sub_mod_plain(a, b):
    out = [0] * 8
    borrow = 0
    for i in range(8):
        d = a[i] - b[i] - borrow
        if d < 0:
            d += 1 << 32
            borrow = 1
        else:
            borrow = 0
        out[i] = d
    return out


def add_mod(a, b, mod):
    out = [0] * 8
    carry = 0
    for i in range(8):
        s = a[i] + b[i] + carry
        out[i] = s & M32
        carry = s >> 32
    if carry or cmp_l(out, mod) >= 0:
        out = sub_mod_plain(out, mod)
    return out


def mont_mul(a, b, mod, n0):
    """CIOS Montgomery 乘法（就地变体，8 limb，32-bit 字）"""
    s = 8
    t = [0] * (s + 2)
    for i in range(s):
        c = 0
        for j in range(s):
            v = t[j] + a[j] * b[i] + c
            t[j] = v & M32
            c = v >> 32
        v = t[s] + c
        t[s] = v & M32
        t[s + 1] = v >> 32

        m = (t[0] * n0) & M32
        v = t[0] + m * mod[0]
        c = v >> 32
        for j in range(1, s):
            v = t[j] + m * mod[j] + c
            t[j - 1] = v & M32
            c = v >> 32
        v = t[s] + c
        t[s - 1] = v & M32
        t[s] = t[s + 1] + (v >> 32)

    out = t[0:s]
    # t < 2m，做一次条件减法即可；用补码减法（不对借位补 mod）
    if t[s] != 0 or cmp_l(out, mod) >= 0:
        out = sub_mod_plain(out, mod)
    return out


def pmul(a, b): return mont_mul(a, b, P_L, P_N0)
def padd(a, b): return add_mod(a, b, P_L)
def psub(a, b): return sub_mod(a, b, P_L)
def pdbl(a): return padd(a, a)
def p3(a): return padd(pdbl(a), a)   # 3a
def p4(a): return pdbl(pdbl(a))      # 4a
def p8(a): return pdbl(p4(a))        # 8a

def to_mont(a): return mont_mul(a, P_R2, P_L, P_N0)
def from_mont(a): return mont_mul(a, to_limbs(1), P_L, P_N0)


def ppow(base, exp):
    """exp 为普通整数；base 为普通形式；返回 Montgomery 域结果"""
    result = P_ONE[:]
    b = to_mont(base)
    e = exp
    while e:
        if e & 1:
            result = pmul(result, b)
        b = pmul(b, b)
        e >>= 1
    return result


def mpow_in_domain(a, exp):
    """a 已在 Montgomery 域；返回 Montgomery 域结果"""
    result = P_ONE[:]
    b = a[:]
    e = exp
    while e:
        if e & 1:
            result = pmul(result, b)
        b = pmul(b, b)
        e >>= 1
    return result


def pinv(a):
    return mpow_in_domain(a, P - 2)


# Jacobian: (X, Y, Z) in Montgomery domain
def jdouble(p):
    """SM2 曲线 a = p-3，用 a=-3 专用倍点公式"""
    X, Y, Z = p
    if is_inf(p) or from_limbs(Y) == 0:
        return inf_j()
    z2 = pmul(Z, Z)
    m = p3(pmul(psub(X, z2), padd(X, z2)))    # 3*(X²-Z⁴)
    b = pmul(Y, Y)                            # Y²
    s = p4(pmul(X, b))                        # 4XY²
    x3 = psub(pmul(m, m), pdbl(s))            # M²-2S
    b2 = pmul(b, b)                           # Y⁴
    b8 = p8(b2)                               # 8Y⁴
    y3 = psub(pmul(m, psub(s, x3)), b8)       # M(S-X3)-8Y⁴
    z3 = pdbl(pmul(Y, Z))                     # 2YZ
    return (x3, y3, z3)


def jadd(p, q):
    if is_inf(p):
        return q
    if is_inf(q):
        return p
    Z1Z1 = pmul(p[2], p[2])
    Z2Z2 = pmul(q[2], q[2])
    U1 = pmul(p[0], Z2Z2)
    U2 = pmul(q[0], Z1Z1)
    S1 = pmul(p[1], pmul(q[2], Z2Z2))
    S2 = pmul(q[1], pmul(p[2], Z1Z1))
    if cmp_l(U1, U2) == 0:
        if cmp_l(S1, S2) != 0:
            return inf_j()
        return jdouble(p)
    H = psub(U2, U1)
    I = pmul(pdbl(H), pdbl(H))          # (2H)²
    J = pmul(H, I)
    r = psub(S2, S1)
    r = padd(r, r)                       # 2(S2-S1)
    V = pmul(U1, I)
    X3 = psub(psub(pmul(r, r), J), pdbl(V))
    S1J = pmul(S1, J)
    Y3 = psub(pmul(r, psub(V, X3)), pdbl(S1J))
    zs = padd(p[2], q[2])
    Z3 = pmul(psub(psub(pmul(zs, zs), Z1Z1), Z2Z2), H)
    return (X3, Y3, Z3)


def inf_j():
    return (P_ONE[:], P_ONE[:], [0] * 8)


def is_inf(p):
    return all(x == 0 for x in p[2])


def jmul(k, point_affine_mont):
    result = inf_j()
    addend = (point_affine_mont[0], point_affine_mont[1], P_ONE[:])
    while k:
        if k & 1:
            result = jadd(result, addend)
        addend = jdouble(addend)
        k >>= 1
    return result


def to_affine(p):
    """返回普通整数坐标 (x, y)"""
    if is_inf(p):
        return None
    zi = pinv(p[2])
    zi2 = pmul(zi, zi)
    x = pmul(p[0], zi2)
    y = pmul(p[1], pmul(zi2, zi))
    return (from_limbs(from_mont(x)), from_limbs(from_mont(y)))


def g_mont():
    return (to_mont(to_limbs(GX)), to_mont(to_limbs(GY)))


if __name__ == "__main__":
    # 基本一致性
    assert from_limbs(from_mont(to_mont(to_limbs(GX)))) == GX
    print("Montgomery 往返 OK")

    # 标量乘验证
    G = g_mont()
    p1 = to_affine(jmul(1, G))
    assert p1 == (GX, GY), p1
    v = json.load(open(r'D:\DP\tv_sm2-vectors.json', encoding='utf-8'))
    p2 = to_affine(jmul(2, G))
    expect_peer = bytes.fromhex(v["peer"])
    assert p2[0] == int.from_bytes(expect_peer[1:33], 'big'), p2
    assert p2[1] == int.from_bytes(expect_peer[33:65], 'big'), p2
    print("G*2 OK")
    p1a = to_affine(jmul(1, G))
    assert p1a == (GX, GY)
    print("G*1 OK")

    # 大标量：k*G 再用 n-k*G 相加应为无穷
    k = 0x1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF
    pA = jmul(k, G)
    pB = jmul(N - k, G)
    s = jadd(pA, pB)
    assert is_inf(s), "k*G + (n-k)*G 应为无穷远点"
    print("标量乘 + 逆元一致性 OK")

    # 验证 agree() 用 Jacobian 路径能复现向量
    peer = (to_mont(to_limbs(int.from_bytes(expect_peer[1:33], 'big'))),
            to_mont(to_limbs(int.from_bytes(expect_peer[33:65], 'big'))))
    local = to_affine(jmul(1, G))
    xbar_local = (local[0] & ((1 << 127) - 1)) | (1 << 127)
    xbar_peer = (p2[0] & ((1 << 127) - 1)) | (1 << 127)
    local_factor = (xbar_local + 1) * 1 % N
    peer_factor = (xbar_peer + 1) % N
    tmp = to_affine(jmul(peer_factor, peer))
    shared_j = jmul(local_factor, (to_mont(to_limbs(tmp[0])), to_mont(to_limbs(tmp[1]))))
    shared = to_affine(shared_j)
    combined = bytes([4]) + shared[0].to_bytes(32, 'big') + shared[1].to_bytes(32, 'big')
    assert combined.hex() == v["shared"], (combined.hex(), v["shared"])
    print("Jacobian 路径共享点 OK")

    # 压缩点解码
    print("全部通过")
