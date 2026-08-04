#!/bin/bash

# ============================================
#  终端一键配置脚本 (macOS)
#  使用方式: source ./setup_terminal_macos.sh
#  或: bash ./setup_terminal_macos.sh
# ============================================

# ---- ANSI 样式 ----
BOLD='\033[1m'; DIM='\033[2m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

# 详细日志文件
SCRIPT_LOG="${TMPDIR:-/tmp}/devtermsetup-$(date +%Y%m%d%H%M%S).log"
log() { printf '%s\n' "$*" >> "$SCRIPT_LOG" 2>/dev/null; }

success() { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn()    { printf "  ${YELLOW}⚠${NC}  %s\n" "$*"; }
error()   { printf "  ${RED}✗${NC} %s\n" "$*"; }
step()    { printf "${YELLOW}${BOLD}▸ [%s]${NC} %s\n\n" "$1" "$2"; }
info()    { printf "  ${DIM}%s${NC}\n" "$*"; }
divider() { printf "${DIM}  ─────────────────────────────────────────${NC}\n"; }

header() {
    echo ""
    echo -e "${CYAN}╭────────────────────────────────────────────────────╮${NC}"
    printf "│ ${CYAN}%-52s${NC} │\n" "  $1"
    echo -e "${CYAN}╰────────────────────────────────────────────────────╯${NC}"
    echo ""
}

# 实时流式执行：\r 进度原地刷新不堆叠，普通行逐行输出；返回命令退出码
stream() {
    local label="$1"; shift
    local ret
    log "==> $label"
    printf "  ${YELLOW}┌─${NC} %s\n" "$label"
    "$@" 2>&1 | (
        local c buf="" is_prog=0 prog_len=0
        while IFS= read -r -n1 c; do
            case "$c" in
                $'\n')
                    if [ "$is_prog" -eq 1 ]; then
                        [ -n "$buf" ] && printf '\r  │ %-*s' "$prog_len" "$buf"
                        printf '\n'
                        is_prog=0
                    elif [ -n "$buf" ]; then
                        printf '  │ %s\n' "$buf"
                        log "  │ $buf"
                    fi
                    buf=""; prog_len=0
                    ;;
                $'\r')
                    if [ -n "$buf" ]; then
                        if [ "${#buf}" -lt "$prog_len" ]; then
                            printf '\r  │ %-*s' "$prog_len" "$buf"
                        else
                            printf '\r  │ %s' "$buf"
                            prog_len=${#buf}
                        fi
                        is_prog=1
                    fi
                    buf=""
                    ;;
                *)
                    buf+="$c"
                    ;;
            esac
        done
        if [ -n "$buf" ]; then
            if [ "$is_prog" -eq 1 ]; then
                printf '\r  │ %-*s' "$prog_len" "$buf"
                printf '\n'
            else
                printf '  │ %s\n' "$buf"
                log "  │ $buf"
            fi
        elif [ "$is_prog" -eq 1 ]; then
            printf '\n'
        fi
    )
    ret=${PIPESTATUS[0]}
    if [ "$ret" -eq 0 ]; then
        printf "  ${GREEN}└─ ✓${NC} %s 完成\n" "$label"
        log "==> OK: $label"
    else
        printf "  ${RED}└─ ✗${NC} %s 失败 (退出码 $ret)\n" "$label"
        log "==> FAIL: $label (exit $ret)"
    fi
    return "$ret"
}

# 下载（curl 原生进度条，经 stream 原地刷新）
download() {
    local url="$1" dest="$2" label="$3"
    stream "$label" curl -fSL --retry 3 -# -o "$dest" "$url"
}

# 工具安装：包管理器 → 官方安装器(询问) → 兜底重检
install_tool() {
    local step="$1" cmd="$2" pkg="$3" official_fn="$4" official_info="$5"
    local n=1 answer
    if command -v "$cmd" >/dev/null 2>&1; then
        success "$cmd 已安装 ($(command -v "$cmd"))"
        return 0
    fi
    if [ "$PKG" != "unknown" ]; then
        if stream "[$step.$n] ${PKG} 安装 $cmd ($pkg)" $INSTALL "$pkg"; then
            hash -r 2>/dev/null
            if command -v "$cmd" >/dev/null 2>&1; then
                success "$cmd 安装完成"
                return 0
            fi
        fi
        warn "$cmd: ${PKG} 失败，尝试其他方式"
        n=$((n+1))
    fi
    if [ -n "$official_fn" ]; then
        echo ""
        warn "无法自动安装 $cmd"
        [ -n "$official_info" ] && printf "  ${YELLOW}⚠${NC}  %s\n" "$official_info"
        read -p "  是否自动安装 $cmd？[Y/n]: " answer
        answer=${answer:-y}
        case "$answer" in
            [yY]*)
                if "$official_fn"; then
                    hash -r 2>/dev/null
                    success "$cmd 安装完成"
                    return 0
                fi
                warn "$cmd: 自动安装失败"
                ;;
            *) warn "已跳过 $cmd 自动安装" ;;
        esac
    fi
    hash -r 2>/dev/null
    if command -v "$cmd" >/dev/null 2>&1; then
        success "$cmd 已可用"
        return 0
    fi
    error "无法安装 $cmd，请手动安装"
    return 1
}

# herdr 官方安装：解析 manifest → 带进度下载 → 安装到 ~/.local/bin
install_herdr() {
    local os arch target manifest url version bin
    os="$(uname -s)"
    case "$os" in
        Darwin) os="macos" ;;
        *) error "不支持的平台: $os"; return 1 ;;
    esac
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) error "不支持的架构: $arch"; return 1 ;;
    esac
    target="${os}-${arch}"
    info "目标: ${os}/${arch}"
    manifest="$(curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 https://herdr.dev/latest.json 2>/dev/null)" || {
        error "获取 herdr 版本信息失败"
        return 1
    }
    url="$(printf '%s\n' "$manifest" | grep -oE "\"${target}\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" | head -1 | sed -E 's/.*"(https?:\/\/[^"]+)".*/\1/')"
    version="$(printf '%s\n' "$manifest" | grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | grep -oE '"[^"]+"$' | tr -d '"')"
    if [ -z "$url" ]; then
        error "manifest 中未找到 ${target} 资产"
        return 1
    fi
    bin="$HOME/.local/bin/herdr"
    mkdir -p "$HOME/.local/bin"
    if stream "下载 herdr v${version:-latest}" curl -fSL --retry 3 -# -o "$bin.tmp" "$url"; then
        mv "$bin.tmp" "$bin"
        chmod +x "$bin"
        success "herdr 已安装到 $bin"
        case ":${PATH}:" in
            *":$HOME/.local/bin:"*) ;;
            *) warn "~/.local/bin 不在 PATH，请添加: export PATH=\"$HOME/.local/bin:\$PATH\"" ;;
        esac
        return 0
    fi
    rm -f "$bin.tmp"
    return 1
}

# 解析默认 shell（与 .wezterm.lua 相同的回退策略：$SHELL → zsh → bash → fish → pwsh → sh）
resolve_shell() {
    local shell="$SHELL"
    [ -n "$shell" ] && [ -x "$shell" ] && { echo "$shell"; return 0; }
    local c p
    for c in zsh bash fish pwsh sh; do
        p="$(command -v "$c" 2>/dev/null)"
        [ -n "$p" ] && { echo "$p"; return 0; }
    done
    echo "/bin/sh"
}

# 写入 herdr 配置：设置 [terminal] default_shell，保留其他配置并备份
configure_herdr_shell() {
    local config_file="$HOME/.config/herdr/config.toml"
    local shell_path
    shell_path="$(resolve_shell)"
    mkdir -p "$(dirname "$config_file")"
    if [ -f "$config_file" ]; then
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d%H%M%S)"
        warn "已备份 herdr 配置 → ${config_file}.backup.*"
    else
        : > "$config_file"
    fi
    awk -v shell="$shell_path" '
        BEGIN { in_term = 0; done = 0 }
        /^[[:space:]]*\[terminal\][[:space:]]*$/ { in_term = 1; print; next }
        /^[[:space:]]*\[/ {
            if (in_term && !done) { print "default_shell = \"" shell "\""; done = 1 }
            in_term = 0
        }
        in_term && /^[[:space:]]*default_shell[[:space:]]*=/ {
            print "default_shell = \"" shell "\""
            done = 1
            next
        }
        { print }
        END {
            if (!done) {
                if (!in_term) { print ""; print "[terminal]" }
                print "default_shell = \"" shell "\""
            }
        }
    ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
    success "herdr default_shell → $shell_path"
}

# ---- 检测包管理器 ----
if ! command -v brew &>/dev/null; then
    PKG="unknown"
else
    PKG="brew"
    INSTALL="brew install"
    UPDATE="brew update"
fi

# --------------------------------------------
header "🖥  终端一键配置 (macOS)"

info "包管理器: $PKG"
info "日志: $SCRIPT_LOG"
echo ""

if [ "$PKG" = "unknown" ]; then
    error "未找到 Homebrew，请先安装: https://brew.sh"
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

if [ "$PKG" = "unknown" ]; then
    error "未找到 Homebrew，退出"
    read -p "  按回车键退出..."
    return 1 2>/dev/null || exit 1
fi

# Git 先装
install_tool "2.1" git git

# 更新 brew 索引
stream "更新包索引" $UPDATE

install_tool "2.2" wezterm wezterm
install_tool "2.3" nvim neovim
install_tool "2.4" lazygit lazygit
HDRDR_INFO="Herdr 将下载约 22MB 预编译二进制，下载时显示实时进度，视网络情况约需 10 秒 - 2 分钟"
install_tool "2.5" herdr herdr install_herdr "$HDRDR_INFO"
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

# 部署 herdr 配置（与 WezTerm 相同的 shell 选择策略）
if command -v herdr >/dev/null 2>&1; then
    printf "  ${YELLOW}┌─${NC} 部署 herdr 配置\n"
    configure_herdr_shell
    stream "herdr config check" herdr config check
else
    info "未安装 herdr，跳过 herdr 配置"
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

if stream "git clone my-nvim" git clone --progress "$REPO_URL" "$NVIM_CONFIG" && [ -d "$NVIM_CONFIG/.git" ]; then
    success "nvim 配置克隆完成 → $NVIM_CONFIG"
else
    error "克隆失败，请检查网络和仓库地址"
fi
echo ""

# --------------------------------------------
divider
echo ""
echo -e "  ${GREEN}${BOLD}✓  配置完成！${NC}"
echo ""
echo -e "  ${DIM}代理设置仅对当前终端会话生效。${NC}"
echo -e "  ${DIM}持久化请追加到 ~/.zshrc 或 ~/.bashrc：${NC}"
echo ""
echo -e "    ${CYAN}export http_proxy=${http_proxy:-your_proxy}${NC}"
echo -e "    ${CYAN}export https_proxy=${https_proxy:-your_proxy}${NC}"
echo -e "    ${CYAN}export all_proxy=${all_proxy:-your_proxy}${NC}"
echo ""
echo -e "  ${CYAN}详细安装日志: $SCRIPT_LOG${NC}"
echo ""

read -p "  按回车键退出..."
