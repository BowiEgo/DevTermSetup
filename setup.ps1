# ============================================
#  DevTermSetup — 引导脚本 (Windows)
#  仅负责：确保 Node.js 存在 → 运行 Node 安装程序
#
#  远程执行:
#    irm https://raw.githubusercontent.com/BowiEgo/DevTermSetup/main/setup.ps1 | iex
#  本地执行:
#    powershell -ExecutionPolicy Bypass -File setup.ps1 [install|repair|doctor]
# ============================================

$ErrorActionPreference = "Continue"

function Write-Success($Text) { Write-Host "  ✓ $Text" -ForegroundColor Green }
function Write-Error2($Text)  { Write-Host "  ✗ $Text" -ForegroundColor Red }
function Write-Info($Text)    { Write-Host "  $Text" -ForegroundColor DarkGray }

# ---- 定位脚本源（本地 vs 远程）----
$LocalDir = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $null }
$RemoteBase = if ($env:SETUP_REMOTE_BASE) { $env:SETUP_REMOTE_BASE } else { "https://raw.githubusercontent.com/BowiEgo/DevTermSetup/main" }

# ---- 确保 Node.js (>= 18) ----
function Get-NodeMajor {
    try {
        $v = (& node -v) 2>$null
        if ($v -match 'v?(\d+)') { return [int]$Matches[1] }
    } catch {}
    return 0
}

Write-Host ""
Write-Host "  DevTermSetup · 引导" -ForegroundColor Cyan

$nodeMajor = Get-NodeMajor
if ($nodeMajor -ge 18) {
    Write-Success "Node.js $(& node -v) 已就绪"
} else {
    Write-Info "未检测到 Node.js，正在安装..."
    winget install --id OpenJS.NodeJS -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    # 刷新 PATH
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + `
                [Environment]::GetEnvironmentVariable("Path", "User")
    $nodeMajor = Get-NodeMajor
    if ($nodeMajor -lt 18) {
        Write-Error2 "Node.js 安装失败，请手动安装: https://nodejs.org"
        exit 1
    }
    Write-Success "Node.js $(& node -v) 已就绪"
}

# ---- 获取并运行 Node 安装程序 ----
if ($LocalDir -and (Test-Path (Join-Path $LocalDir "devterm-setup.js"))) {
    $JS = Join-Path $LocalDir "devterm-setup.js"
} else {
    $JS = Join-Path $env:TEMP "devterm-setup.js"
    Write-Info "下载 devterm-setup.js ..."
    try {
        Invoke-WebRequest -Uri "$RemoteBase/devterm-setup.js" -OutFile $JS -UseBasicParsing
    } catch {
        Write-Error2 "下载失败，请检查网络"
        exit 1
    }
}

# 运行 Node 安装程序（保留代理环境变量）
& node $JS @args
exit $LASTEXITCODE
