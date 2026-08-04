# ============================================
#  终端一键配置 — Windows PowerShell
#
#  远程执行:
#    irm https://raw.githubusercontent.com/<user>/<repo>/main/setup.ps1 | iex
#
#  本地执行:
#    .\setup.ps1
# ============================================

$ErrorActionPreference = "Continue"

# ---- 辅助函数 ----
$W = 52

function Write-Box($Text, $Color = "Cyan") {
    $top    = "╭" + ("─" * $W) + "╮"
    $bottom = "╰" + ("─" * $W) + "╯"
    $pad    = ($W - $Text.Length - 2)
    $line   = "│  $Text" + (" " * [Math]::Max(0, $pad)) + "│"
    Write-Host ""
    Write-Host $top    -ForegroundColor $Color
    Write-Host $line   -ForegroundColor $Color
    Write-Host $bottom -ForegroundColor $Color
    Write-Host ""
}

function Write-Step($Num, $Text) {
    Write-Host "▸ [$Num] $Text" -ForegroundColor Yellow
    Write-Host ""
}

function Write-Success($Text) { Write-Host "  ✓ $Text" -ForegroundColor Green }
function Write-Warn($Text)    { Write-Host "  ⚠  $Text" -ForegroundColor DarkYellow }
function Write-Error($Text)   { Write-Host "  ✗ $Text" -ForegroundColor Red }
function Write-Info($Text)    { Write-Host "  $Text" -ForegroundColor DarkGray }
function Write-Divider()      { Write-Host ("  " + ("─" * 40)) -ForegroundColor DarkGray }

function Invoke-Pending($Msg, $ScriptBlock) {
    Write-Host "  ⏳ $Msg ... " -NoNewline -ForegroundColor Yellow
    # 同步执行：脚本块与调用方同作用域，父级变量/代理环境变量直接可用；
    # 脚本块须以显式布尔表达式结尾（如 $LASTEXITCODE -eq 0）表示成败。
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = & $ScriptBlock
    $sw.Stop()
    $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($ok) {
        Write-Host "`r  ✓ $Msg 完成 (${secs}s)" -ForegroundColor Green
        return $true
    }
    Write-Host "`r  ✗ $Msg 失败 (${secs}s)" -ForegroundColor Red
    return $false
}

# ---- 检测包管理器 ----
$winget = $null; try { $winget = Get-Command winget -ErrorAction Stop } catch {}
$scoop  = $null; try { $scoop  = Get-Command scoop  -ErrorAction Stop } catch {}

# ---- 定位脚本源（本地 vs 远程）----
$ScriptSource = if ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $env:TEMP
}
$IsRemote = ($MyInvocation.MyCommand.Path -eq $null)

# 远程执行时默认从 GitHub 拉取配置文件（可用 SETUP_REMOTE_BASE 覆盖）
if ($IsRemote -and -not $env:SETUP_REMOTE_BASE) {
    $env:SETUP_REMOTE_BASE = "https://raw.githubusercontent.com/BowiEgo/DevTermSetup/main"
}

# --------------------------------------------
Write-Box "🪟  终端一键配置 (Windows)"

Write-Info "平台: Windows"
if ($winget) { Write-Info "包管理器: winget" }
elseif ($scoop) { Write-Info "包管理器: scoop" }
else { Write-Error "未找到 winget 或 scoop，请手动安装工具" }
Write-Host ""

# --------------------------------------------
Write-Step "1/4" "网络代理设置"

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
        }
        Write-Success "保持当前代理设置"
    }
    "n*" {
        Write-Warn "已跳过代理设置"
    }
    default {
        $env:http_proxy = $env:https_proxy = $env:HTTP_PROXY = $env:HTTPS_PROXY = $env:all_proxy = $proxy_ok
        Write-Success "已临时激活代理: $proxy_ok"
    }
}
Write-Host ""

# --------------------------------------------
Write-Step "2/4" "检查终端工具"

# 合并 Machine/User PATH 并保留当前进程已有的额外条目（如 conda、临时路径）
function Refresh-Path {
    $combined = @()
    foreach ($part in @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User')
    )) {
        if ($part) { $combined += $part -split ';' }
    }
    foreach ($entry in ($env:Path -split ';')) {
        if ($entry -and ($combined -notcontains $entry)) { $combined += $entry }
    }
    $env:Path = ($combined | Where-Object { $_ } | Select-Object -Unique) -join ';'
}

function Install-Tool($Cmd, $WingetId, $ScoopId, [scriptblock]$Fallback, [string]$ManualHint = "") {
    try {
        $exists = Get-Command $Cmd -ErrorAction Stop
        Write-Success "$Cmd 已安装 ($($exists.Source))"
        return $true
    } catch {}

    if ($winget -and $WingetId) {
        if (Invoke-Pending "winget install $WingetId" {
            winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            $LASTEXITCODE -eq 0
        }) {
            Write-Success "$Cmd 安装完成"
            Refresh-Path
            return $true
        }
        Write-Warn "winget 安装 $Cmd 失败，尝试其他方式"
    }
    if ($scoop -and $ScoopId) {
        if (Invoke-Pending "scoop install $ScoopId" {
            scoop install $ScoopId 2>&1 | Out-Null
            $LASTEXITCODE -eq 0
        }) {
            Write-Success "$Cmd 安装完成"
            Refresh-Path
            return $true
        }
        Write-Warn "scoop 安装 $Cmd 失败"
    }
    if ($Fallback) {
        if (Invoke-Pending "cargo install $Cmd" $Fallback) {
            Write-Success "$Cmd 安装完成"
            Refresh-Path
            return $true
        }
        Write-Warn "cargo 安装 $Cmd 失败"
    }
    # 兜底：winget 对"已安装但无可用更新"会返回非零码，
    # 刷新 PATH 后重新检测，避免会话 PATH 过期导致误报失败
    Refresh-Path
    try {
        Get-Command $Cmd -ErrorAction Stop | Out-Null
        Write-Success "$Cmd 已可用"
        return $true
    } catch {}
    Write-Error "无法安装 $Cmd，请手动安装"
    if ($ManualHint) { Write-Warn $ManualHint }
    return $false
}

# Git 先装（Install-Tool 内部会自动刷新 PATH）
$null = Install-Tool "git" "Git.Git" "git"

$null = Install-Tool "wezterm" "wez.wezterm"                "wezterm"
$null = Install-Tool "nvim"    "Neovim.Neovim"              "neovim"
$null = Install-Tool "lazygit" "JesseDuffield.lazygit"      "lazygit"
# herdr 无 winget/scoop 包，回退 cargo install（与 Linux 脚本一致）
$null = Install-Tool "herdr"   "herdr.herdr"                "herdr" {
    try { cargo install herdr 2>&1 | Out-Null; $LASTEXITCODE -eq 0 } catch { $false }
} "手动安装: winget install Rustlang.Rustup 后执行 cargo install herdr"
Write-Host ""

# --------------------------------------------
Write-Step "3/4" "部署 WezTerm 配置"

$WeztermDst = Join-Path $env:USERPROFILE ".wezterm.lua"
$WeztermSrc = Join-Path $ScriptSource ".wezterm.lua"

# 也尝试从远程下载
function Download-Config($Filename, $Dest) {
    if ($env:SETUP_REMOTE_BASE) {
        if (Invoke-Pending "下载 $Filename" {
            try {
                Invoke-WebRequest -Uri "$env:SETUP_REMOTE_BASE/$Filename" -OutFile $Dest -ErrorAction Stop -UseBasicParsing | Out-Null
                $true
            } catch { $false }
        }) {
            return $true
        }
    }
    return $false
}

$copied = $false
if (Test-Path $WeztermSrc) {
    if (Test-Path $WeztermDst) {
        $Backup = "$WeztermDst.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $WeztermDst $Backup
        Write-Warn "已备份旧配置"
    }
    Copy-Item $WeztermSrc $WeztermDst -Force
    Write-Success ".wezterm.lua → $WeztermDst"
    $copied = $true
}
elseif (Download-Config ".wezterm.lua" $WeztermDst) {
    Write-Success ".wezterm.lua → $WeztermDst (远程)"
    $copied = $true
}

if (-not $copied) {
    Write-Warn "未找到 .wezterm.lua，跳过 WezTerm 配置"
    if ($IsRemote) {
        Write-Warn "提示: 远程下载失败，请检查网络，或用 SETUP_REMOTE_BASE 环境变量指定其他来源"
    }
}
Write-Host ""

# --------------------------------------------
Write-Step "4/4" "部署 Neovim 配置"

$NvimConfig = Join-Path $env:LOCALAPPDATA "nvim"
$RepoUrl    = "https://github.com/BowiEgo/my-nvim.git"

if (Test-Path $NvimConfig) {
    $Backup = "$NvimConfig.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Move-Item $NvimConfig $Backup
    Write-Warn "已备份旧 nvim 配置"
}

$cloneOk = Invoke-Pending "git clone my-nvim" {
    git clone $RepoUrl $NvimConfig 2>&1 | Out-Null
    $LASTEXITCODE -eq 0
}

if ($cloneOk -and (Test-Path (Join-Path $NvimConfig ".git"))) {
    Write-Success "nvim 配置克隆完成 → $NvimConfig"
}
else {
    Write-Error "克隆失败，请检查网络和仓库地址"
}
Write-Host ""

# --------------------------------------------
Write-Divider
Write-Host ""
Write-Host "  ✓  配置完成！" -ForegroundColor Green
Write-Host ""
Write-Host "  代理设置仅对当前 PowerShell 会话生效。" -ForegroundColor DarkGray
Write-Host "  持久化请以管理员身份运行：" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    [Environment]::SetEnvironmentVariable('http_proxy',  'your_proxy', 'User')" -ForegroundColor DarkCyan
Write-Host "    [Environment]::SetEnvironmentVariable('https_proxy', 'your_proxy', 'User')" -ForegroundColor DarkCyan
Write-Host ""

Read-Host "  按回车键退出..."
