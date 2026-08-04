#!/usr/bin/env node
/**
 * DevTermSetup — 终端环境一键配置 (Node.js)
 *
 * 用法:
 *   node devterm-setup.js                # 欢迎界面 + 菜单（安装/修复/doctor）
 *   node devterm-setup.js install [--tools git,wezterm]   # 安装（可指定工具）
 *   node devterm-setup.js repair         # 修复 / 同步工具配置
 *   node devterm-setup.js doctor         # 工具健康检查
 *
 * 零第三方依赖，仅用 Node 内置模块（Node 18+，推荐 20+）。
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const https = require('https');
const net = require('net');
const crypto = require('crypto');
const { spawn, spawnSync } = require('child_process');
const readline = require('readline');

/* ================= 常量 ================= */
const REPO_BASE = process.env.SETUP_REMOTE_BASE || 'https://raw.githubusercontent.com/BowiEgo/DevTermSetup/main';
const IS_WINDOWS = process.platform === 'win32';
const IS_MACOS = process.platform === 'darwin';
const IS_LINUX = process.platform === 'linux';
const HOME = os.homedir();

const C = {
  B: '\x1b[1m', D: '\x1b[2m',
  R: '\x1b[0m',
  Red: '\x1b[0;31m', Green: '\x1b[0;32m', Yellow: '\x1b[1;33m', Cyan: '\x1b[0;36m',
};

const TOOLS = {
  git:     { name: 'Git',        check: 'git',     winget: 'Git.Git',               apt: 'git',     brew: 'git' },
  wezterm: { name: 'WezTerm',    check: 'wezterm', winget: 'wez.wezterm',           apt: 'wezterm', brew: 'wezterm' },
  nvim:    { name: 'Neovim',     check: 'nvim',    winget: 'Neovim.Neovim',         apt: 'neovim',  brew: 'neovim' },
  lazygit: { name: 'lazygit',    check: 'lazygit', winget: 'JesseDuffield.lazygit', apt: 'lazygit', brew: 'lazygit' },
  herdr:   { name: 'herdr',      check: 'herdr',   official: true },
};

/* ================= 基础工具 ================= */
const pad = (n) => String(n).padStart(2, '0');
const ts = () => {
  const d = new Date();
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
};
const LOG_FILE = path.join(os.tmpdir(), `devtermsetup-${ts()}.log`);
function log(m) { try { fs.appendFileSync(LOG_FILE, m + '\n'); } catch {} }
const out = (s = '') => process.stdout.write(s + '\n');
const success = (m) => out(`  ${C.Green}✓${C.R} ${m}`);
const warn = (m) => out(`  ${C.Yellow}⚠${C.R}  ${m}`);
const error = (m) => out(`  ${C.Red}✗${C.R} ${m}`);
const info = (m) => out(`  ${C.D}${m}${C.R}`);
const step = (n, m) => { out(`${C.Yellow}${C.B}▸ [${n}]${C.R} ${m}`); out(''); };
const divider = () => out(`${C.D}  ${'─'.repeat(41)}${C.R}`);
function header(title) {
  const w = 54;
  out('');
  out(`  ${C.Cyan}╭${'─'.repeat(w)}╮${C.R}`);
  out(`  ${C.Cyan}│${C.R}  ${title.padEnd(w - 3)}${C.Cyan}│${C.R}`);
  out(`  ${C.Cyan}╰${'─'.repeat(w)}╯${C.R}`);
  out('');
}
function welcome() {
  out('');
  out(`  ${C.Cyan}${C.B}  ╔═══════════════════════════════════════════════╗${C.R}`);
  out(`  ${C.Cyan}${C.B}  ║       DevTermSetup · 终端环境一键配置         ║${C.R}`);
  out(`  ${C.Cyan}${C.B}  ╚═══════════════════════════════════════════════╝${C.R}`);
  out('');
  out(`  ${C.D}  跨平台: Windows / macOS / Linux    Node ${process.version}${C.R}`);
  out(`  ${C.D}  日志: ${LOG_FILE}${C.R}`);
  out('');
}

/* ================= 平台与包管理器 ================= */
function commandPath(cmd) {
  try {
    const r = spawnSync(IS_WINDOWS ? 'where' : 'sh', IS_WINDOWS ? [cmd] : ['-c', `command -v ${cmd}`], { encoding: 'utf8' });
    if (r.status === 0 && r.stdout) return r.stdout.trim().split(/\r?\n/)[0];
  } catch {}
  return null;
}
const commandExists = (cmd) => !!commandPath(cmd);

// 工具定位：PATH 优先，失败则查已知安装路径（应对 PATH 过期的会话）
function toolPath(key) {
  const t = TOOLS[key];
  let p = commandPath(t.check);
  if (p) return p;
  if (key === 'herdr') {
    const cands = IS_WINDOWS
      ? [path.join(process.env.LOCALAPPDATA || '', 'Programs', 'Herdr', 'bin', 'herdr.exe')]
      : [path.join(HOME, '.local', 'bin', 'herdr')];
    for (const c of cands) if (c && fs.existsSync(c)) return c;
  }
  return null;
}

function detectPkgManager() {
  if (IS_WINDOWS) {
    if (commandExists('winget')) return { pkg: 'winget', install: ['winget', 'install', '--id', 'PLACEHOLDER', '-e', '--silent', '--accept-package-agreements', '--accept-source-agreements'] };
    if (commandExists('scoop')) return { pkg: 'scoop', install: ['scoop', 'install', 'PLACEHOLDER'] };
    return { pkg: null };
  }
  if (IS_MACOS) {
    if (commandExists('brew')) return { pkg: 'brew', install: ['brew', 'install', 'PLACEHOLDER'], update: ['brew', 'update'] };
    return { pkg: null };
  }
  const cands = [
    ['apt', ['sudo', 'apt', 'install', '-y', 'PLACEHOLDER'], ['sudo', 'apt', 'update']],
    ['dnf', ['sudo', 'dnf', 'install', '-y', 'PLACEHOLDER'], ['sudo', 'dnf', 'check-update']],
    ['pacman', ['sudo', 'pacman', '-S', '--noconfirm', 'PLACEHOLDER'], ['sudo', 'pacman', '-Sy']],
    ['zypper', ['sudo', 'zypper', 'install', '-y', 'PLACEHOLDER'], ['sudo', 'zypper', 'refresh']],
    ['apk', ['sudo', 'apk', 'add', 'PLACEHOLDER'], ['sudo', 'apk', 'update']],
  ];
  for (const [pkg, install, update] of cands) if (commandExists(pkg)) return { pkg, install, update };
  return { pkg: null };
}
const PM = detectPkgManager();
function pmInstall(pkg) { return PM.install.map((a) => (a === 'PLACEHOLDER' ? pkg : a)); }

/* ================= 进程执行 ================= */
function spawnP(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    let child;
    try { child = spawn(cmd, args, { stdio: opts.stdio || ['ignore', 'pipe', 'pipe'], ...opts.spawn }); }
    catch (e) { return resolve(-1); }
    child.on('error', () => resolve(-1));
    child.on('close', (code) => resolve(code === null ? -1 : code));
  });
}

// 控制台直通执行：子进程直接连终端（winget 原生进度条、sudo 提示等）
async function runConsole(label, cmd, args) {
  log(`==> ${label}`);
  out(`  ${C.Yellow}┌─${C.R} ${label}`);
  const t0 = Date.now();
  const code = await spawnP(cmd, args, { stdio: 'inherit' });
  const secs = ((Date.now() - t0) / 1000).toFixed(1);
  if (code === 0) { out(`  ${C.Green}└─ ✓${C.R} ${label} 完成 (${secs}s)`); log(`==> OK: ${label} (${secs}s)`); return true; }
  out(`  ${C.Red}└─ ✗${C.R} ${label} 失败 (退出码 ${code})`); log(`==> FAIL: ${label} (exit ${code})`);
  return false;
}

// 流式执行：\r 进度原地刷新不堆叠，普通行逐行输出
async function stream(label, cmd, args) {
  log(`==> ${label}`);
  out(`  ${C.Yellow}┌─${C.R} ${label}`);
  const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  let buf = '', isProg = false, progLen = 0;
  const onData = (chunk) => {
    buf += chunk.toString('utf8');
    while (buf.length) {
      const n = buf.indexOf('\n');
      const r = buf.indexOf('\r');
      if (n === -1 && r === -1) break;
      if (n !== -1 && (r === -1 || n < r)) {
        const line = buf.slice(0, n); buf = buf.slice(n + 1);
        if (isProg) {
          if (line) process.stdout.write(`\r  │ ${line.padEnd(progLen)}`);
          process.stdout.write('\n');
          isProg = false; progLen = 0;
        } else if (line) { out(`  │ ${line}`); log(`  │ ${line}`); }
      } else {
        const seg = buf.slice(0, r); buf = buf.slice(r + 1);
        if (seg) {
          const s = seg.trimEnd();
          if (s.length < progLen) process.stdout.write(`\r  │ ${s.padEnd(progLen)}`);
          else { process.stdout.write(`\r  │ ${s}`); progLen = s.length; }
          isProg = true;
        }
      }
    }
  };
  child.stdout.on('data', onData);
  child.stderr.on('data', onData);
  const code = await new Promise((res) => {
    child.on('error', () => res(-1));
    child.on('close', res);
  });
  if (buf) {
    if (isProg) { process.stdout.write(`\r  │ ${buf.trimEnd().padEnd(progLen)}`); process.stdout.write('\n'); }
    else if (buf.trim()) { out(`  │ ${buf.trimEnd()}`); log(`  │ ${buf.trimEnd()}`); }
  }
  if (code === 0) { out(`  ${C.Green}└─ ✓${C.R} ${label} 完成`); log(`==> OK: ${label}`); return true; }
  out(`  ${C.Red}└─ ✗${C.R} ${label} 失败 (退出码 ${code})`); log(`==> FAIL: ${label} (exit ${code})`);
  return false;
}

/* ================= 下载（带进度，支持代理与重定向） ================= */
function httpsRequest(url, method = 'GET', redirects = 0) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const isHttps = u.protocol === 'https:';
    const proxyEnv = isHttps ? (process.env.https_proxy || process.env.HTTPS_PROXY) : (process.env.http_proxy || process.env.HTTP_PROXY);
    const headers = { 'user-agent': 'DevTermSetup/1.0' };
    const done = (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        if (redirects > 5) return reject(new Error('重定向过多'));
        return resolve(httpsRequest(new URL(res.headers.location, u).toString(), method, redirects + 1));
      }
      resolve({ res, url: u.toString() });
    };
    const fail = (e) => reject(e);
    if (proxyEnv && isHttps) {
      // HTTPS 经 HTTP 代理：CONNECT 隧道 + 手动 TLS 握手
      const p = new URL(proxyEnv);
      const c = net.connect(Number(p.port) || 443, p.hostname, () => {
        c.write(`CONNECT ${u.hostname}:${u.port || 443} HTTP/1.1\r\nHost: ${u.hostname}:${u.port || 443}\r\n\r\n`);
      });
      let tunneled = false;
      c.on('data', (d) => {
        if (tunneled) return;
        tunneled = true;
        const s = d.toString('latin1');
        if (!s.includes(' 200')) { c.destroy(); return reject(new Error('代理 CONNECT 失败')); }
        const tlsSock = require('tls').connect({ socket: c, servername: u.hostname }, () => {
          const req = http.request({ createConnection: () => tlsSock, method, headers: { ...headers, host: u.hostname }, path: u.pathname + u.search }, done);
          req.on('error', fail);
          req.end();
        });
        tlsSock.on('error', fail);
      });
      c.on('error', fail);
    } else if (proxyEnv) {
      const p = new URL(proxyEnv);
      const req = http.request({ host: p.hostname, port: Number(p.port) || 80, method, path: u.href, headers: { ...headers, host: u.host } }, done);
      req.on('error', fail);
      req.end();
    } else {
      const mod = isHttps ? https : http;
      const req = mod.request({
        method, headers,
        hostname: u.hostname, port: Number(u.port) || (isHttps ? 443 : 80),
        path: u.pathname + u.search,
        ...(isHttps ? { servername: u.hostname } : {}),
      }, done);
      req.on('error', fail);
      req.end();
    }
  });
}

function fmtProgress(label, done, total, speed) {
  if (total > 0) {
    const pct = Math.min(100, (done / total) * 100);
    const barLen = 20;
    const fill = Math.floor((pct / 100) * barLen);
    const bar = '#'.repeat(fill) + '-'.repeat(barLen - fill);
    return `${label}: ${(done / 1048576).toFixed(1).padStart(7)} / ${(total / 1048576).toFixed(1)} MiB  (${pct.toFixed(1).padStart(5)}%)  [${bar}]  ${speed.toFixed(2)} MiB/s`;
  }
  return `${label}: ${(done / 1048576).toFixed(1)} MiB  ${speed.toFixed(2)} MiB/s`;
}

async function downloadWithProgress(url, dest, label = '下载') {
  log(`==> ${label}`);
  out(`  ${C.Yellow}┌─${C.R} ${label}`);
  try {
    const { res } = await httpsRequest(url);
    if (res.statusCode !== 200) { res.resume(); throw new Error(`HTTP ${res.statusCode}`); }
    const total = parseInt(res.headers['content-length'] || '0', 10) || 0;
    const ws = fs.createWriteStream(dest);
    let done = 0, lastTick = Date.now(), lastDone = 0, speed = 0, maxW = 0;
    res.on('data', (chunk) => {
      done += chunk.length;
      const now = Date.now();
      if (now - lastTick >= 100) {
        speed = (done - lastDone) / ((now - lastTick) / 1000) / 1048576;
        lastDone = done; lastTick = now;
        const line = fmtProgress(label, done, total, speed);
        if (line.length < maxW) process.stdout.write(`\r  │ ${line.padEnd(maxW)}`);
        else { process.stdout.write(`\r  │ ${line}`); maxW = line.length; }
      }
    });
    await new Promise((resolve, reject) => {
      res.pipe(ws);
      ws.on('finish', resolve);
      res.on('error', reject);
      ws.on('error', reject);
    });
    const secs = ((Date.now() - (Date.now() - (done / Math.max(0.001, speed)) * 1000)) / 1000).toFixed(1);
    const line = fmtProgress(label, done, total, done / Math.max(0.001, secs) / 1048576 || 0);
    if (line.length < maxW) process.stdout.write(`\r  │ ${line.padEnd(maxW)}`);
    else process.stdout.write(`\r  │ ${line}`);
    process.stdout.write('\n');
    log(`  │ ${line}`);
    if (total > 0 && done !== total) { out(`  ${C.Yellow}└─ ⚠${C.R} ${label} 下载不完整 (${done}/${total} 字节)`); log(`==> PARTIAL: ${label}`); return false; }
    out(`  ${C.Green}└─ ✓${C.R} ${label} 完成`); log(`==> OK: ${label}`);
    return true;
  } catch (e) {
    out(`  ${C.Red}└─ ✗${C.R} ${label} 失败: ${e.message}`); log(`==> FAIL: ${label} ${e.message}`);
    return false;
  }
}

async function getJson(url) {
  const { res } = await httpsRequest(url);
  if (res.statusCode !== 200) { res.resume(); throw new Error(`HTTP ${res.statusCode}`); }
  let data = '';
  for await (const chunk of res) data += chunk;
  return JSON.parse(data);
}

/* ================= Shell 解析（与 .wezterm.lua 相同回退链） ================= */
function resolveShell() {
  if (IS_WINDOWS) {
    const candidates = [
      commandPath('pwsh.exe'),
      'C:\\Program Files\\PowerShell\\7\\pwsh.exe',
      commandPath('powershell.exe'),
      path.join(process.env.WINDIR || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
      process.env.COMSPEC,
    ];
    for (const c of candidates) if (c && fs.existsSync(c)) return c;
    return 'cmd.exe';
  }
  const shell = process.env.SHELL;
  if (shell && fs.existsSync(shell)) return shell;
  for (const s of ['zsh', 'bash', 'fish', 'pwsh', 'sh']) {
    const p = commandPath(s);
    if (p) return p;
  }
  return '/bin/sh';
}

/* ================= 配置部署 ================= */
function herdrConfigPath() {
  return IS_WINDOWS
    ? path.join(process.env.APPDATA || path.join(HOME, 'AppData', 'Roaming'), 'herdr', 'config.toml')
    : path.join(HOME, '.config', 'herdr', 'config.toml');
}
function backupIfExists(file) {
  if (fs.existsSync(file)) {
    const b = `${file}.backup.${ts()}`;
    fs.copyFileSync(file, b);
    warn(`已备份 ${path.basename(file)} → ${path.basename(b)}`);
  }
}
function deployWeztermConfig(srcDir) {
  const src = path.join(srcDir, '.wezterm.lua');
  if (!fs.existsSync(src)) { warn('未找到 .wezterm.lua，跳过'); return; }
  const dst = path.join(HOME, '.wezterm.lua');
  backupIfExists(dst);
  fs.copyFileSync(src, dst);
  success(`.wezterm.lua → ${dst}`);
}
function deployHerdrConfig(srcDir) {
  const src = path.join(srcDir, '.herdr.config.toml');
  if (!fs.existsSync(src)) { warn('未找到 .herdr.config.toml，跳过'); return; }
  const dst = herdrConfigPath();
  let content = fs.readFileSync(src, 'utf8');
  const shell = resolveShell();
  const esc = IS_WINDOWS ? shell.replace(/\\/g, '\\\\') : shell;
  content = content.split('__DEFAULT_SHELL__').join(esc);
  if (content.includes('__DEFAULT_SHELL__')) { warn('模板占位符未替换，跳过写入'); return; }
  backupIfExists(dst);
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.writeFileSync(dst, content);
  success(`herdr 配置已部署 → ${dst} (default_shell: ${shell})`);
}

/* ================= herdr 安装 ================= */
function sha256File(p) {
  return crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
}
async function installHerdr() {
  if (commandExists('herdr')) { success('herdr 已安装'); return true; }
  if (IS_WINDOWS) return installHerdrWindows();
  const osName = IS_MACOS ? 'macos' : IS_LINUX ? 'linux' : null;
  if (!osName) { error(`不支持的平台: ${process.platform}`); return false; }
  const arch = os.arch() === 'x64' ? 'x86_64' : os.arch() === 'arm64' ? 'aarch64' : null;
  if (!arch) { error(`不支持的架构: ${os.arch()}`); return false; }
  const target = `${osName}-${arch}`;
  try {
    info(`目标: ${osName}/${arch}`);
    const manifest = await getJson('https://herdr.dev/latest.json');
    const url = manifest.assets?.[target];
    if (!url) { error(`manifest 中未找到 ${target} 资产`); return false; }
    const bin = path.join(HOME, '.local', 'bin', 'herdr');
    fs.mkdirSync(path.dirname(bin), { recursive: true });
    if (!(await downloadWithProgress(url, bin + '.tmp', `下载 herdr v${manifest.version || 'latest'}`))) return false;
    fs.renameSync(bin + '.tmp', bin);
    fs.chmodSync(bin, 0o755);
    success(`herdr 已安装到 ${bin}`);
    const dirInPath = (process.env.PATH || '').split(':').some((d) => path.resolve(d) === path.dirname(bin));
    if (!dirInPath) warn(`~/.local/bin 不在 PATH，请添加: export PATH="$HOME/.local/bin:$PATH"`);
    return true;
  } catch (e) { error(`herdr 安装失败: ${e.message}`); return false; }
}
async function installHerdrWindows() {
  try {
    const manifest = await getJson('https://herdr.dev/preview.json');
    const base = manifest.base_version, build = manifest.build_id;
    const asset = manifest.assets?.['windows-x86_64'];
    if (!asset?.url) { error('manifest 中未找到 Windows 资产'); return false; }
    const ver = `${base}-preview.${build}`;
    const zip = path.join(os.tmpdir(), `herdr-${crypto.randomUUID()}.zip`);
    if (!(await downloadWithProgress(asset.url, zip, `下载 herdr ${ver}`))) return false;
    const actual = sha256File(zip);
    if (asset.sha256 && actual !== String(asset.sha256).toLowerCase()) {
      error('herdr 校验失败 (SHA256 不匹配)');
      fs.rmSync(zip, { force: true });
      return false;
    }
    success('SHA256 校验通过');
    const releaseName = `${ver.replace(/[^0-9A-Za-z._-]/g, '-')}-x86_64-pc-windows-msvc`;
    const releasesDir = path.join(HOME, '.herdr', 'packages', 'standalone', 'releases');
    const releaseDir = path.join(releasesDir, releaseName);
    const staging = path.join(releasesDir, `.staging.${releaseName}`);
    fs.mkdirSync(releasesDir, { recursive: true });
    fs.rmSync(staging, { recursive: true, force: true });
    fs.rmSync(releaseDir, { recursive: true, force: true });
    if (!(await runConsole('解压 herdr', 'powershell.exe', ['-NoProfile', '-Command', `Expand-Archive -LiteralPath '${zip}' -DestinationPath '${staging}'`]))) return false;
    fs.rmSync(zip, { force: true });
    fs.renameSync(staging, releaseDir);
    success(`herdr 已解压到 ${releaseDir}`);
    // 官方安装器收尾：junction + PATH（检测到已完整会跳过下载）
    return await stream('herdr 官方安装器收尾', 'powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-c', 'irm https://herdr.dev/install.ps1 | iex']);
  } catch (e) { error(`herdr 安装失败: ${e.message}`); return false; }
}

/* ================= 工具安装 ================= */
async function installTool(key, stepNo) {
  const t = TOOLS[key];
  const p = toolPath(key);
  if (p) { success(`${t.name} 已安装 (${p})`); return true; }
  let n = 1;
  if (PM.pkg && PM.install && t[PM.pkg]) {
    const args = pmInstall(t[PM.pkg]);
    if (await runConsole(`[${stepNo}.${n}] ${PM.pkg} 安装 ${t.name} (${t[PM.pkg]})`, args[0], args.slice(1))) {
      if (toolPath(key)) { success(`${t.name} 安装完成`); return true; }
    }
    warn(`${t.name}: ${PM.pkg} 失败，尝试其他方式`);
    n++;
  }
  if (t.official) {
    out('');
    warn(`无法自动安装 ${t.name}`);
    warn(`Herdr 将下载约 22MB 预编译二进制，下载时显示实时进度，视网络情况约需 10 秒 - 2 分钟`);
    const ans = await ask('  是否自动安装 herdr？[Y/n]', 'y');
    if (/^y/i.test(ans)) {
      if (await installHerdr()) { success('herdr 安装完成'); return true; }
      warn('herdr: 自动安装失败');
    } else { warn('已跳过 herdr 自动安装'); }
    n++;
  }
  if (toolPath(key)) { success(`${t.name} 已可用`); return true; }
  error(`无法安装 ${t.name}，请手动安装`);
  return false;
}

/* ================= 交互 UI ================= */
function ask(question, def = '') {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((res) => {
    rl.question(`${question} `, (a) => { rl.close(); res(a.trim() || def); });
  });
}
async function pressEnter() { await ask('  按回车键退出...', ''); }

function keySelect(title, items) {
  return new Promise((resolve) => {
    let cursor = 0, rendered = false;
    const total = items.length + 2;
    const render = () => {
      if (rendered) process.stdout.write(`\x1b[${total}A`);
      process.stdout.write(`\x1b[2K  ${C.Yellow}${C.B}${title}${C.R}\n`);
      items.forEach((it, i) => {
        process.stdout.write(`\x1b[2K  ${i === cursor ? `${C.Cyan}>${C.R}` : ' '} ${it.name}\n`);
      });
      process.stdout.write(`\x1b[2K  ${C.D}↑/↓ 移动，回车确认${C.R}\n`);
      rendered = true;
    };
    const cleanup = () => { process.stdin.setRawMode(false); process.stdin.removeListener('keypress', onKey); process.stdin.pause(); };
    const onKey = (str, key) => {
      if (key.name === 'up') { cursor = (cursor - 1 + items.length) % items.length; render(); }
      else if (key.name === 'down') { cursor = (cursor + 1) % items.length; render(); }
      else if (key.name === 'return') { cleanup(); resolve(items[cursor].value); }
      else if (key.ctrl && key.name === 'c') { cleanup(); process.exit(130); }
    };
    try {
      readline.emitKeypressEvents(process.stdin);
      process.stdin.setRawMode(true);
      process.stdin.on('keypress', onKey);
    } catch {
      // 非 TTY：直接返回第一项
      resolve(items[0].value);
      return;
    }
    render();
  });
}

function multiSelect(title, items, defaults) {
  return new Promise((resolve) => {
    let cursor = 0, rendered = false;
    const selected = new Set(defaults || items.map((_, i) => i));
    const total = items.length + 3;
    const render = () => {
      if (rendered) process.stdout.write(`\x1b[${total}A`);
      process.stdout.write(`\x1b[2K  ${C.Yellow}${C.B}${title}${C.R}\n`);
      items.forEach((it, i) => {
        const mark = selected.has(i) ? `${C.Green}[✓]${C.R}` : '[ ]';
        process.stdout.write(`\x1b[2K  ${i === cursor ? `${C.Cyan}>${C.R}` : ' '} ${mark} ${it.name}\n`);
      });
      process.stdout.write(`\x1b[2K  ${C.D}↑/↓ 移动，空格 选择/取消，回车 确认${C.R}\n`);
      rendered = true;
    };
    const cleanup = () => { process.stdin.setRawMode(false); process.stdin.removeListener('keypress', onKey); process.stdin.pause(); };
    const onKey = (str, key) => {
      if (key.name === 'up') { cursor = (cursor - 1 + items.length) % items.length; render(); }
      else if (key.name === 'down') { cursor = (cursor + 1) % items.length; render(); }
      else if (key.name === 'space') { selected.has(cursor) ? selected.delete(cursor) : selected.add(cursor); render(); }
      else if (key.name === 'return') { cleanup(); resolve([...selected].map((i) => items[i].value)); }
      else if (key.ctrl && key.name === 'c') { cleanup(); process.exit(130); }
    };
    try {
      readline.emitKeypressEvents(process.stdin);
      process.stdin.setRawMode(true);
      process.stdin.on('keypress', onKey);
    } catch {
      resolve([...selected].map((i) => items[i].value));
      return;
    }
    render();
  });
}

/* ================= 配置源定位 ================= */
async function getConfigDir() {
  // 本地运行：脚本所在目录（含 .wezterm.lua / .herdr.config.toml）
  const local = path.resolve(__dirname);
  if (fs.existsSync(path.join(local, '.wezterm.lua'))) return local;
  // 远程运行：从仓库下载
  out('');
  step('配置', '下载配置文件');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'devtermsetup-cfg-'));
  for (const f of ['.wezterm.lua', '.herdr.config.toml']) {
    if (!(await downloadWithProgress(`${REPO_BASE}/${f}`, path.join(dir, f), `下载 ${f}`))) return null;
  }
  return dir;
}

/* ================= 模式：安装 ================= */
async function runInstall(selectedTools) {
  welcome();
  step('1/4', '网络代理设置');
  info(`http_proxy  = ${process.env.http_proxy || '未设置'}`);
  info(`https_proxy = ${process.env.https_proxy || '未设置'}`);
  out('');
  const ans = await ask('  代理设置是否正确？[Y/n/自定义地址]', 'y');
  if (/^y/i.test(ans)) {
    if (process.env.http_proxy) {
      process.env.HTTP_PROXY = process.env.http_proxy;
      process.env.HTTPS_PROXY = process.env.https_proxy || process.env.http_proxy;
      process.env.all_proxy = process.env.all_proxy || process.env.http_proxy;
    }
    success('保持当前代理设置');
  } else if (/^n/i.test(ans)) {
    warn('已跳过代理设置');
  } else {
    process.env.http_proxy = process.env.https_proxy = process.env.HTTP_PROXY = process.env.HTTPS_PROXY = process.env.all_proxy = ans;
    success(`已临时激活代理: ${ans}`);
  }
  out('');

  step('2/4', '选择要安装的工具');
  let keys = selectedTools;
  if (!keys) {
    keys = await multiSelect('可用工具（空格选择/取消，回车确认，默认全选）',
      Object.entries(TOOLS).map(([k, t]) => ({ name: `${t.name} (${t.check})`, value: k })));
  }
  if (!keys.length) { warn('未选择任何工具，跳过安装'); }
  out('');

  step('3/4', '安装所选工具');
  info(`包管理器: ${PM.pkg || '未检测到'}`);
  if (!PM.pkg && IS_LINUX) warn('未识别到包管理器，git/wezterm/nvim/lazygit 将跳过（herdr 仍可用官方安装器）');
  out('');
  let i = 1;
  for (const k of keys) {
    await installTool(k, `3.${i}`);
    i++;
  }
  out('');

  step('4/4', '部署终端配置');
  const dir = await getConfigDir();
  if (dir) {
    deployWeztermConfig(dir);
    if (toolPath('herdr')) {
      deployHerdrConfig(dir);
      const h = commandPath('herdr') || toolPath('herdr');
      await stream('herdr config check', h, ['config', 'check']);
    } else { info('未安装 herdr，跳过 herdr 配置'); }
  } else { warn('无法获取配置文件，跳过配置部署'); }
  out('');

  divider();
  out('');
  success(`${C.B}配置完成！${C.R}`);
  out('');
  info(`详细安装日志: ${LOG_FILE}`);
  out('');
  await pressEnter();
}

/* ================= 模式：修复 / 同步配置 ================= */
async function runRepair() {
  header('🔧 修复 / 同步工具配置');
  const dir = await getConfigDir();
  if (!dir) { error('无法获取配置文件'); await pressEnter(); return; }
  step('1/2', '部署 WezTerm 配置');
  deployWeztermConfig(dir);
  out('');
  step('2/2', '部署 herdr 配置');
  if (toolPath('herdr')) {
    deployHerdrConfig(dir);
    const h = commandPath('herdr') || toolPath('herdr');
    await stream('herdr config check', h, ['config', 'check']);
  } else { info('未安装 herdr，跳过 herdr 配置'); }
  out('');
  divider();
  out('');
  success('修复完成');
  info(`详细日志: ${LOG_FILE}`);
  out('');
  await pressEnter();
}

/* ================= 模式：Doctor ================= */
async function runDoctor() {
  header('🔍 Doctor 健康检查');
  out(`${C.Yellow}${C.B}  工具检查${C.R}`);
  let okCount = 0, total = Object.keys(TOOLS).length;
  for (const [key, t] of Object.entries(TOOLS)) {
    const p = toolPath(key);
    if (p) { success(`${t.name}: ${p}`); okCount++; }
    else { error(`${t.name}: 未安装`); }
  }
  out('');
  out(`${C.Yellow}${C.B}  Shell 解析${C.R}`);
  success(`默认 shell: ${resolveShell()}`);
  out('');
  out(`${C.Yellow}${C.B}  配置检查${C.R}`);
  const wz = path.join(HOME, '.wezterm.lua');
  if (fs.existsSync(wz)) success(`.wezterm.lua: ${wz}`); else warn('.wezterm.lua: 未部署 (可运行 repair 同步)');
  const hc = herdrConfigPath();
  if (fs.existsSync(hc)) success(`herdr config: ${hc}`); else warn('herdr config: 未部署 (可运行 repair 同步)');
  out('');
  divider();
  out('');
  success(`${C.B}检查完成: ${okCount}/${total} 个工具已安装${C.R}`);
  info(`日志: ${LOG_FILE}`);
  out('');
  await pressEnter();
}

/* ================= 菜单入口 ================= */
async function runMenu() {
  welcome();
  const choice = await keySelect('请选择操作', [
    { name: `${C.Cyan}①${C.R} 安装工具`, value: 'install' },
    { name: `${C.Cyan}②${C.R} 修复 / 同步配置`, value: 'repair' },
    { name: `${C.Cyan}③${C.R} Doctor 检查`, value: 'doctor' },
    { name: `${C.Cyan}④${C.R} 退出`, value: 'exit' },
  ]);
  if (choice === 'install') await runInstall(null);
  else if (choice === 'repair') await runRepair();
  else if (choice === 'doctor') await runDoctor();
  else process.exit(0);
}

/* ================= 主流程 ================= */
function parseToolsArg() {
  const idx = process.argv.indexOf('--tools');
  if (idx !== -1 && process.argv[idx + 1]) {
    return process.argv[idx + 1].split(',').map((s) => s.trim()).filter((s) => TOOLS[s]);
  }
  return null;
}
async function main() {
  const mode = process.argv[2] || 'menu';
  if (mode === 'install') await runInstall(parseToolsArg());
  else if (mode === 'repair') await runRepair();
  else if (mode === 'doctor') await runDoctor();
  else await runMenu();
}

// 直接运行时进入主流程；被 require 时导出内部函数便于测试
if (require.main === module) {
  main().catch((e) => { error(`程序异常: ${e.stack || e.message}`); process.exit(1); });
} else {
  module.exports = { downloadWithProgress, stream, runConsole, resolveShell, toolPath, commandPath, installHerdr, getConfigDir, LOG_FILE };
}
