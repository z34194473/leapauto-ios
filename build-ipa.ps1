# 一键构建 IPA（Windows PowerShell 版）
# 用途：在 Windows 上无法构建 iOS；此脚本打包工程并提示下一步
# 用法：.\build-ipa.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  LeapAuto iOS —— 构建准备" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# ---- 1. 本地算法自检（需要 Swift for Windows）
$swiftc = Get-Command swiftc -ErrorAction SilentlyContinue
if (-not $swiftc) {
    $guess = 'C:\Users\00\AppData\Local\Programs\Swift\Toolchains\5.10.1+Asserts\usr\bin\swiftc.exe'
    if (Test-Path $guess) { $swiftc = $guess }
}

if ($swiftc) {
    Write-Host "[1/3] 运行算法验证..." -ForegroundColor Yellow
    & "$root\Verify\run-algorithms.ps1" 2>&1 | Select-Object -Last 4
} else {
    Write-Host "[1/3] 跳过本地验证（未安装 Swift for Windows）" -ForegroundColor DarkGray
}

# ---- 2. 打包工程
Write-Host ""
Write-Host "[2/3] 打包完整工程..." -ForegroundColor Yellow
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$zip = Join-Path $root "LeapAuto-ios-$stamp.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

$exclude = @('build', 'dist', '.git')
$items = Get-ChildItem $root -Force | Where-Object { $exclude -notcontains $_.Name }
Compress-Archive -Path $items.FullName -DestinationPath $zip -Force
Write-Host "  ✓ $zip  ($([math]::Round((Get-Item $zip).Length/1KB,1)) KB)" -ForegroundColor Green

# ---- 3. 说明
Write-Host ""
Write-Host "[3/3] 下一步" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Windows 无法生成 iOS 二进制（需 Apple iOS SDK，仅随 Xcode 分发）。" -ForegroundColor Gray
Write-Host "  三种方式拿到 IPA：" -ForegroundColor Gray
Write-Host ""
Write-Host "  A. 有 Mac：" -ForegroundColor White
Write-Host "     解压 zip → cd LeapAuto → ./build-ipa.sh" -ForegroundColor Gray
Write-Host ""
Write-Host "  B. 用自己 GitHub 账号的 Actions（需 macOS runner 额度）：" -ForegroundColor White
Write-Host "     git push → Actions → Build iOS IPA → 下载 artifact" -ForegroundColor Gray
Write-Host ""
Write-Host "  C. 租云 Mac（MacStadium / MacinCloud / Scaleway，按小时）：" -ForegroundColor White
Write-Host "     ssh 进去 → ./build-ipa.sh → scp 拉回 IPA" -ForegroundColor Gray
Write-Host ""
Write-Host "  详见 BUILD.md" -ForegroundColor Cyan
Write-Host ""
Write-Host "  工程已推到 https://github.com/z34194473/leapauto-ios" -ForegroundColor Cyan
