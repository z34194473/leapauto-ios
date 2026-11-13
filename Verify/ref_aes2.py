"""逐行翻译当前 Compat.swift 的 expandKey + encryptBlock，验证 FIPS-197。"""
import re

s = open(r'D:\DP\LeapAutoiOS\LeapAuto\Compat.swift', encoding='utf-8').read()
m = re.search(r'sbox: \[UInt8\] = \[(.*?)\]', s, re.S)
SBOX = [int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{2})', m.group(1))]
RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]


def expandKey_swift(key):
    """精确对应 Swift 的 expandKey"""
    w = list(key)
    bytesGenerated = 16
    rci = 0
    temp = [0, 0, 0, 0]
    while bytesGenerated < 176:
        tailStart = bytesGenerated - 4
        for i in range(4):
            temp[i] = w[tailStart + i]
        if bytesGenerated % 16 == 0:
            t0 = temp[0]
            temp[0] = SBOX[temp[1]] ^ RCON[rci]
            temp[1] = SBOX[temp[2]]
            temp[2] = SBOX[temp[3]]
            temp[3] = SBOX[t0]
            rci += 1
        baseStart = bytesGenerated - 16
        for i in range(4):
            w.append(w[baseStart + i] ^ temp[i])
        bytesGenerated += 4
    return w


def xt(a):
    return ((a << 1) & 0xFF) ^ (0x1b if a & 0x80 else 0)


def encryptBlock_swift(block, w):
    """精确对应 Swift 的 encryptBlock"""
    st = list(block)
    for i in range(16):
        st[i] ^= w[i]
    for rnd in range(1, 11):
        for i in range(16):
            st[i] = SBOX[st[i]]
        t = list(st)
        for c in range(4):
            for r in range(4):
                t[r + 4 * c] = st[r + 4 * ((c + r) % 4)]
        st = t
        if rnd != 10:
            for c in range(4):
                i = 4 * c
                a0, a1, a2, a3 = st[i], st[i + 1], st[i + 2], st[i + 3]
                allb = a0 ^ a1 ^ a2 ^ a3
                st[i] = a0 ^ allb ^ xt(a0 ^ a1)
                st[i + 1] = a1 ^ allb ^ xt(a1 ^ a2)
                st[i + 2] = a2 ^ allb ^ xt(a2 ^ a3)
                st[i + 3] = a3 ^ allb ^ xt(a3 ^ a0)
        for i in range(16):
            st[i] ^= w[16 * rnd + i]
    return st


key = bytes.fromhex('000102030405060708090a0b0c0d0e0f')
pt = bytes.fromhex('00112233445566778899aabbccddeeff')
w = expandKey_swift(list(key))

print('=== 轮密钥对比 FIPS-197 A.1 ===')
expect_rk = [
    '000102030405060708090a0b0c0d0e0f',
    'd6aa74fdd2af72fadaa678f1d6ab76fe',
    'b692cf0b643dbdf1be9bc5006830b3fe',
    'b6ff744ed2c2c9bf6c590cbf0469bf41',
    '47f7f7bc95353e03f96c32bcfd058dfd',
    '3caaa3e8a99f9deb50f3af57adf622aa',
    '5e390f7df7a69296a7553dc10aa31f6b',
    '14f9701ae35fe28c440adf4d4ea9c026',
    '47438735a41c65b9e016baf4aebf7ad2',
    '549932d1f08557681093ed9cbe2c974e',
    '13111d7fe3944a17f307a78b4d2b30c5',
]
allok = True
for rnd, exp in enumerate(expect_rk):
    got = bytes(w[16 * rnd:16 * rnd + 16]).hex()
    ok = got == exp
    allok &= ok
    print(f'  rk{rnd:2d} {"OK " if ok else "BAD"} {got}')

print(f'\n轮密钥全部正确: {allok}')

ct = bytes(encryptBlock_swift(list(pt), w))
print(f'\n密文: {ct.hex()}')
print(f'标准: 69c4e0d86a7b0430d8cdb78070b4c55a')
print('加密正确' if ct.hex() == '69c4e0d86a7b0430d8cdb78070b4c55a' else '加密错误')

# 之前脚本的 w40 打印为何不符？检查我 expand_key 的 words 结构
words = [list(key[i*4:i*4+4]) for i in range(4)]
for i in range(4, 44):
    t = list(words[i-1])
    if i % 4 == 0:
        t = t[1:] + t[:1]
        t = [SBOX[b] for b in t]
        t[0] ^= RCON[i//4-1]
    words.append([words[i-4][j] ^ t[j] for j in range(4)])
print('\n比较两种展开的第 40 个 word:')
print('  按 word 方式:', bytes(sum(words[40:41], [])).hex())
print('  按 byte 方式:', bytes(w[160:164]).hex())
