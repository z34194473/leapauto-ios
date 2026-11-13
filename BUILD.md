# 构建 iOS IPA —— 完整指南

本项目是**完整的 Xcode 工程**，`open LeapAuto.xcodeproj` 即可构建。
下面按「你有 Mac」和「你没有 Mac」两种情况给出可执行路径。

---

## 已产出：可直接安装的 IPA

**本仓库的 GitHub Actions 已经构建成功，产物在 Actions 页面可下载。**

下载地址：<https://github.com/z34194473/leapauto-ios/actions/workflows/build-ipa.yml>
→ 点最近一次成功记录 → 页面底部 Artifacts → `LeapAuto-ipa`

已验证的产物信息：

| 项 | 值 |
|---|---|
| 文件名 | `LeapAuto-unsigned.ipa` |
| 大小 | 547 KB |
| 架构 | arm64（Magic `cffaedfe`，cputype `16777228`，filetype `2` = MH_EXECUTE）|
| Bundle ID | `com.leapauto.ios` |
| 最低系统 | iOS 16.0 |
| 蓝牙权限 | 已配置（中文描述）|
| 签名 | **未签名**（需自行签名后安装）|

### 关键：必须用 `macos-latest`

实测结论（2026-11）：

```
runs-on: macos-13   → 永远 queued，分配不到 runner
runs-on: macos-14   → 立即 cancelled，runner_name 为空
runs-on: macos-latest → 正常分配，构建成功 ✅
```

所以工作流里固定用 `macos-latest`。如果你 fork 后构建失败，先检查这一行。

### 重新构建

```bash
# 触发（改任意 LeapAuto/ 下文件 push 也会自动触发）
gh workflow run build-ipa.yml --repo z34194473/leapauto-ios
gh run watch --repo z34194473/leapauto-ios

# 下载
gh run download --repo z34194473/leapauto-ios -n LeapAuto-ipa
```

---

## 路线 A：自己的 Mac（最快，推荐）

### A-1. 环境
- macOS 13+，Xcode 15+（App Store 安装）
- 首次打开 Xcode 需同意许可：`sudo xcodebuild -license accept`

### A-2. 直接跑

```bash
git clone https://github.com/z34194473/leapauto-ios.git
cd leapauto-ios
open LeapAuto.xcodeproj
```

Xcode 里：
1. 选中 `LeapAuto` target → `Signing & Capabilities`
2. `Team` 选你的 Apple ID（免费账号即可，个人开发者证书 7 天有效期）
3. `Bundle Identifier` 若冲突，改成 `com.你的名字.leapauto`
4. 连上 iPhone，选中设备 → `⌘R` 运行

### A-3. 命令行出 IPA（unsigned）

```bash
cd leapauto-ios

xcodebuild \
  -project LeapAuto.xcodeproj \
  -scheme LeapAuto \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  -archivePath build/LeapAuto.xcarchive \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" ENABLE_BITCODE=NO \
  archive

mkdir -p build/Payload
cp -R build/LeapAuto.xcarchive/Products/Applications/LeapAuto.app build/Payload/
cd build && zip -qry LeapAuto-unsigned.ipa Payload && ls -lh LeapAuto-unsigned.ipa
```

### A-4. 出可安装 IPA（已签名）

**方式 1 — Xcode 导出（有 Apple ID 即可）**

`Product → Archive` → Organizer → `Distribute App` → `Custom` → `Development`
→ 选 Team → Export，得到可直装真机的 `.ipa`。

**方式 2 — 未签名 IPA + 重签工具（免费账号 7 天限制可用）**

```bash
# 用 ldid 伪造签名（越狱设备 / TrollStore 可直接装）
brew install ldid
ldid -S build/Payload/LeapAuto.app/LeapAuto
cd build && zip -qry LeapAuto-ldid.ipa Payload
```

或配合 **AltStore / Sideloadly / TrollStore** 侧载：
- 把 `LeapAuto-unsigned.ipa` 拖进 Sideloadly，登录 Apple ID 自动签名安装
- 免费 Apple ID：7 天有效期，到期重新签一次

---

## 路线 B：用自己的 GitHub 账号跑 Actions

如果你的 GitHub 账号有 macOS 额度（付费计划或额度未耗尽）：

```bash
# 1. fork 或直接推到你的仓库
git clone https://github.com/z34194473/leapauto-ios.git
cd leapauto-ios
git remote set-url origin https://github.com/<你的用户名>/leapauto-ios.git
git push -u origin master

# 2. 触发构建（也可以直接改一次 LeapAuto/ 下任意文件让 push 自动触发）
gh workflow run build-ipa.yml --repo <你的用户名>/leapauto-ios
gh run watch --repo <你的用户名>/leapauto-ios

# 3. 下载 artifact
gh run download --repo <你的用户名>/leapauto-ios -n LeapAuto-ipa
```

产物是 `LeapAuto-unsigned.ipa`，用 Sideloadly / AltStore 签名安装。

也可以在网页操作：仓库 → `Actions` → `Build iOS IPA` → `Run workflow`
→ 等完成后在 run 页面底部下载 `LeapAuto-ipa`。

---

## 路线 C：租一台云 Mac（一小时内）

| 服务 | 价格 | 说明 |
|---|---|---|
| MacStadium | 按小时 | 完整 Mac，SSH 进去按路线 A 操作 |
| MacinCloud | 按小时/天 | 有 Xcode 预装 |
| Scaleway Mac mini | 按小时 | 欧洲机房 |
| AWS EC2 mac2.metal | 按小时 | 需申请配额 |

拿到 SSH 后：

```bash
ssh user@your-mac
xcodebuild -version   # 确认 Xcode 已装

git clone https://github.com/z34194473/leapauto-ios.git
cd leapauto-ios
# 按路线 A-3 的命令构建
```

构建完成后用 `scp` 把 IPA 拉回本地：

```powershell
scp user@your-mac:~/leapauto-ios/build/LeapAuto-unsigned.ipa D:\DP\
```

---

## 安装到 iPhone

| 方式 | 前提 | 有效期 |
|---|---|---|
| Sideloadly（Windows/Mac 都有） | 任意 Apple ID | 免费 7 天，开发者账号 1 年 |
| AltStore | 同一 Wi-Fi + AltServer | 免费 7 天，自动续签 |
| TrollStore | iOS 14.0–16.6.1 特定版本 | 永久 |
| Xcode 直连 | Mac + 数据线 | 免费 7 天 |
| TestFlight | 开发者账号 | 90 天 |

Sideloadly 用法：把 `.ipa` 拖进去 → 输入 Apple ID → 连接 iPhone → Start。
首次安装后需在 iPhone `设置 → 通用 → VPN 与设备管理` 里信任开发者证书。

---

## 已知需要留意的点

**1. Bundle Identifier 冲突**
工程默认 `com.leapauto.ios`。若提示已被占用（极少见），改成任意唯一值：

```bash
# 命令行改
xcodebuild ... PRODUCT_BUNDLE_IDENTIFIER=com.yourname.leapauto.archive
```
或在 Xcode 的 Signing 面板里改。

**2. 免费证书的设备限制**
免费 Apple ID 只能同时签 3 个 App，且设备数受限。超了要吊销旧证书。

**3. 首次启动会请求蓝牙与通知权限**
必须允许，否则蓝牙钥匙无法工作。权限描述已在工程里配好。

**4. 登录建议用「凭据导入」**
iOS 无法生成数美 `smDeviceId`，短信登录可能被风控。从 Android 端导出
`accountId,token,refreshToken` 粘贴导入可完全绕开数美与极验。

---

## 构建产物说明

IPA 解包后结构：

```
Payload/
└── LeapAuto.app/
    ├── LeapAuto               # arm64 Mach-O 可执行文件
    ├── Info.plist
    ├── Assets.car
    └── ...
```

工程使用 `GENERATE_INFOPLIST_FILE = YES`，`Info.plist` 由 Xcode 生成，
里面已包含：
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`
- `NSLocationWhenInUseUsageDescription`
- `UISupportedInterfaceOrientations = Portrait`
- `UIUserInterfaceStyle = Dark`

---

## 验证构建前代码是否正确

无需 Mac，先在任意机器跑：

```bash
swiftc -O LeapAuto/SM.swift LeapAuto/Crypto.swift LeapAuto/Compat.swift \
       LeapAuto/BLE.swift LeapAuto/Models.swift \
       Verify/Tests/algorithms/main.swift -o algorithms && ./algorithms
# 期望：全部通过：81 项
```

Windows 上可用仓库里的 `Verify/run-algorithms.ps1`（需装 Swift 5.10 + MSVC + Windows SDK）。
