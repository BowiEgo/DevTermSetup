#!/bin/bash
# ============================================
#  DevTermSetup — 引导脚本 (macOS / Linux)
#  仅负责：确保 Node.js 存在 → 运行 Node 安装程序
#
#  远程执行:
#    curl -fsSL https://raw.githubusercontent.com/BowiEgo/DevTermSetup/main/setup.sh | bash
#  本地执行:
#    bash setup.sh [install|repair|doctor]
# ============================================

# ---- 样式 ----
BOLD='\033[1m'; DIM='\033[2m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
success() { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn()    { printf "  ${YELLOW}⚠${NC}  %s\n" "$*"; }
error()   { printf "  ${RED}✗${NC} %s\n" "$*"; }
info()    { printf "  ${DIM}%s${NC}\n" "$*"; }

# ---- 定位脚本源（本地 vs 远程）----
LOCAL_DIR=""
if [ -n "$BASH_SOURCE" ] && [ "${BASH_SOURCE[0]}" != "bash" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
REMOTE_BASE="${SETUP_REMOTE_BASE:-https://raw.githubusercontent.com/BowiEgo/DevTermSetup/main}"

# ---- 确保 Node.js (>= 18) ----
ensure_node() {
    if command -v node >/dev/null 2>&1; then
        local major
        major="$(node -v | cut -d. -f1 | tr -d 'v')"
        if [ "${major:-0}" -ge 18 ] 2>/dev/null; then
            success "Node.js $(node -v) 已就绪"
            return 0
        fi
        info "检测到 Node.js $(node -v)，但需要 18+，继续安装新版本"
    else
        echo ""
        info "未检测到 Node.js，正在安装..."
    fi

    # 包管理器优先
    if   command -v apt     &>/dev/null; then sudo apt update && sudo apt install -y nodejs npm
    elif command -v dnf     &>/dev/null; then sudo dnf install -y nodejs npm
    elif command -v pacman  &>/dev/null; then sudo pacman -S --noconfirm nodejs npm
    elif command -v zypper  &>/dev/null; then sudo zypper install -y nodejs npm
    elif command -v apk     &>/dev/null; then sudo apk add nodejs npm
    elif command -v brew    &>/dev/null; then brew install node
    fi 2>/dev/null

    if command -v node >/dev/null 2>&1 && [ "$(node -v | cut -d. -f1 | tr -d 'v')" -ge 18 ] 2>/dev/null; then
        success "Node.js $(node -v) 已就绪"
        return 0
    fi

    # 回退：nvm
    info "包管理器安装失败，尝试 nvm..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install --lts >/dev/null 2>&1
    if command -v node >/dev/null 2>&1 && [ "$(node -v | cut -d. -f1 | tr -d 'v')" -ge 18 ] 2>/dev/null; then
        success "Node.js $(node -v) 已就绪 (nvm)"
        return 0
    fi
    error "Node.js 安装失败，请手动安装: https://nodejs.org"
    return 1
}

echo ""
printf "  ${CYAN}${BOLD}DevTermSetup · 引导${NC}\n"

# ---- 代理检测（在安装 Node 之前）----
detect_proxy() {
    echo ""
    info "http_proxy  = ${http_proxy:-未设置}"
    info "https_proxy = ${https_proxy:-未设置}"
    info "all_proxy   = ${all_proxy:-未设置}"
    echo ""
    read -p "  代理设置是否正确？[Y/n/自定义地址]: " proxy_ok
    proxy_ok=${proxy_ok:-y}
    case "$proxy_ok" in
        [yY]*)
            if [ -n "$http_proxy" ]; then
                export HTTP_PROXY="$http_proxy"
                export HTTPS_PROXY="${https_proxy:-$http_proxy}"
                export all_proxy="${all_proxy:-$http_proxy}"
                success "保持当前代理设置"
            else
                warn "未设置代理，将直连（可能较慢）"
            fi
            ;;
        [nN]*)
            warn "跳过代理设置（直连）"
            ;;
        *)
            export http_proxy="$proxy_ok" https_proxy="$proxy_ok"
            export HTTP_PROXY="$proxy_ok" HTTPS_PROXY="$proxy_ok" all_proxy="$proxy_ok"
            success "已临时激活代理: $proxy_ok"
            ;;
    esac
    # 验证代理连通性
    if [ -n "$https_proxy" ]; then
        info "验证代理连通性..."
        if curl -fsSL --connect-timeout 5 -x "$https_proxy" https://raw.githubusercontent.com >/dev/null 2>&1; then
            success "代理可用"
        else
            warn "代理验证失败，继续尝试直连（可能较慢）"
        fi
    fi
    echo ""
}
detect_proxy

# ---- 确保 Node.js (>= 18) ----
ensure_node || exit 1

# ---- 获取并运行 Node 安装程序 ----
if [ -n "$LOCAL_DIR" ] && [ -f "$LOCAL_DIR/devterm-setup.js" ]; then
    JS="$LOCAL_DIR/devterm-setup.js"
else
    JS="$(mktemp /tmp/devterm-setup.XXXXXX.js)"
    info "下载 devterm-setup.js ..."
    if ! curl -fsSL -# -o "$JS" "$REMOTE_BASE/devterm-setup.js"; then
        error "下载失败，请检查网络"
        rm -f "$JS"
        exit 1
    fi
    trap 'rm -f "$JS"' EXIT
fi

# 运行 Node 安装程序（保留代理环境变量）
node "$JS" "$@"
