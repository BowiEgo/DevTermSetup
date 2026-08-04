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
$RemoteBase = if ($env:SETUP_REMOTE_BASE) { $env:SETUP_REMOTE_BASE } else { "https://raw.githubusercontent.com/BowiEgo/DevTermSetup/main" }

# ---- 代理检测（在安装 Node 之前）----
Write-Host ""
Write-Host "  DevTermSetup · 引导" -ForegroundColor Cyan
Write-Host ""
Write-Info "http_proxy  = $(if($env:http_proxy){$env:http_proxy}else{'未设置'})"
Write-Info "https_proxy = $(if($env:https_proxy){$env:https_proxy}else{'未设置'})"
Write-Info "all_proxy   = $(if($env:all_proxy){$env:all_proxy}else{'未设置'})"
Write-Host ""
$proxy_ok = Read-Host "  代理设置是否正确？[Y/n/自定义地址]"
if ([string]::IsNullOrEmpty($proxy_ok)) { $proxy_ok = "y" }
switch -Wildcard ($proxy_ok) {
    "y*" {
        if ($env:http_proxy) {
            $env:HTTP_PROXY  = $env:http_proxy
            $env:HTTPS_PROXY = if($env:https_proxy){$env:https_proxy}else{$env:http_proxy}
            $env:all_proxy   = if($env:all_proxy){$env:all_proxy}else{$env:http_proxy}
            Write-Success "保持当前代理设置"
        } else {
            Write-Warn "未设置代理，将直连（可能较慢）"
        }
    }
    "n*" { Write-Warn "跳过代理设置（直连）" }
    default {
        $env:http_proxy = $env:https_proxy = $env:HTTP_PROXY = $env:HTTPS_PROXY = $env:all_proxy = $proxy_ok
        Write-Success "已临时激活代理: $proxy_ok"
    }
}
# 验证代理连通性
if ($env:https_proxy) {
    Write-Info "验证代理连通性..."
    try {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com" -Proxy $env:https_proxy -TimeoutSec 8 -UseBasicParsing -Method Head -ErrorAction Stop | Out-Null
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
