# DevTermSetup

一键配置开发终端环境：引导脚本自动安装 Node.js，随后由跨平台 Node 程序完成全部工具安装与配置（WezTerm、Neovim、lazygit、herdr、Git）。

## 快速开始

### Windows

```powershell
irm https://raw.githubusercontent.com/BowiEgo/DevTermSetup/main/setup.ps1 | iex
```

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/BowiEgo/DevTermSetup/main/setup.sh | bash
```

引导脚本只做一件事：**确保 Node.js (≥18) 存在**，然后运行 `devterm-setup.js`。Node 缺失时自动安装（Windows 用 winget，macOS 用 brew，Linux 用系统包管理器，回退 nvm）。

## Node 程序功能

| 模式 | 说明 |
|---|---|
| **默认（菜单）** | 欢迎界面 + 交互菜单（安装 / 修复 / Doctor / 退出） |
| **安装** | 代理设置 → **多选框自定义选择工具** → 安装（实时进度、下载进度条、herdr 官方安装器）→ 部署配置 |
| **修复** | 同步工具配置（`.wezterm.lua`、`.herdr.config.toml`，带备份） |
| **Doctor** | 工具健康检查：安装状态、shell 解析、配置文件 |

### 直接运行

```bash
node devterm-setup.js                          # 欢迎界面 + 菜单
node devterm-setup.js install                  # 安装（交互选择工具）
node devterm-setup.js install --tools git,wezterm,herdr   # 非交互指定工具
node devterm-setup.js repair                   # 修复 / 同步配置
node devterm-setup.js doctor                   # 健康检查
```

零第三方依赖，仅用 Node 内置模块（Node 18+，推荐 20+）。日志保存在 `devtermsetup-<时间戳>.log`（系统临时目录）。

## 配置文件

| 文件 | 说明 |
|---|---|
| `.wezterm.lua` | WezTerm 配置，含跨平台默认 shell 回退链（Windows: pwsh→powershell→cmd；macOS/Linux: $SHELL→zsh→bash→fish→pwsh→sh） |
| `.herdr.config.toml` | herdr 配置模板，`default_shell` 在部署时按相同策略自动解析 |

## 安装的工具

Git、WezTerm、Neovim、lazygit、herdr（官方安装器，带下载进度与 SHA256 校验）。安装命令按平台适配：Windows 用 winget，macOS 用 brew，Linux 用 apt/dnf/pacman/zypper/apk。
