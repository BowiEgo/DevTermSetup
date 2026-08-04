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
REMOTE_BASE="${SETUP_REMOTE_BASE:-}"
REMOTE_BRANCHES="nodeVersion main"
# 远程获取文件：优先 SETUP_REMOTE_BASE，否则按分支顺序回退
fetch_remote() {
    local out="$1" file="$2" b
    if [ -n "$REMOTE_BASE" ]; then
        curl -fsSL -# -o "$out" "$REMOTE_BASE/$file" && return 0
        return 1
    fi
    for b in $REMOTE_BRANCHES; do
        if curl -fsSL -# -o "$out" "https://raw.githubusercontent.com/BowiEgo/DevTermSetup/$b/$file"; then
            return 0
        fi
    done
    return 1
}

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
    info "当前 http_proxy  = ${http_proxy:-未设置}"
    info "当前 https_proxy = ${https_proxy:-未设置}"
    echo ""
    local default="${https_proxy:-http://127.0.0.1:7897}"
    local proxy_ok=""
    if [ -t 0 ]; then
        # 交互终端：预填可编辑（backspace 可改），清空回车=直连
        read -e -i "$default" -p "  代理地址（回车=默认/当前，输入覆盖，清空回车=直连）: " proxy_ok
    else
        # 非交互（管道/脚本）：回车用默认，输入 direct 表示直连
        read -p "  代理地址（回车=默认 $default，输入覆盖，输入 direct=直连）: " proxy_ok
        if [ -z "$proxy_ok" ]; then proxy_ok="$default"; fi
    fi
    case "$proxy_ok" in
        direct|none|off)
            warn "已选择直连（不使用代理）"
            ;;
        *)
            if [ -n "$proxy_ok" ]; then
                export http_proxy="$proxy_ok" https_proxy="$proxy_ok"
                export HTTP_PROXY="$proxy_ok" HTTPS_PROXY="$proxy_ok" all_proxy="$proxy_ok"
                success "已使用代理: $proxy_ok"
                info "验证代理连通性..."
                if curl -fsSL --connect-timeout 5 -x "$proxy_ok" https://raw.githubusercontent.com >/dev/null 2>&1; then
                    success "代理可用"
                else
                    warn "代理验证失败，继续尝试直连（可能较慢）"
                fi
            else
                warn "已选择直连（不使用代理）"
            fi
            ;;
    esac
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
    if ! fetch_remote "$JS" "devterm-setup.js"; then
        error "下载失败，请检查网络"
        rm -f "$JS"
        exit 1
    fi
    trap 'rm -f "$JS"' EXIT
fi

# 运行 Node 安装程序（保留代理环境变量）
node "$JS" "$@"
