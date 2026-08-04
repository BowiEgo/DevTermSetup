# ============================================
#  终端一键配置脚本 (Windows PowerShell)
#  使用方式: .\setup_terminal_windows.ps1
#  权限不足时: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
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

# 详细日志文件（记录每个安装步骤与输出）
$ScriptLog = Join-Path $env:TEMP ("devtermsetup-" + (Get-Date -Format 'yyyyMMddHHmmss') + ".log")
function Write-Log($Text) {
    try { Add-Content -Path $ScriptLog -Value $Text -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}

function Invoke-Pending($Msg, $ScriptBlock) {
    Write-Host "  ⏳ $Msg ... " -NoNewline -ForegroundColor Yellow
    Write-Log "==> $Msg"
    # 同步执行：脚本块与调用方同作用域，父级变量/代理环境变量直接可用；
    # 脚本块须以显式布尔表达式结尾（如 $LASTEXITCODE -eq 0）表示成败。
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = & $ScriptBlock
    $sw.Stop()
    $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($ok) {
        Write-Host "`r  ✓ $Msg 完成 (${secs}s)" -ForegroundColor Green
        Write-Log "==> OK: $Msg (${secs}s)"
        return $true
    }
    Write-Host "`r  ✗ $Msg 失败 (${secs}s)" -ForegroundColor Red
    Write-Log "==> FAIL: $Msg (${secs}s)"
    return $false
}

# 实时流式执行本机命令：逐步显示每一步输出与耗时，返回成败
function Invoke-Streaming($Label, [string[]]$CommandArgs) {
    if (-not $CommandArgs -or $CommandArgs.Count -eq 0) { return $false }
    Write-Host "  ┌─ $Label" -ForegroundColor Yellow
    Write-Log "==> $Label"
    $cmdExe = Get-Command $CommandArgs[0] -ErrorAction SilentlyContinue
    if (-not $cmdExe) {
        Write-Host "  └─ ✗ $Label 失败 (未找到命令 $($CommandArgs[0]))" -ForegroundColor Red
        Write-Log "==> FAIL: $Label (未找到命令 $($CommandArgs[0]))"
        return $false
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $cmdName = $CommandArgs[0]
    $cmdArgs = if ($CommandArgs.Count -gt 1) { @($CommandArgs[1..($CommandArgs.Count - 1)]) } else { @() }
    & $cmdName @cmdArgs 2>&1 | ForEach-Object {
        $text = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { "$_" }
        $text = $text -replace "`r", ""
        if ($text) {
            Write-Host "  │ $text" -ForegroundColor DarkGray
            Write-Log "  │ $text"
        }
    }
    $ok = ($LASTEXITCODE -eq 0)
    $sw.Stop()
    $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($ok) {
        Write-Host "  └─ ✓ $Label 完成 (${secs}s)" -ForegroundColor Green
        Write-Log "==> OK: $Label (${secs}s)"
    } else {
        Write-Host "  └─ ✗ $Label 失败 (${secs}s)" -ForegroundColor Red
        Write-Log "==> FAIL: $Label (${secs}s)"
    }
    return $ok
}

# ---- 检测包管理器 ----
$winget = $null; try { $winget = Get-Command winget -ErrorAction Stop } catch {}
$scoop  = $null; try { $scoop  = Get-Command scoop  -ErrorAction Stop } catch {}

# --------------------------------------------
Write-Box "🪟  终端一键配置 (Windows)"

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
        $env:http_proxy  = $proxy_ok
        $env:https_proxy = $proxy_ok
        $env:HTTP_PROXY  = $proxy_ok
        $env:HTTPS_PROXY = $proxy_ok
        $env:all_proxy   = $proxy_ok
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

function Install-Tool($Step, $Cmd, $WingetId, $ScoopId, [string[]]$OfficialArgs, [string]$OfficialInfo = "") {
    try {
        $exists = Get-Command $Cmd -ErrorAction Stop
        Write-Success "$Cmd 已安装 ($($exists.Source))"
        return $true
    } catch {}

    $n = 1
    if ($winget -and $WingetId) {
        if (Invoke-Streaming "[$Step.$n] winget 安装 $Cmd ($WingetId)" @("winget","install","--id",$WingetId,"--silent","--accept-package-agreements","--accept-source-agreements")) {
            Write-Success "$Cmd 安装完成"
            Refresh-Path
            return $true
        }
        Write-Warn "${Cmd}: winget 失败，尝试其他方式"
        $n++
    }
    if ($scoop -and $ScoopId) {
        if (Invoke-Streaming "[$Step.$n] scoop 安装 $Cmd ($ScoopId)" @("scoop","install",$ScoopId)) {
            Write-Success "$Cmd 安装完成"
            Refresh-Path
            return $true
        }
        Write-Warn "${Cmd}: scoop 失败"
        $n++
    }
    if ($OfficialArgs) {
        Write-Host ""
        Write-Warn "无法自动安装 $Cmd"
        if ($OfficialInfo) { Write-Host "  ⚠  $OfficialInfo" -ForegroundColor DarkYellow }
        $answer = Read-Host "  是否使用官方安装器自动安装 $Cmd？[Y/n]"
        if ([string]::IsNullOrEmpty($answer)) { $answer = "y" }
        if ($answer -match "^y") {
            if (Invoke-Streaming "[$Step.$n] 官方安装器安装 $Cmd" $OfficialArgs) {
                Write-Success "$Cmd 安装完成"
                Refresh-Path
                return $true
            }
            Write-Warn "${Cmd}: 官方安装器安装失败"
        } else {
            Write-Warn "已跳过 $Cmd 自动安装"
        }
        $n++
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
    return $false
}

# Git 先装（Install-Tool 内部会自动刷新 PATH）
$null = Install-Tool "2.1" "git" "Git.Git" "git"

$null = Install-Tool "2.2" "wezterm" "wez.wezterm"           "wezterm"
$null = Install-Tool "2.3" "nvim"    "Neovim.Neovim"         "neovim"
$null = Install-Tool "2.4" "lazygit" "JesseDuffield.lazygit" "lazygit"
# herdr: 无 winget/scoop 包，失败后询问是否用官方安装器（预编译二进制）
$herdrInstaller = @("powershell.exe","-NoProfile","-ExecutionPolicy","Bypass","-c","irm https://herdr.dev/install.ps1 | iex")
$herdrInfo = "Herdr 官方安装器将下载约 22MB 预编译二进制（含 ConPTY 组件），视网络情况约需 10 秒 - 2 分钟"
$null = Install-Tool "2.5" "herdr" "herdr.herdr" "herdr" $herdrInstaller $herdrInfo
Write-Host ""

# --------------------------------------------
Write-Step "3/4" "部署 WezTerm 配置"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$WeztermSrc = Join-Path $ScriptDir ".wezterm.lua"
$WeztermDst = Join-Path $env:USERPROFILE ".wezterm.lua"

if (Test-Path $WeztermSrc) {
    if (Test-Path $WeztermDst) {
        $Backup = "$WeztermDst.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $WeztermDst $Backup
        Write-Warn "已备份旧配置 → $(Split-Path $Backup -Leaf)"
    }
    Copy-Item $WeztermSrc $WeztermDst -Force
    Write-Success ".wezterm.lua → $WeztermDst"
}
else {
    Write-Error "未找到 $WeztermSrc"
}
Write-Host ""

# --------------------------------------------
Write-Step "4/4" "部署 Neovim 配置"

$NvimConfig = Join-Path $env:LOCALAPPDATA "nvim"
$RepoUrl    = "https://github.com/BowiEgo/my-nvim.git"

if (Test-Path $NvimConfig) {
    $Backup = "$NvimConfig.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Move-Item $NvimConfig $Backup
    Write-Warn "已备份旧 nvim 配置 → $(Split-Path $Backup -Leaf)"
}

$cloneOk = Invoke-Streaming "git clone my-nvim" @("git","clone","--progress",$RepoUrl,$NvimConfig)

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
Write-Host "  详细安装日志: $ScriptLog" -ForegroundColor DarkCyan
Write-Host ""

Read-Host "  按回车键退出..."
