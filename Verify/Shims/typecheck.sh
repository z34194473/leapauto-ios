#!/bin/bash
# ============================================================
#  SwiftUI 类型检查（无需 macOS）
#  用桩模块模拟 SwiftUI / CoreBluetooth / Combine，
#  让编译器验证 View 代码的语法与类型正确性。
#  用法：./typecheck.sh
# ============================================================
set -uo pipefail

SHIM_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SHIM_DIR/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==============================================="
echo "  SwiftUI 类型检查（桩模块）"
echo "==============================================="
echo ""

mkdir -p "$WORK/copy"

# ---- 1. 构建桩模块
echo "[1/4] 构建桩模块..."
build_module() {
    local name="$1" src="$2"
    local out
    out=$(swiftc -emit-module -module-name "$name" \
              -emit-module-path "$WORK/$name.swiftmodule" \
              -I "$WORK" "$src" 2>&1)
    if echo "$out" | grep -q 'error:'; then
        echo "      ❌ $name 桩构建失败:"
        echo "$out" | grep 'error:' | sed 's/^/        /'
        return 1
    fi
    return 0
}

build_module Combine        "$SHIM_DIR/CombineShim2.swift"      || exit 1
build_module CoreBluetooth  "$SHIM_DIR/CoreBluetoothShim.swift"  || exit 1
build_module SwiftUI        "$SHIM_DIR/SwiftUIShim.swift"        || exit 1
echo "      ✓ Combine / CoreBluetooth / SwiftUI 桩已就绪"
echo ""

# ---- 2. 准备源文件副本
echo "[2/4] 准备源文件..."
for f in "$ROOT"/LeapAuto/*.swift; do
    name="$(basename "$f")"
    python3 - "$f" "$WORK/copy/$name" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
s = re.sub(r'^import UIKit\s*$', '', s, flags=re.M)
if ('@Published' in s or 'ObservableObject' in s) and 'import Combine' not in s:
    s = s.replace('import Foundation', 'import Foundation\nimport Combine', 1)
if 'import Foundation' not in s:
    lines = s.split('\n')
    for i, ln in enumerate(lines):
        if ln.startswith('import '):
            lines.insert(i, 'import Foundation'); break
    else:
        lines.insert(0, 'import Foundation')
    s = '\n'.join(lines)
open(dst, 'w', encoding='utf-8').write(s)
PY
done
echo "      ✓ $(ls -1 "$WORK/copy" | wc -l | tr -d ' ') 个文件"
echo ""

# ---- 3. 类型检查
echo "[3/4] 类型检查..."
OUTPUT=$(swiftc -typecheck -I "$WORK" "$WORK"/copy/*.swift 2>&1)
echo ""

# ---- 4. 结果
echo "[4/4] 结果"
echo "==============================================="

ALL_ERRORS=$(echo "$OUTPUT" | grep 'error:' | grep -v 'error: fatalError' || true)

if [ -z "$ALL_ERRORS" ]; then
    echo "  ✅ 全部通过，0 错误"
    exit 0
fi

# 已知平台差异（Apple 平台原生支持，Linux/Windows Foundation 缺失）
PLATFORM_DIFF=$(echo "$ALL_ERRORS" | grep -E 'URLSession|FoundationNetworking|no such module' || true)
REAL=$(echo "$ALL_ERRORS" | grep -vE 'URLSession|FoundationNetworking|no such module' || true)

if [ -z "$REAL" ]; then
    echo "  ✅ 通过（仅剩 Foundation 平台差异，非代码问题）"
    echo ""
    echo "  平台差异（Apple 平台原生支持）："
    echo "$PLATFORM_DIFF" | sed 's/^/    /'
    exit 0
fi

echo "  ❌ $(echo "$REAL" | grep -c 'error:') 个真实错误"
echo ""
echo "$REAL" | sed 's/^/  /'
if [ -n "$PLATFORM_DIFF" ]; then
    echo ""
    echo "  （另有平台差异 $(echo "$PLATFORM_DIFF" | grep -c 'error:') 处，已忽略）"
fi
exit 1
