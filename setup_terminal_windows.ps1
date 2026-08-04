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

# 流式执行本机命令：\r 进度原地刷新不堆叠，普通行逐行显示，返回成败
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

    # cmd /c "cmd args 2>&1" 合并 stderr→stdout，逐字节读取以支持 \r 进度刷新
    $argStr = @($CommandArgs | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/d /c `"$argStr 2>&1`""
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $reader = $p.StandardOutput.BaseStream
    $buf = New-Object byte[] 4096
    $cur = New-Object System.Text.StringBuilder
    $sawCR = $false
    $progWidth = 0
    $lastRefreshSeg = ""
    $logLine = ""
    try {
        while ($true) {
            $n = $reader.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            for ($i = 0; $i -lt $n; $i++) {
                $c = $buf[$i]
                if ($c -eq 10) {          # \n：一行结束
                    $seg = $cur.ToString().TrimEnd()
                    [void]$cur.Clear()
                    if ($sawCR) {         # 进度组/CRLF 行：补出最终段后换行
                        if ($seg) {
                            if ($seg.Length -lt $progWidth) { $seg = $seg.PadRight($progWidth) }
                            Write-Host "`r  │ $seg" -NoNewline -ForegroundColor DarkGray
                            $logLine = $seg.TrimEnd()
                        } elseif ($lastRefreshSeg) {
                            $logLine = $lastRefreshSeg
                        }
                        Write-Host ""
                    } elseif ($seg) {     # 普通 LF 行
                        Write-Host "  │ $seg" -ForegroundColor DarkGray
                        $logLine = $seg
                    }
                    if ($logLine) { Write-Log "  │ $logLine"; $logLine = "" }
                    $sawCR = $false
                    $progWidth = 0
                    $lastRefreshSeg = ""
                } elseif ($c -eq 13) {    # \r：进度刷新点
                    $seg = $cur.ToString().TrimEnd()
                    [void]$cur.Clear()
                    $sawCR = $true
                    if ($seg) {
                        if ($seg.Length -lt $progWidth) { $seg = $seg.PadRight($progWidth) } else { $progWidth = $seg.Length }
                        Write-Host "`r  │ $seg" -NoNewline -ForegroundColor DarkGray
                        $lastRefreshSeg = $seg.TrimEnd()
                    }
                } else {
                    [void]$cur.Append([char]$c)
                }
            }
        }
        # EOF 残留（输出未以换行结尾）
        $seg = $cur.ToString().TrimEnd()
        if ($seg) {
            if ($sawCR) {
                if ($seg.Length -lt $progWidth) { $seg = $seg.PadRight($progWidth) }
                Write-Host "`r  │ $seg" -NoNewline -ForegroundColor DarkGray
                Write-Host ""
            } else {
                Write-Host "  │ $seg" -ForegroundColor DarkGray
            }
            Write-Log "  │ $seg"
        } elseif ($sawCR) {
            Write-Host ""
        }
    } finally {
        $null = $p.WaitForExit()
        $reader.Close()
    }
    $ok = ($p.ExitCode -eq 0)
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

# 格式化下载进度行
function Format-DownloadProgress($Label, $Done, $Total, $Speed) {
    if ($Total -gt 0) {
        $pct = [math]::Min(100, [math]::Round($Done / $Total * 100, 1))
        $barLen = 20
        $fill = [int][math]::Floor($pct / 100 * $barLen)
        $bar = ('#' * $fill) + ('-' * ($barLen - $fill))
        return ("{0}: {1,7:N1} / {2:N1} MiB  ({3,5:N1}%)  [{4}]  {5:N2} MiB/s" -f $Label, ($Done / 1MB), ($Total / 1MB), $pct, $bar, $Speed)
    }
    return ("{0}: {1:N1} MiB  {2:N2} MiB/s" -f $Label, ($Done / 1MB), $Speed)
}

# 流式下载并实时显示进度（大小/百分比/速度，\r 原地刷新）
function Download-FileWithProgress($Url, $Dest, $Label = "下载") {
    Write-Host "  ┌─ $Label" -ForegroundColor Yellow
    Write-Log "==> $Label"
    try {
        # 兼容 TLS 1.2
        if (-not ([Net.ServicePointManager]::SecurityProtocol.ToString().Contains("Tls12"))) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        }
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.UserAgent = "DevTermSetup/1.0"
        $req.Timeout = 600000
        $req.ReadWriteTimeout = 600000
        $req.AllowAutoRedirect = $true
        if ($Url -like "https:*" -and $env:https_proxy) { $req.Proxy = New-Object System.Net.WebProxy($env:https_proxy) }
        elseif ($Url -like "http:*" -and $env:http_proxy) { $req.Proxy = New-Object System.Net.WebProxy($env:http_proxy) }

        $resp = $req.GetResponse()
        $total = [long]0
        try { $total = [long]$resp.ContentLength } catch {}
        if ($total -lt 0) { $total = 0 }
        $src = $resp.GetResponseStream()
        $fs = [System.IO.File]::Create($Dest)
        $buf = New-Object byte[] 65536
        $done = [long]0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $lastTick = [Environment]::TickCount
        $lastDone = [long]0
        $speed = 0.0
        $maxW = 0
        try {
            while ($true) {
                $n = $src.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }
                $fs.Write($buf, 0, $n)
                $done += $n
                $now = [Environment]::TickCount
                if ($now - $lastTick -ge 100) {
                    $speed = ($done - $lastDone) / [Math]::Max(1, ($now - $lastTick)) * 1000 / 1MB
                    $lastDone = $done; $lastTick = $now
                    $line = Format-DownloadProgress $Label $done $total $speed
                    if ($line.Length -lt $maxW) { $line = $line.PadRight($maxW) } else { $maxW = $line.Length }
                    Write-Host "`r  │ $line" -NoNewline -ForegroundColor DarkGray
                }
            }
        } finally {
            $fs.Close(); $src.Close(); $resp.Close()
        }
        $sw.Stop()
        $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        $speed = $done / [Math]::Max(1, $sw.Elapsed.TotalSeconds) / 1MB
        $line = Format-DownloadProgress $Label $done $total $speed
        if ($line.Length -lt $maxW) { $line = $line.PadRight($maxW) }
        Write-Host "`r  │ $line" -NoNewline -ForegroundColor DarkGray
        Write-Host ""
        Write-Log "  │ $line"
        if ($total -gt 0 -and $done -ne $total) {
            Write-Host "  └─ ⚠ $Label 下载不完整 ($done/$total 字节)" -ForegroundColor DarkYellow
            Write-Log "==> PARTIAL: $Label ($done/$total)"
            return $false
        }
        Write-Host "  └─ ✓ $Label 完成 (${secs}s)" -ForegroundColor Green
        Write-Log "==> OK: $Label (${secs}s)"
        return $true
    } catch {
        Write-Host "  └─ ✗ $Label 失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "==> FAIL: $Label $($_.Exception.Message)"
        return $false
    }
}

# 原生控制台执行（不重定向输出），让 winget 等显示自己的下载进度条；返回成败
function Invoke-Console($Label, [string[]]$CommandArgs) {
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
    # Start-Process -NoNewWindow：子进程直连控制台（winget 显示原生下载进度条），输出不被捕获
    $args2 = if ($CommandArgs.Count -gt 1) { @($CommandArgs[1..($CommandArgs.Count - 1)]) } else { @() }
    $p = Start-Process -FilePath $cmdExe.Source -ArgumentList $args2 -NoNewWindow -Wait -PassThru
    $ok = ($p.ExitCode -eq 0)
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

# herdr 官方安装：解析 manifest → 带进度下载 → SHA256 校验 → 解压 → 官方安装器收尾
function Install-HerdrWithProgress {
    try {
        Write-Host "  ⏳ 获取 herdr 版本信息 ..." -ForegroundColor Yellow
        Write-Log "==> 获取 herdr manifest"
        $manifest = Invoke-RestMethod -Uri "https://herdr.dev/preview.json" -TimeoutSec 60
        $baseVersion = [string]$manifest.base_version
        $buildId = [string]$manifest.build_id
        if (-not $baseVersion -or -not $buildId) { throw "无法解析 herdr 版本信息" }
        $versionIdentity = "$baseVersion-preview.$buildId"
        $asset = $manifest.assets.'windows-x86_64'
        if (-not $asset -or -not $asset.url) { throw "manifest 中未找到 Windows 资产" }
        $url = [string]$asset.url
        $sha256 = [string]$asset.sha256
        Write-Host "  └─ ✓ 版本: $versionIdentity" -ForegroundColor Green

        $safeVer = $versionIdentity -replace '[^0-9A-Za-z._-]', '-'
        $releaseName = "$safeVer-x86_64-pc-windows-msvc"
        $releasesDir = Join-Path $env:USERPROFILE ".herdr\packages\standalone\releases"
        $releaseDir  = Join-Path $releasesDir $releaseName
        $zip = Join-Path $env:TEMP ("herdr-" + [guid]::NewGuid().ToString("N") + ".zip")

        # 带进度下载
        if (-not (Download-FileWithProgress $url $zip "下载 herdr $versionIdentity")) { return $false }

        # SHA256 校验（用 .NET 实现，兼容性更稳）
        if ($sha256) {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $hash = [BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($zip))).Replace("-", "").ToLowerInvariant()
            } finally {
                $sha.Dispose()
            }
            if ($hash -ne $sha256.ToLowerInvariant()) {
                Write-Error "herdr 校验失败 (SHA256 不匹配)"
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
                return $false
            }
            Write-Success "SHA256 校验通过"
        }

        # 解压到官方安装器约定的目录结构
        New-Item -ItemType Directory -Force -Path $releasesDir | Out-Null
        $staging = Join-Path $releasesDir ".staging.$releaseName"
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $releaseDir) { Remove-Item $releaseDir -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -LiteralPath $zip -DestinationPath $staging
        Move-Item $staging $releaseDir
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Write-Success "herdr 已解压到 $releaseDir"

        # 官方安装器收尾：设置 junction + 更新 PATH（检测到已完整会跳过下载）
        return (Invoke-Streaming "herdr 官方安装器收尾" @("powershell.exe","-NoProfile","-ExecutionPolicy","Bypass","-c","irm https://herdr.dev/install.ps1 | iex"))
    } catch {
        Write-Error "herdr 自动安装失败: $($_.Exception.Message)"
        return $false
    }
}

# 解析默认 shell（与 .wezterm.lua 相同的回退策略：pwsh → powershell → cmd）
function Resolve-Shell {
    $candidates = @(
        (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source,
        'C:\Program Files\PowerShell\7\pwsh.exe',
        (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source,
        (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'),
        $env:COMSPEC
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return 'cmd.exe'
}

# 部署 herdr 配置：读取仓库模板(.herdr.config.toml) → 解析 shell → 替换占位符 → 写入
function Deploy-HerdrConfig($TemplatePath) {
    if (-not $TemplatePath -or -not (Test-Path $TemplatePath)) {
        Write-Warn "未找到 herdr 配置模板，跳过"
        return $false
    }
    try {
        $template = [System.IO.File]::ReadAllText($TemplatePath)
        $shell = Resolve-Shell
        $shellEscaped = $shell -replace '\\', '\\'
        $content = $template.Replace('__DEFAULT_SHELL__', $shellEscaped)
        if ($content -match '__DEFAULT_SHELL__') {
            Write-Warn "模板占位符未替换，跳过写入"
            return $false
        }
        $configDir = Join-Path $env:APPDATA "herdr"
        $configFile = Join-Path $configDir "config.toml"
        if (Test-Path $configFile) {
            $Backup = "$configFile.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item $configFile $Backup
            Write-Warn "已备份 herdr 配置 → $(Split-Path $Backup -Leaf)"
        }
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
        [System.IO.File]::WriteAllText($configFile, $content, (New-Object System.Text.UTF8Encoding($false)))
        Write-Success "herdr 配置已部署 → $configFile (default_shell: $shell)"
        return $true
    } catch {
        Write-Error "部署 herdr 配置失败: $($_.Exception.Message)"
        return $false
    }
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

function Install-Tool($Step, $Cmd, $WingetId, $ScoopId, [scriptblock]$Official, [string]$OfficialInfo = "") {
    try {
        $exists = Get-Command $Cmd -ErrorAction Stop
        Write-Success "$Cmd 已安装 ($($exists.Source))"
        return $true
    } catch {}

    $n = 1
    if ($winget -and $WingetId) {
        # 控制台直通执行：winget 会显示自己的下载进度条
        if (Invoke-Console "[$Step.$n] winget 安装 $Cmd ($WingetId)" @("winget","install","--id",$WingetId,"--silent","--accept-package-agreements","--accept-source-agreements")) {
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
    if ($Official) {
        Write-Host ""
        Write-Warn "无法自动安装 $Cmd"
        if ($OfficialInfo) { Write-Host "  ⚠  $OfficialInfo" -ForegroundColor DarkYellow }
        $answer = Read-Host "  是否自动安装 $Cmd？[Y/n]"
        if ([string]::IsNullOrEmpty($answer)) { $answer = "y" }
        if ($answer -match "^y") {
            if (& $Official) {
                Write-Success "$Cmd 安装完成"
                Refresh-Path
                return $true
            }
            Write-Warn "${Cmd}: 自动安装失败"
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
# herdr: 无 winget/scoop 包，失败后询问是否自动安装（带下载进度）
$herdrInfo = "Herdr 将下载约 22MB 预编译二进制（含 ConPTY 组件），下载时显示实时进度，视网络情况约需 10 秒 - 2 分钟"
$null = Install-Tool "2.5" "herdr" "herdr.herdr" "herdr" { Install-HerdrWithProgress } $herdrInfo
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

# 部署 herdr 配置（模板 .herdr.config.toml，与 .wezterm.lua 同方式读取）
Refresh-Path
if (Get-Command herdr -ErrorAction SilentlyContinue) {
    Write-Host "  ┌─ 部署 herdr 配置" -ForegroundColor Yellow
    $herdrSrc = Join-Path $ScriptDir ".herdr.config.toml"
    if (Test-Path $herdrSrc) {
        $null = Deploy-HerdrConfig $herdrSrc
    } else {
        Write-Warn "未找到 .herdr.config.toml，跳过 herdr 配置"
    }
    $herdrExe = (Get-Command herdr -ErrorAction SilentlyContinue).Source
    $null = Invoke-Streaming "herdr config check" @($herdrExe, "config", "check")
} else {
    Write-Info "未安装 herdr，跳过 herdr 配置"
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
