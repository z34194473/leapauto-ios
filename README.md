# 零跑智控 iOS 版（从 Android APK 完整逆向移植）

> **状态：源码完整、经真实编译器验证，等待 macOS 环境产出 IPA。**
> 仓库：<https://github.com/z34194473/leapauto-ios>
> 构建方式见 [BUILD.md](BUILD.md)：有 Mac 就直接 `./build-ipa.sh`；没有就用 GitHub Actions 或云 Mac。


> 纯 Swift 单工程，零第三方依赖。国密 SM2/SM3/SM4、AES、RSA、两套云端签名、BLE 蓝牙钥匙协议全部本地实现。
> **已用真实 Swift 5.10.1 编译器在 Windows 上编译并运行 195 项验证，全部通过。**

---

## 一、验证结果

### 已用真实编译器验证（非静态检查）

| 套件 | 项数 | Windows 本地 | GitHub Linux CI |
|---|---|---|---|
| 算法层（SM2/SM3/SM4 + BLE 帧） | 81 | **全部通过** | **success** |
| UI 逻辑层（状态派生/指令表/定时空调） | 114 | **全部通过** | **success** |
| 真实协议层（访问零跑生产服务器） | 23 | **全部通过** | 见下说明 |
| 全量类型检查（16 文件 / 8282 行） | — | **仅 1 处平台差异** | — |

CI 运行记录：<https://github.com/z34194473/leapauto-ios/actions>

### 签名算法经零跑生产服务器确认

这是最强的正确性证据——不是"看着对"，而是**服务器判定通过**：

```
[正确签名]         → 302010202 第三方TOKEN失效   ← 签名通过，进入业务层
[错误签名/空签名]  → 302002002 签名信息校验失败  ← 签名被拒
```

同一个端点、同一份请求头，只有 `sign` 不同，服务器给出不同分支。
这证明 Swift 实现的 `sortAndConcat + SHA-256` 网关签名与官方 APK 完全一致。

### 全量类型检查结果

在 Windows 上无法编译 SwiftUI（Apple 独占），因此我构造了 **SwiftUI / CoreBluetooth / Combine 三个桩模块**，
用真实 Swift 5.10.1 编译器对全部 16 个源文件做类型检查，结果：

```
16 个源文件 → 唯一剩余错误：URLSession.data(for:) 在 Windows Foundation 上不存在
                （Apple 平台原生支持，非代码问题）
```

这个检查抓出了 3 个**只会在 macOS 上暴露**的编译错误，已在交付前修复：

| # | 文件 | 问题 | 后果 |
|---|---|---|---|
| 1 | `BluetoothView.swift` | 缺 `import Foundation` | `Date`/`DateFormatter` 不可见，编译失败 |
| 2 | `BluetoothView.swift` | `ActionButton` 参数顺序错：`tint` 写在 `active` 前 | 「参数顺序不匹配」编译失败 |
| 3 | `LeapAutoApp.swift` | `UINavigationBarAppearance().configureWithOpaqueBackground()` 空对象调用 | 无效代码，产生警告 |

### 真实编译暴露并修复的 4 个算法 Bug

这些静态检查、Python 镜像都没发现，真机编译器一跑就暴露：

| # | 位置 | 问题 | 后果 |
|---|---|---|---|
| 1 | `SM.swift` `pointMultiply` | MSB-first 遍历却用 LSB-first 的「先加后倍」顺序 | **所有 SM2 点乘全错**，蓝牙钥匙无法协商 |
| 2 | `Compat.swift` `expandKey` | 内层循环自增 `bytesGenerated` 污染基准索引 | 轮密钥错误，AES 不符 FIPS-197 |
| 3 | `BLE.swift` `createP256` | 缺 `#if canImport(Security)` | 非 Apple 平台编译失败 |
| 4 | `LeapAPI.swift` | `??` 链达 4–5 层 | Swift 类型推断超时 |

## 二、逆向对象

| 项目 | 值 |
|---|---|
| 来源 | `https://www.pgyer.com/lingpaozhikong` → `/app/install/ae5fcf930093867bbb1c70dd369221ea` |
| 下载说明 | 该 URL 直接返回 APK 字节流，`Content-Type` 伪装成 text/html，首字节 `50 4B 03 04`（PK/zip）。用 UA 伪装 + 直接落盘即可拿到原包 |
| 包名 / 版本 | `com.leapauto.app` / `4.5.15` (versionCode 4005015, build 110) |
| APK SHA-256 | `D0E69A824743180DF1A8DC72C983DD0549292B357DC63C8233F579B69F798408` |
| 大小 | 2 985 964 字节 |
| minSdk / targetSdk | 26 / 35（compileSdk 35） |
| 签名 | v2 only，`CN=LeapAuto, OU=Development, O=LeapAuto, L=Shanghai, C=CN`，SHA-1 `1965a4157617de1c387a138f23939985619e823c` |
| 加固 | **无壳**。classes.dex 明文，ProGuard 仅重命名类名（`defpackage.CF` 等），逻辑完整可读 |
| 反调试 | **无**。`AppSignatureGuard` 只校验自身签名，不拦调试 |
| 风控 | 数美 `libsmsdk.so` + `assets/shumei.dex`（organization `mRCScLRggvJAYnjU7WgS`，appId `default`） |
| 验证码 | 极验 v4（`static.geetest.com/v4/gt4.js`），仅当服务端返回 `data.risk_type` 时触发 |
| 上游源码 | 作者开源 `github.com/stephenwang1011/leapauto`（Kotlin，用于交叉验证全部协议细节） |

---

## 三、云端协议（全部实证）

### 2.1 短信登录三步

```
GET  https://appuser.leapmotor.cn/app-user/applogin/compliance/sendmessagecode?phoneNo=<RSA密文>
POST https://appuser.leapmotor.cn/app-user/applogin/check_login_with_phone
       ?phoneNoCiphertext=<RSA密文>&smsCode=<验证码>&deviceID=<32位hex>
       &smDeviceId=<数美设备号>&os=android&pageUrl=
POST https://app-gw-global-master.leapmotor.com/base/base-user/account/v1/login
       {"identifier":accountId,"identifierType":"1","security":<旧token>}
```

- 手机号：`RSA/ECB/PKCS1Padding`，**1024 位公钥硬编码**在 `HM.K()`，已提取进 `Crypto.swift`
- 密文编码：base64url 去掉 `=` 填充
- 参数全部走 query，body 为空（`HQ.k(..., post=true)` 传的是空 body）

### 2.2 两套签名并存

**旧链路（appgateway / appuser）** — `CF.W()`

```python
m = {timespan, nonce, deviceID, token} ∪ 业务参数
signStr = md5_hex(concat(sorted_by_key(values)))[8:24]   # 取 16 字符
# 签完把 token 从参数里剔除，只回传 signStr
```

**新网关（app-gw-global-master / appRegion）** — `CF.U()`

```python
sign_base = concat(sorted(8 个公共签名头 + 业务参数 的值))
# 未登录：sign = sha256_hex(sign_base)
# 已登录：sign = hmac_sha256_hex(signKey, sign_base)
```

公共签名头（**只比值、按键名排序**）：
`acceptLanguage=zh-CN, channel=1, deviceId, deviceType=android, nonce, source=leapmotor, timestamp, version=1.23.00`

完整请求头另含：`x-region: CN`、`x-api-signature-version: 2.0`、`digest: ""`、`userId`、`carvin`、`cartype`、`x-subversion: 3.24.5-1`、`token`

### 2.3 signKey 派生（最隐蔽的门槛）

```python
signKey = base64url(jwt_parts[2]) XOR base64(r2) XOR base64(r3)   # 取三者最短长度
```

`r2`/`r3` 由网关登录响应的 `data.signParam` 下发。

**关键坑**：`signKey` 与 deviceId 绑定 —— JWT payload 的 `user_name` 字段内嵌 `deviceId:<32位hex>`。换到新网关后**必须把本地 deviceId 换成 token 里的那个**，否则所有签名请求全 401。`LeapAPI.extractNewAuth` 已自动切换。

### 2.4 控车

```
POST https://appgateway.leapmotor.com/app/app-control-service/v3/api/appremotectl
     form: cmdid / state / carvin / oppwd / nonce / deviceID / signStr / timespan
GET  .../appremotectl/query?msgID=...
```

`oppwd` = `AES-128-CBC/PKCS7(pin)`，key = `md5Short(token[0:32])`，iv = `md5Short(token[32:64])`，token 取网关 accessToken（回退旧 token）。

### 2.5 cmdid 全表（来自 APK `AbstractC0443Qy` + 官方抓包）

| cmdid | state | 功能 |
|---|---|---|
| 110 | `{"value":"lock"}` / `"unlock"` | 上锁 / 解锁 |
| 120 | `{"value":"true"}` | 鸣笛寻车 |
| 130 | `{"value":"true"}` / `"false"` | 开 / 关后备箱 |
| 131 | `{"value":"100"}` / `"0"` | 开 / 关前备箱 |
| 160 | `{"value":"ptcon"}` / `"ptcoff"` | 电池预热开 / 关 |
| 161 | `{"controls":[{on,set_id,start_time,update_time,days}]}` | 预约电池预热 |
| 170 | `{"operate":"auto","temperature":"24","windlevel":"2","mode":"nohotcold","circle":"in","wshld":"1","position":"all"}` | 开空调 |
| 170 | `{"operate":"off",...}` | 关空调 |
| 170 | 极速降温 / 极速升温 / 除雾 / 快速除味 | 各预设 state |
| 171 | `{"controls":[{...temperature,windlevel,mode,circle,wshld,days}]}` | 定时空调 |
| 190 | `{"chargeEnable","chargesoc","circulation","cycles","starttime","endtime","recharge"}` | 预约充电 |
| 192 | `{"operation":"unlock"}` | 解锁充电枪 |
| 193 | `{"value":"start"}` / `"finish"` | 开始 / 停止充电 |
| 230 | `{"value":"0"}` / `"2"` / `"5"` | 车窗全关 / 通风 / 半开 |
| 240 | `{"value":"10"}` / `"0"` | 遮阳帘开 / 关 |
| 300 | `{"value":"1"}` / `"0"` | 天窗开 / 关 |
| 301 | `{"position":"left_front","level":"0-3"}` | 座椅加热 |
| 320 | `{"level":"0-2"}` | 方向盘加热 |
| 370 | `{"position":"left_front","level":"0-3"}` | 座椅通风 |
| 400 | `{"operation":"on"}` / `"off"` | 哨兵模式 |
| 440 | `{"value":"2"}` / `"1"` | 后视镜加热开 / 关 |
| 500 | `{"cycles","duration","enable","mode","parkEnable","style","temp","value"}` | 车载冰箱 |

### 2.6 车况

```
GET  https://app-gw-global-master.leapmotor.com/app/app-global-service/v1/vehicle/list
GET  .../app/app-global-service/v1/vehicle/getCarRoute?vin=
POST {appRegion}/app/app-signal-service/signal/info/query   body: {"vin":"..."}
GET  {appRegion}/carownerservice/v3/api/chassis/query       驻车环视照片
```

车况返回**数字信号 ID**，需查表。`Models.swift` 已完整移植 86 条信号映射（`1204`=SOC、`3260`=续航、`1318`=总里程、`2646/2653/2667/2660`=四轮胎压、`1298`=门锁、`3636`=哨兵 等），并处理了 `rangeMode` 标准/动态续航切换。

---

## 四、BLE 蓝牙钥匙

### 3.1 传输层

| 项 | 值 |
|---|---|
| Service UUID | `0000FFFE-0000-1000-8000-00805F9B34FB` |
| Characteristic | `0000FFF2-0000-1000-8000-00805F9B34FB` |
| 帧头 | `0xAA` + 类型 |
| 帧类型 | `0xAB` 加密(6B头) / `0xAC` 事件(10B头) / `0xAE` 认证(4B头) / `0xEE` 重连(4B头) |
| 分包上限 | `min(max(MTU-3, 20), 160)` |
| CRC8 | 多项式 `0x07`，用于控车命令体 |

### 3.2 会话密钥派生（`BleKeyProtocol.deriveSession`）

```python
selector = HASH(le32(sessionId) + utf8(vin[::-1]))        # vin 反转
offset   = (selector[0] >> 4) * 5                          # 0..75
material = passwordCard[offset:offset+5] + sharedSecret
digest   = HASH(material)                                  # SM3 或 SHA-256
hex      = lowercase_hex_ascii(digest)                     # 64 字符
key      = hex[0:16]      # 16 字节 ASCII
iv       = hex[48:64]     # 16 字节 ASCII
```

`HASH` = SM3（keyType=1，SM4 加密）或 SHA-256（keyType=0，AES-128 加密）。

### 3.3 国密 SM2 协商（`BleSm2Crypto.agree`）

```
local  = d·G
shared = ((xbar(local)+1)·d) · ((xbar(peer)+1)·peer)
       = combined_scalar · peer
secret = SM3( X(shared) ‖ Y(shared) ‖ ZA(local) ‖ ZA(peer) ‖ 00000001 )
xbar(x) = (x mod 2^127) + 2^127
ZA(P)   = SM3( ENTL ‖ "1234567812345678" ‖ a ‖ b ‖ Gx ‖ Gy ‖ Px ‖ Py )
```

曲线 `sm2p256v1`，点乘用**自实现的 32 位分肢 Montgomery + Jacobian 坐标**（无 BouncyCastle 可用）。

### 3.4 认证帧

```
payload = le32(sessionId) ‖ 未压缩公钥(65B) ‖ base64(SM4/AES(plain)) ‖ 01 09
frame   = AA AE ‖ le16(len(payload)) ‖ payload

plain   = le32(len(text)) ‖ text ‖ signature
text    = "{epoch};{f0};{accountId};{deviceId};{f3};{f4};{f5};{校准};{flags};"
```

`flags` 分 8/9 两档：minor≥9 输出 4 位 `[enabled, autoLock, autoUnlock, button]`，否则 2 位。

### 3.5 控车与回执

```
command = le64(epoch) ‖ cmdid ‖ params
plain   = crc8(command) ‖ command
frame   = AA AB ‖ le32(len(b64)) ‖ base64(crypt(plain))
```

回执解密后为 `"type;...;"` 文本：`0;锁状态` 认证成功 / `1;hex` 重连凭据 / `2;id;result` 命令结果（`2;3;0` 或 `2;3;00` = 配置确认）。

### 3.6 已验证的官方向量（`verify_all.py`，22 项全 PASS）

```
SM3("abc")      = 66c7f0f4...8f4ba8e0      ✅ 对齐 GB/T 32905
SM4 单块        = 0123...3210 → 681edf34...36e4246   ✅
SM2 ZA(local)   = 5b32bfe3...8bc91de8      ✅
sharedSecret    = 5f86e6b1...5fdaf48b      ✅
deriveSession   = 6fa340d39f4141fe / 437410132db0dd25 (offset=15)  ✅
unlock/lock 帧  = 与官方 hex 逐字节一致     ✅
authentication8/9 = 与官方 base64 逐字节一致 ✅
8 种回执帧      = 全部解码正确              ✅
```

---

## 五、代码结构（16 文件 / 8384 行）

```
LeapAuto/
├── LeapAutoApp.swift     121  入口、TabView、导航栏/标签栏外观
├── Theme.swift           407  设计系统：卡片/按钮/环形电量/分段控件/步进器/档位选择
├── SM.swift              754  国密 SM2(点乘/协商) + SM3 + SM4，32 位分肢 Montgomery 自实现
├── Compat.swift          443  跨平台加密适配：Digest/Random/AES+MD5+SHA256 纯 Swift 兜底
├── Crypto.swift          287  RSA 手机号、AES 操作密码、MD5/SHA256/HMAC、signKey、JWT
├── BLE.swift             849  证书、标定、被动配置、帧编解码、会话密钥、认证/控车帧
├── LeapAPI.swift        1391  登录、双签名、车辆、车况、控车、预约、充电、BLE 证书
├── Models.swift          693  86 条信号表、状态快照、29 条 cmdid、星期编解码
├── LeapModel.swift       387  VM：登录态、车辆、状态、控车、预约、自动刷新
├── BluetoothKey.swift    609  CoreBluetooth 状态机：扫描→连接→MTU→订阅→认证→控车
├── LoginView.swift       300  短信登录 / 凭据导入 / 设备指纹
├── HomeView.swift        631  车辆概览、电量续航、快捷控制、门锁车窗胎压、驻车照片
├── ControlView.swift     640  车锁/空调/车身/座椅/充电 五个面板 + 温度/座椅/健康充电/预约
├── ScheduledAcEditor.swift 203  定时空调编辑（时间/星期/温度/风量/模式/循环）
├── BluetoothView.swift   290  证书同步、扫描、连接、蓝牙控车、诊断日志
└── SettingsView.swift    379  账号、车辆、刷新、诊断面板（可搜索原始信号）、关于

Verify/                    验证工程（Windows / Linux 可跑）
├── run-algorithms.ps1       81 项算法验证
├── run-uilogic.ps1         114 项 UI 逻辑验证
├── Tests/algorithms/main.swift
├── Tests/uilogic/main.swift
├── ref_sm.py  ref_sm2.py  ref_mont.py  ref_aes2.py   Python 交叉验证实现
└── README.md                环境安装与验证说明
```

### 跨平台编译策略

`Compat.swift` 通过 `#if canImport(...)` 让同一份源码在两处都能编译：

| 能力 | Apple 平台（iOS） | 非 Apple（验证用） |
|---|---|---|
| MD5 / SHA256 / HMAC | CryptoKit | 纯 Swift（RFC 1321 / FIPS 180-4 校验通过） |
| AES-128-CBC | CommonCrypto | 纯 Swift（FIPS-197 全 11 组轮密钥校验通过） |
| RSA / SM2 随机数 | Security.framework | 明确报错 / 时间熵兜底 |
| SM2 / SM3 / SM4 | **纯 Swift（两端一致）** | **纯 Swift** |
| URLSession async | Foundation 原生 | `withCheckedThrowingContinuation` 包装 |

iOS 构建行为完全不变 —— 只是给非 Apple 平台留了验证通道。

## 六、iOS 落地差异

| 环节 | Android | iOS 实现 |
|---|---|---|
| 设备指纹 | 数美 `SmAntiFraud.getDeviceId()` | iOS 无此 SDK。留空则用自身 32 位 hex；短信登录被风控时改走「凭据导入」 |
| 手机号加密 | `javax.crypto` RSA | `SecKeyCreateEncryptedData(.rsaEncryptionPKCS1)`，DER 手动剥 SPKI 头 |
| MD5 / SHA256 / HMAC | `MessageDigest` / `Mac` | `CryptoKit`（`Insecure.MD5` / `SHA256` / `HMAC<SHA256>`） |
| AES-CBC | `Cipher` | `CommonCrypto.CCCrypt`（PKCS7） |
| SM2/SM3/SM4 | BouncyCastle | **纯 Swift 自实现**（32 位分肢 Montgomery + Jacobian） |
| 极验 | WebView 嵌 gt4.js | 未内嵌。命中 `risk_type` 时明确提示走导入凭据 |
| 蓝牙 | `BluetoothGatt` 回调 | `CoreBluetooth`，MTU 由系统协商（用 `maximumWriteValueLength` 换算） |
| 后台常驻 | `ForegroundService` | iOS 不支持，蓝牙仅前台可用（符合系统限制） |

---

## 七、编译出 IPA

```bash
cd LeapAutoiOS
open LeapAuto.xcodeproj      # Xcode 15+，自动签名即可直装真机
```

命令行构建：

```bash
xcodebuild -project LeapAuto.xcodeproj -scheme LeapAuto \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath build/LeapAuto.xcarchive archive
```

导出 IPA：

```bash
cat > build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>development</string>
  <key>teamID</key><string>你的TeamID</string>
  <key>compileBitcode</key><false/>
  <key>stripSwiftSymbols</key><true/>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath build/LeapAuto.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/ipa
```

无开发者账号（侧载）：

```bash
xcodebuild -project LeapAuto.xcodeproj -scheme LeapAuto -configuration Release \
  -sdk iphoneos CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -derivedDataPath build/dd build

mkdir -p build/Payload
cp -R build/dd/Build/Products/Release-iphoneos/LeapAuto.app build/Payload/
ldid -S build/Payload/LeapAuto.app/LeapAuto
cd build && zip -qr LeapAuto.ipa Payload
```

---

## 八、验证脚本

两套验证工程在 `Verify/`，用真实 Swift 编译器运行：

```powershell
cd Verify

# 算法层 81 项（SM2/SM3/SM4 + BLE 帧）
.\run-algorithms.ps1

# UI 逻辑层 114 项（状态派生/指令表/定时空调）
.\run-uilogic.ps1
```

环境准备（一次性）：

```powershell
winget install --id Swift.Toolchain.5.10.1
winget install --id Microsoft.VisualStudio.2022.BuildTools --override '--quiet --wait --norestart --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
winget install --id Microsoft.WindowsSDK.10.0.22621
```

详见 `Verify/README.md`。

### Python 参考实现（独立于 Swift 的交叉验证）

| 文件 | 作用 |
|---|---|
| `ref_sm.py` | SM3 / SM4 参考实现 |
| `ref_sm2.py` | SM2 协商、ZA 摘要、会话派生、BLE 帧构造 |
| `ref_mont.py` | 32 位分肢 Montgomery + Jacobian 镜像实现 |
| `ref_aes2.py` | AES-128（FIPS-197 全 11 组轮密钥校验） |

---

## 九、已知限制

| 项 | 说明 |
|---|---|
| `smDeviceId` | 数美 SDK 仅 Android 版，iOS 无法生成。留输入框粘贴 Android 端值；强校验时走「凭据导入」 |
| 极验风控 | 未内嵌 gt4.js，命中 `risk_type` 时提示改用凭据导入 |
| 蓝牙后台 | iOS 不支持 Android 的 `ForegroundService` 常驻，蓝牙仅前台可用（系统限制） |
| P-256 证书 | 车端 `keyType=0` 走 Security.framework ECDH；目前实车证书多为 `keyType=1`（SM2 主路径，已完整实现） |
