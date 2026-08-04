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
function Write-Warn($Text)   { Write-Host "  ⚠  $Text" -ForegroundColor DarkYellow }
function Write-Error2($Text) { Write-Host "  ✗ $Text" -ForegroundColor Red }
function Write-Info($Text)   { Write-Host "  $Text" -ForegroundColor DarkGray }

# ---- 定位脚本源（本地 vs 远程）----
$LocalDir = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $null }
$RemoteBranches = @("nodeVersion", "main")
function Get-RemoteScript {
    param([string]$File, [string]$Dest)
    if ($env:SETUP_REMOTE_BASE) {
        try { Invoke-WebRequest -Uri "$env:SETUP_REMOTE_BASE/$File" -OutFile $Dest -UseBasicParsing -ErrorAction Stop; return $true } catch { return $false }
    }
    foreach ($b in $RemoteBranches) {
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/BowiEgo/DevTermSetup/$b/$File" -OutFile $Dest -UseBasicParsing -ErrorAction Stop
            return $true
        } catch {}
    }
    return $false
}

# ---- 代理检测（在安装 Node 之前）----
Write-Host ""
Write-Host "  DevTermSetup · 引导" -ForegroundColor Cyan
Write-Host ""
Write-Info "当前 http_proxy  = $(if($env:http_proxy){$env:http_proxy}else{'未设置'})"
Write-Info "当前 https_proxy = $(if($env:https_proxy){$env:https_proxy}else{'未设置'})"
Write-Host ""
$default = if ($env:https_proxy) { $env:https_proxy } else { "http://127.0.0.1:7890" }
Write-Info "回车使用默认: $default（输入覆盖；输入 direct 表示直连）"
$proxy_ok = Read-Host "  代理地址"
if ([string]::IsNullOrWhiteSpace($proxy_ok)) { $proxy_ok = $default }
if ($proxy_ok -match "^(direct|none|off)$") {
    Write-Warn "已选择直连（不使用代理）"
} elseif ($proxy_ok) {
    $env:http_proxy = $env:https_proxy = $env:HTTP_PROXY = $env:HTTPS_PROXY = $env:all_proxy = $proxy_ok
    Write-Success "已使用代理: $proxy_ok"
    Write-Info "验证代理连通性..."
    try {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com" -Proxy $proxy_ok -TimeoutSec 8 -UseBasicParsing -Method Head -ErrorAction Stop | Out-Null
        Write-Success "代理可用"
    } catch {
        Write-Warn "代理验证失败，继续尝试直连（可能较慢）"
    }
}
Write-Host ""

# ---- 确保 Node.js (>= 18) ----
function Get-NodeMajor {
    try {
        $v = (& node -v) 2>$null
        if ($v -match 'v?(\d+)') { return [int]$Matches[1] }
    } catch {}
    return 0
}

$nodeMajor = Get-NodeMajor
if ($nodeMajor -ge 18) {
    Write-Success "Node.js $(& node -v) 已就绪"
} else {
    Write-Info "未检测到 Node.js，正在安装..."
    $wingetArgs = @("install", "--id", "OpenJS.NodeJS", "-e", "--silent", "--accept-package-agreements", "--accept-source-agreements")
    if ($env:https_proxy) { $wingetArgs += @("--proxy", $env:https_proxy) }
    winget @wingetArgs 2>&1 | Out-Null
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
    if (-not (Get-RemoteScript "devterm-setup.js" $JS)) {
        Write-Error2 "下载失败，请检查网络"
        exit 1
    }
}

# 运行 Node 安装程序（保留代理环境变量）
& node $JS @args
exit $LASTEXITCODE
