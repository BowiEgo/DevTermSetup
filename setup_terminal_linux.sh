#!/bin/bash

# ============================================
#  终端一键配置脚本 (Linux)
#  使用方式: source ./setup_terminal_linux.sh
# ============================================

# ---- ANSI 样式 ----
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

BOX_TOP="╭──────────────────────────────────────────────────╮"
BOX_BOT="╰──────────────────────────────────────────────────╯"

header() {
    echo ""
    echo -e "${CYAN}${BOX_TOP}${NC}"
    printf "│ ${CYAN}%-48s${NC} │\n" "  $1"
    echo -e "${CYAN}${BOX_BOT}${NC}"
    echo ""
}

success() { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
step()    { echo -e "${YELLOW}${BOLD}▸ [$1]${NC} $2"; echo ""; }
info()    { echo -e "  ${DIM}$1${NC}"; }
divider() { echo -e "${DIM}  ─────────────────────────────────────────${NC}"; }

pending() {
    local msg="$1"
    shift
    echo -ne "  ${YELLOW}⏳${NC} $msg ... "
    "$@" > /tmp/.setup_terminal_log 2>&1 &
    local pid=$!
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 $pid 2>/dev/null; do
        echo -ne "\r  ${YELLOW}${spin[$i]}${NC} $msg ... "
        i=$(( (i+1) % ${#spin[@]} ))
        sleep 0.1
    done
    wait $pid
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo -e "\r  ${GREEN}✓${NC} $msg 完成"
    else
        echo -e "\r  ${RED}✗${NC} $msg 失败"
        cat /tmp/.setup_terminal_log
    fi
    return $ret
}

# ---- 检测包管理器 ----
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$ID"
    OS_PRETTY="$PRETTY_NAME"
else
    OS_NAME="unknown"
    OS_PRETTY="Unknown Linux"
fi

if   command -v apt     &>/dev/null; then PKG="apt";     INSTALL="sudo apt install -y";     UPDATE="sudo apt update"
elif command -v dnf     &>/dev/null; then PKG="dnf";     INSTALL="sudo dnf install -y";     UPDATE="sudo dnf check-update || true"
elif command -v pacman  &>/dev/null; then PKG="pacman";  INSTALL="sudo pacman -S --noconfirm"; UPDATE="sudo pacman -Sy"
elif command -v zypper  &>/dev/null; then PKG="zypper";  INSTALL="sudo zypper install -y";  UPDATE="sudo zypper refresh"
elif command -v apk     &>/dev/null; then PKG="apk";     INSTALL="sudo apk add";            UPDATE="sudo apk update"
else PKG="unknown"; fi

# --------------------------------------------
header "🐧 终端一键配置 (Linux)"

info "系统: $OS_PRETTY"
info "包管理器: $PKG"
echo ""

if [ "$PKG" = "unknown" ]; then
    error "未识别的包管理器，将跳过自动安装"
    echo ""
fi

# --------------------------------------------
step "1/4" "网络代理设置"

info "http_proxy  = ${http_proxy:-未设置}"
info "https_proxy = ${https_proxy:-未设置}"
info "all_proxy   = ${all_proxy:-未设置}"
echo ""

read -p "  代理设置是否正确？[Y/n/自定义地址]: " proxy_ok
proxy_ok=${proxy_ok:-y}

case "$proxy_ok" in
    [yY]|[yY][eE][sS])
        if [ -n "$http_proxy" ]; then
            export HTTP_PROXY="$http_proxy"
            export HTTPS_PROXY="${https_proxy:-$http_proxy}"
            export all_proxy="${all_proxy:-$http_proxy}"
        fi
        success "保持当前代理设置"
        ;;
    [nN]|[nN][oO])
        warn "已跳过代理设置"
        ;;
    *)
        export http_proxy="$proxy_ok"
        export https_proxy="$proxy_ok"
        export HTTP_PROXY="$proxy_ok"
        export HTTPS_PROXY="$proxy_ok"
        export all_proxy="$proxy_ok"
        success "已临时激活代理: $proxy_ok"
        ;;
esac
echo ""

# --------------------------------------------
step "2/4" "检查终端工具"

# 确保 git
if ! command -v git &>/dev/null; then
    if [ "$PKG" != "unknown" ]; then
        pending "安装 git" $INSTALL git
    else
        error "请先手动安装 git"
        read -p "  按回车键退出..."
        return 1 2>/dev/null || exit 1
    fi
fi

install_pkg() {
    local cmd="$1" pkg="$2"
    if command -v "$cmd" &>/dev/null; then
        success "$pkg 已安装 ($(command -v "$cmd"))"
    elif [ "$PKG" != "unknown" ]; then
        pending "${PKG} install $pkg" $INSTALL "$pkg"
    else
        error "跳过 $pkg（未知包管理器）"
    fi
}

install_cargo_pkg() {
    local cmd="$1" pkg="$2"
    if command -v "$cmd" &>/dev/null; then
        success "$pkg 已安装"
        return
    fi
    if ! command -v cargo &>/dev/null; then
        pending "安装 Rust toolchain" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
        source "$HOME/.cargo/env"
    fi
    pending "cargo install $pkg" cargo install "$pkg"
}

if [ "$PKG" != "unknown" ]; then
    pending "更新包索引" $UPDATE
fi

install_pkg wezterm  wezterm
install_pkg nvim     neovim
install_pkg lazygit  lazygit

# herdr: 优先包管理器，回退 cargo
if ! command -v herdr &>/dev/null; then
    if [ "$PKG" != "unknown" ]; then
        install_pkg herdr herdr 2>/dev/null || install_cargo_pkg herdr herdr
    else
        install_cargo_pkg herdr herdr
    fi
else
    success "herdr 已安装 ($(command -v herdr))"
fi
echo ""

# --------------------------------------------
step "3/4" "部署 WezTerm 配置"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.wezterm.lua" ]; then
    if [ -f "$HOME/.wezterm.lua" ]; then
        BACKUP="$HOME/.wezterm.lua.backup.$(date +%Y%m%d%H%M%S)"
        cp "$HOME/.wezterm.lua" "$BACKUP"
        warn "已备份旧配置 → ${BACKUP##*/}"
    fi
    cp "$SCRIPT_DIR/.wezterm.lua" "$HOME/.wezterm.lua"
    success ".wezterm.lua → ~/.wezterm.lua"
else
    error "未找到 $SCRIPT_DIR/.wezterm.lua"
fi
echo ""

# --------------------------------------------
step "4/4" "部署 Neovim 配置"

NVIM_CONFIG="$HOME/.config/nvim"
REPO_URL="https://github.com/BowiEgo/my-nvim.git"

if [ -d "$NVIM_CONFIG" ]; then
    BACKUP="${NVIM_CONFIG}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$NVIM_CONFIG" "$BACKUP"
    warn "已备份旧 nvim 配置 → ${BACKUP##*/}"
fi

pending "git clone my-nvim" git clone "$REPO_URL" "$NVIM_CONFIG"
echo ""

# --------------------------------------------
divider
echo ""
echo -e "  ${GREEN}${BOLD}✓  配置完成！${NC}"
echo ""
echo -e "  ${DIM}代理设置仅对当前终端会话生效。${NC}"
echo -e "  ${DIM}持久化请追加到 shell 配置文件：${NC}"
echo ""
echo -e "    ${CYAN}export http_proxy=${http_proxy:-your_proxy}${NC}"
echo -e "    ${CYAN}export https_proxy=${https_proxy:-your_proxy}${NC}"
echo -e "    ${CYAN}export all_proxy=${all_proxy:-your_proxy}${NC}"
echo ""

read -p "  按回车键退出..."
