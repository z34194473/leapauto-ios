# 算法验证工程（Windows / Linux 可跑）

本目录用 **真实 Swift 编译器** 验证 `LeapAuto/` 里的核心算法，不依赖 Xcode / macOS。

## 环境要求

| 组件 | 版本 | 说明 |
|---|---|---|
| Swift Toolchain | 5.10.1 | [swift.org](https://www.swift.org/install/windows/) |
| VS Build Tools 2022 | 17.14+ | 需 MSVC x64 + Windows SDK |
| Windows SDK | 10.0.22621+ | Swift for Windows 的链接依赖 |

安装（winget）：

```powershell
winget install --id Swift.Toolchain.5.10.1
winget install --id Microsoft.VisualStudio.2022.BuildTools --override '--quiet --wait --norestart --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
winget install --id Microsoft.WindowsSDK.10.0.22621
```

## 运行

```powershell
# 1) 算法验证：SM2/SM3/SM4 + BLE 协议帧（81 项）
.\run-algorithms.ps1

# 2) UI 逻辑验证：状态派生 / 指令表 / 定时空调（114 项）
.\run-uilogic.ps1
```

脚本会自动：
1. 通过 `vcvars64.bat` 注入 MSVC 环境
2. 指向 Swift Windows SDK（`Platforms\5.10.1\Windows.platform\Developer\SDKs\Windows.sdk`）
3. 编译 `../LeapAuto/*.swift` + `Tests/*.swift`
4. 运行并返回退出码

## 验证覆盖

### `run-algorithms.ps1` —— 81 项

| 分组 | 内容 | 校验标准 |
|---|---|---|
| SM3 | `""` / `"abc"` / `"abcd"×16` | GB/T 32905-2016 标准向量 |
| SM4 | 单块加密、CBC 往返 | GB/T 32907-2016 标准向量 |
| 哈希 | MD5、md5Short、SHA256、HMAC-SHA256 | RFC 1321 / FIPS 180-4 / RFC 4231 |
| Montgomery | toMont 往返、montMul、montInverse、affine | 自校验 |
| SM2 曲线 | 1·G、2·G、k·G+(n-k)·G=∞、压缩点解码 | node-crypto 官方向量 |
| SM2 协商 | agree 公钥、共享密钥 | 官方 sm2-vectors |
| BLE 帧 | CRC8、MTU 分包、帧解码、证书摘要、标定、被动配置 | 官方 passive-vectors |
| BLE 端到端 | selector、会话密钥、unlock/lock 帧、4 种回执解码 | 官方向量逐字节 |
| 星期 | 掩码编解码、中文描述 | 自校验 |
| 指令 | 上下锁/后备箱/空调/座椅/方向盘/充电/哨兵 | cmdid + state 精确匹配 |
| 信号表 | SOC/续航/总里程/油量/充电/门锁/车窗 | 数字 ID → 命名字段 |
| 状态派生 | SOC 取整、续航模式、充电功率、剩余时间 | 业务规则 |

### `run-uilogic.ps1` —— 114 项

| 分组 | 内容 |
|---|---|
| 首页派生 | SOC/续航/里程/充电功率/电流绝对值/剩余时间/门锁/车窗/胎压/哨兵/手刹/后视镜/空调/位置/色调 |
| 车锁语义 | 已锁→显示解锁、未锁→显示上锁、未知态兜底 |
| 座椅档位 | 4 座 × 加热/通风，含越界钳制 |
| 自定义温度 | 16–32°C 钳制、≤26 制冷 / ≥27 制热、风量固定 7 |
| 定时空调 | cmdid=171 全字段、set_id 前缀、days 数组、解析往返、空/非法输入 |
| 星期选择 | 工作日/周末/每天快捷、中文描述 |
| 健康充电 | SOC 50–100 钳制 |
| 蓝牙阶段 | 10 个阶段的标签与 isBusy |
| MAC 规范化 | 紧凑/冒号格式、全零/全F/非法拒绝 |
| 指令表 | 29 条指令的 cmdid/state/label 完整性 + JSON 合法性 |
| 冰箱指令 | cmdid=500、温度钳制 |

## 已验证修复的 Bug

真实编译暴露了 4 个此前静态检查无法发现的错误：

| # | 位置 | 问题 | 后果 |
|---|---|---|---|
| 1 | `SM.swift` `pointMultiply` | MSB-first 遍历却用 LSB-first 的「先加后倍」顺序 | **所有 SM2 点乘结果全错**，蓝牙钥匙无法协商 |
| 2 | `Compat.swift` `AESFallback.expandKey` | 内层循环自增 `bytesGenerated` 污染基准索引 | 轮密钥错误，AES 加密结果非标准 |
| 3 | `BLE.swift` `createP256` | 无 `#if canImport(Security)` 保护 | 非 Apple 平台编译失败 |
| 4 | `LeapAPI.swift` 多处 | `??` 链过长（4–5 层） | Swift 类型推断超时，编译失败 |

## Python 参考实现

用于交叉验证 Swift 输出，独立于编译器：

| 文件 | 作用 |
|---|---|
| `ref_sm.py` | SM3 / SM4 参考实现（含 SM4 解密轮密钥反转） |
| `ref_sm2.py` | SM2 协商、ZA 摘要、会话派生、BLE 帧构造 |
| `ref_mont.py` | 32 位分肢 Montgomery + Jacobian 镜像实现 |
| `ref_aes2.py` | AES-128 参考实现（FIPS-197 全 11 组轮密钥校验） |
