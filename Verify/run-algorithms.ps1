# 算法验证：SM2/SM3/SM4 + BLE 协议帧（81 项）
# 用法：.\run-algorithms.ps1

$ErrorActionPreference = 'Continue'

$root   = 'C:\Users\00\AppData\Local\Programs\Swift'
$tc     = Join-Path $root 'Toolchains\5.10.1+Asserts\usr\bin'
$rt     = Join-Path $root 'Runtimes\5.10.1\usr\bin'
$sdk    = Join-Path $root 'Platforms\5.10.1\Windows.platform\Developer\SDKs\Windows.sdk'
$vcvars = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'

if (-not (Test-Path $tc))    { Write-Host "Swift toolchain not found: $tc" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $vcvars)) { Write-Host "vcvars64.bat not found: $vcvars" -ForegroundColor Red; exit 1 }

# 注入 MSVC 环境
$envDump = cmd /c "`"$vcvars`" >nul 2>&1 && set"
foreach ($line in $envDump) {
    if ($line -match '^([^=]+)=(.*)$') {
        Set-Item -Path "env:$($matches[1])" -Value $matches[2] -ErrorAction SilentlyContinue
    }
}
$env:Path = "$tc;$rt;" + $env:Path

Set-Location $PSScriptRoot

$core    = @('SM.swift', 'Crypto.swift', 'Compat.swift', 'BLE.swift', 'Models.swift')
$sources = $core | ForEach-Object { Join-Path (Split-Path $PSScriptRoot -Parent) "LeapAuto\$_" }
$sources += Join-Path $PSScriptRoot 'Tests\algorithms\main.swift'

foreach ($s in $sources) {
    if (-not (Test-Path $s)) { Write-Host "MISSING: $s" -ForegroundColor Red; exit 1 }
}

Write-Host "Compiling algorithm verification ($($sources.Count) files)..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$out = & swiftc -sdk $sdk -O -module-name AlgorithmVerify @sources -o algorithms.exe 2>&1
$sw.Stop()
foreach ($l in $out) {
    if ("$l" -notmatch 'Creating library|\.lib and object') { Write-Host $l }
}
Write-Host ("Compile: {0:N1}s" -f $sw.Elapsed.TotalSeconds)

if (-not (Test-Path algorithms.exe)) { Write-Host "COMPILE FAILED" -ForegroundColor Red; exit 1 }

Write-Host "COMPILE OK, running..." -ForegroundColor Green
Write-Host ""
& .\algorithms.exe
exit $LASTEXITCODE
