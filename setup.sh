#!/bin/bash
# ============================================
#  终端一键配置 — 远程一键执行
#
#  macOS / Linux:
#    curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/setup.sh | bash
#
#  也支持本地 source 执行以保留代理设置:
#    source ./setup.sh
# ============================================

# ---- ANSI 样式 ----
BOLD='\033[1m'; DIM='\033[2m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

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
    local msg="$1" pid ret
    shift
    echo -ne "  ${YELLOW}⏳${NC} $msg ... "
    "$@" > /tmp/.setup_log 2>&1 &
    pid=$!
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0
    while kill -0 $pid 2>/dev/null; do
        echo -ne "\r  ${YELLOW}${spin[$i]}${NC} $msg ... "
        i=$(( (i+1) % ${#spin[@]} ))
        sleep 0.1
    done
    wait $pid; ret=$?
    if [ $ret -eq 0 ]; then
        echo -e "\r  ${GREEN}✓${NC} $msg 完成"
    else
        echo -e "\r  ${RED}✗${NC} $msg 失败"
        cat /tmp/.setup_log
    fi
    return $ret
}

# ---- 检测平台 ----
case "$(uname -s)" in
    Darwin)  OS="macOS" ;;
    Linux)   OS="Linux" ;;
    *)
        error "不支持的操作系统: $(uname -s)"
        exit 1
        ;;
esac

# ---- 检测包管理器 ----
if [ "$OS" = "macOS" ]; then
    if ! command -v brew &>/dev/null; then
        error "未找到 Homebrew，请先安装: https://brew.sh"
        read -p "  按回车键退出..."
        exit 1
    fi
    PKG="brew"
    INSTALL="brew install"
    UPDATE="brew update"
else
    if   command -v apt     &>/dev/null; then PKG="apt";     INSTALL="sudo apt install -y";     UPDATE="sudo apt update"
    elif command -v dnf     &>/dev/null; then PKG="dnf";     INSTALL="sudo dnf install -y";     UPDATE="sudo dnf check-update || true"
    elif command -v pacman  &>/dev/null; then PKG="pacman";  INSTALL="sudo pacman -S --noconfirm"; UPDATE="sudo pacman -Sy"
    elif command -v zypper  &>/dev/null; then PKG="zypper";  INSTALL="sudo zypper install -y";  UPDATE="sudo zypper refresh"
    elif command -v apk     &>/dev/null; then PKG="apk";     INSTALL="sudo apk add";            UPDATE="sudo apk update"
    else PKG="unknown"; fi
fi

# ---- 解析远程仓库地址 ----
# 如果通过 curl pipe 执行，尝试推断原始仓库 URL 以下载 .wezterm.lua
REMOTE_BASE=""
if [ -n "$BASH_SOURCE" ] && [ "${BASH_SOURCE[0]}" != "bash" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    # 本地执行：脚本所在目录
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # 远程 pipe 执行：使用临时目录
    SCRIPT_DIR="$(mktemp -d)"
    REMOTE_CLEANUP=1
fi

download_config() {
    local filename="$1"
    # 本地优先
    if [ -f "$SCRIPT_DIR/$filename" ]; then
        cp "$SCRIPT_DIR/$filename" "$2"
        return 0
    fi
    # 如果用户提供了 REMOTE_BASE 环境变量
    if [ -n "$SETUP_REMOTE_BASE" ]; then
        pending "下载 $filename" curl -fsSLo "$2" "$SETUP_REMOTE_BASE/$filename"
        return $?
    fi
    return 1
}

# --------------------------------------------
header "🖥  终端一键配置"

info "平台: $OS"
info "包管理器: $PKG"
if [ "$PKG" = "unknown" ] && [ "$OS" = "Linux" ]; then
    error "未识别的包管理器，将跳过部分自动安装"
fi
echo ""

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
        export http_proxy="$proxy_ok" https_proxy="$proxy_ok"
        export HTTP_PROXY="$proxy_ok" HTTPS_PROXY="$proxy_ok"
        export all_proxy="$proxy_ok"
        success "已临时激活代理: $proxy_ok"
        ;;
esac
echo ""

# --------------------------------------------
step "2/4" "检查终端工具"

if ! command -v git &>/dev/null; then
    if [ "$PKG" != "unknown" ]; then
        pending "安装 git" $INSTALL git
    else
        error "请先手动安装 git"
        exit 1
    fi
fi

install_if_missing() {
    local cmd="$1" pkg="$2"
    if command -v "$cmd" &>/dev/null; then
        success "$pkg 已安装 ($(command -v "$cmd"))"
    elif [ "$PKG" != "unknown" ]; then
        pending "$PKG install $pkg" $INSTALL "$pkg"
    else
        error "跳过 $pkg（未知包管理器）"
    fi
}

install_cargo_pkg() {
    local cmd="$1" pkg="$2"
    if command -v "$cmd" &>/dev/null; then
        success "$pkg 已安装"; return
    fi
    if ! command -v cargo &>/dev/null; then
        pending "安装 Rust toolchain" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
        source "$HOME/.cargo/env"
    fi
    pending "cargo install $pkg" cargo install "$pkg"
}

[ "$PKG" != "unknown" ] && pending "更新包索引" $UPDATE

install_if_missing wezterm  wezterm
install_if_missing nvim     neovim
install_if_missing lazygit  lazygit

# herdr: 优先包管理器，回退 cargo
if ! command -v herdr &>/dev/null; then
    if [ "$PKG" != "unknown" ]; then
        install_if_missing herdr herdr 2>/dev/null || install_cargo_pkg herdr herdr
    else
        install_cargo_pkg herdr herdr
    fi
else
    success "herdr 已安装 ($(command -v herdr))"
fi
echo ""

# --------------------------------------------
step "3/4" "部署 WezTerm 配置"

WZ_DST="$HOME/.wezterm.lua"

# 尝试从本地/远程获取 .wezterm.lua
WZ_COPIED=0
if [ -f "$SCRIPT_DIR/.wezterm.lua" ]; then
    [ -f "$WZ_DST" ] && cp "$WZ_DST" "${WZ_DST}.backup.$(date +%Y%m%d%H%M%S)" && warn "已备份旧配置"
    cp "$SCRIPT_DIR/.wezterm.lua" "$WZ_DST"
    success ".wezterm.lua → ~/.wezterm.lua"
    WZ_COPIED=1
elif download_config ".wezterm.lua" "$WZ_DST"; then
    [ -f "$WZ_DST" ] && cp "$WZ_DST" "${WZ_DST}.backup.$(date +%Y%m%d%H%M%S)" && warn "已备份旧配置"
    success ".wezterm.lua → ~/.wezterm.lua (远程)"
    WZ_COPIED=1
else
    warn "未找到 .wezterm.lua，跳过 WezTerm 配置"
    warn "提示: 设置 SETUP_REMOTE_BASE 环境变量指向你的仓库"
    warn "  export SETUP_REMOTE_BASE=https://raw.githubusercontent.com/<user>/<repo>/main"
fi
echo ""

# --------------------------------------------
step "4/4" "部署 Neovim 配置"

NVIM_CONFIG="$HOME/.config/nvim"
REPO_URL="https://github.com/BowiEgo/my-nvim.git"

if [ -d "$NVIM_CONFIG" ]; then
    BACKUP="${NVIM_CONFIG}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$NVIM_CONFIG" "$BACKUP"
    warn "已备份旧 nvim 配置"
fi

pending "git clone my-nvim" git clone "$REPO_URL" "$NVIM_CONFIG"
echo ""

# ---- 清理 ----
[ -n "$REMOTE_CLEANUP" ] && rm -rf "$SCRIPT_DIR"

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
