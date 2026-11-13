#!/bin/bash
# ============================================================
#  一键构建 iOS IPA（在 macOS 上运行）
#  用法：./build-ipa.sh [输出目录]
# ============================================================
set -euo pipefail

OUT_DIR="${1:-./dist}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==============================================="
echo "  LeapAuto iOS —— 一键构建 IPA"
echo "==============================================="

# ---- 1. 环境检查
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ 此脚本必须在 macOS 上运行（当前：$(uname)）"
    echo ""
    echo "可选方案："
    echo "  1. 用自己的 GitHub 账号跑 Actions（.github/workflows/build-ipa.yml）"
    echo "  2. 租一台云 Mac（MacStadium / MacinCloud / Scaleway）"
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "❌ 未找到 xcodebuild，请先安装 Xcode"
    echo "   App Store 搜索 Xcode，或 https://developer.apple.com/download/"
    exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "❌ Xcode 许可未接受，执行："
    echo "   sudo xcodebuild -license accept"
    exit 1
fi

echo "✓ Xcode: $(xcodebuild -version | head -1)"
echo "✓ iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
echo ""

# ---- 2. 先跑算法验证（确保代码正确）
echo "[1/4] 编译并运行算法验证（81 项）..."
swiftc -O \
    LeapAuto/SM.swift LeapAuto/Crypto.swift LeapAuto/Compat.swift \
    LeapAuto/BLE.swift LeapAuto/Models.swift \
    Verify/Tests/algorithms/main.swift \
    -o /tmp/leap_algorithms
/tmp/leap_algorithms
echo ""

echo "[2/4] 编译并运行 UI 逻辑验证（114 项）..."
swiftc -O \
    LeapAuto/SM.swift LeapAuto/Crypto.swift LeapAuto/Compat.swift \
    LeapAuto/BLE.swift LeapAuto/Models.swift LeapAuto/LeapAPI.swift \
    Verify/Tests/uilogic/main.swift \
    -o /tmp/leap_uilogic
/tmp/leap_uilogic
echo ""

# ---- 3. 构建 archive
echo "[3/4] 构建 Release archive..."
rm -rf build
xcodebuild \
    -project LeapAuto.xcodeproj \
    -scheme LeapAuto \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath build \
    -archivePath build/LeapAuto.xcarchive \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="" \
    ENABLE_BITCODE=NO \
    archive 2>&1 | tee build/build.log | grep -E "error:|warning:|BUILD" || true

APP="build/LeapAuto.xcarchive/Products/Applications/LeapAuto.app"
if [[ ! -d "$APP" ]]; then
    echo ""
    echo "❌ 构建失败，最后 60 行日志："
    tail -60 build/build.log
    exit 1
fi
echo "✓ App 产物: $APP"
echo ""

# ---- 4. 打包 IPA
echo "[4/4] 打包 IPA..."
mkdir -p build/Payload
cp -R "$APP" build/Payload/
mkdir -p "$OUT_DIR"
( cd build && zip -qry "../$OUT_DIR/LeapAuto-unsigned.ipa" Payload )

IPA="$OUT_DIR/LeapAuto-unsigned.ipa"
echo ""
echo "==============================================="
echo "  ✅ 构建成功"
echo "==============================================="
echo "IPA: $IPA  ($(du -h "$IPA" | cut -f1))"
echo ""
echo "安装方式（任选其一）："
echo "  · Sideloadly：拖入 IPA → 输 Apple ID → Start"
echo "  · AltStore  ：同一 Wi-Fi + AltServer"
echo "  · Xcode     ：Product → Archive → Distribute App"
echo ""
echo "免费 Apple ID 签名有效期 7 天，到期重签即可。"
echo ""
echo "若要签名的 IPA（可直接装真机），在 Xcode 里："
echo "  Product → Archive → Distribute App → Custom → Development"
