#!/bin/bash
set -o pipefail

# --- 颜色与基础设置 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ASSUME_YES=false
DRY_RUN=false
TERMINAL_FONT_FAMILY="MesloLGS Nerd Font Mono"
TERMINAL_FONT_SIZE=14

usage() {
    cat <<'EOF'
Usage: ./setup.sh [--yes] [--dry-run] [--help]

Options:
  --yes      Automatically answer yes to confirmation prompts.
  --dry-run  Print the actions that would change the system without doing them.
  --help     Show this help message.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --yes|-y)
            ASSUME_YES=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: ${arg}${NC}"
            usage
            exit 1
            ;;
    esac
done

echo -e "${BLUE}===> [自动化环境初始化] 启动中...${NC}"

# 让脚本可以从任意目录运行，也不要求仓库必须位于 ~/dotfiles。
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 创建必要的本地目录
run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[dry-run] $*${NC}"
    else
        "$@"
    fi
}

write_file() {
    local file=$1
    local content=$2
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[dry-run] write ${file}${NC}"
    else
        printf '%s\n' "$content" > "$file"
    fi
}

append_line() {
    local file=$1
    local content=$2
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[dry-run] append to ${file}: ${content}${NC}"
    else
        printf '%s\n' "$content" >> "$file"
    fi
}

file_contains() {
    local pattern=$1
    local file=$2
    [ -f "$file" ] && grep -q "$pattern" "$file"
}

make_temp_file() {
    mktemp "${TMPDIR:-/tmp}/dotfiles-remote.XXXXXX"
}

version_number() {
    local version=${1#v}
    local major minor patch
    IFS=. read -r major minor patch <<< "$version"
    printf '%03d%03d%03d\n' "${major:-0}" "${minor:-0}" "${patch:-0}"
}

version_gt() {
    [ "$(version_number "$1")" -gt "$(version_number "$2")" ]
}

version_lt() {
    [ "$(version_number "$1")" -lt "$(version_number "$2")" ]
}

has_proxy_env() {
    [ -n "${HTTPS_PROXY:-}" ] || [ -n "${https_proxy:-}" ] || \
        [ -n "${HTTP_PROXY:-}" ] || [ -n "${http_proxy:-}" ] || \
        [ -n "${ALL_PROXY:-}" ] || [ -n "${all_proxy:-}" ]
}

maybe_warn_github_proxy() {
    local url=$1
    if [[ "$url" == *github.com* || "$url" == *githubusercontent.com* ]] && ! has_proxy_env; then
        echo -e "${YELLOW}提示：正在访问 GitHub 资源，但未检测到 HTTPS_PROXY / HTTP_PROXY / ALL_PROXY。${NC}"
        echo -e "${YELLOW}如果下载长时间 0 字节，请先打开代理，或执行类似：export HTTPS_PROXY=http://127.0.0.1:7890${NC}"
    fi
}

set_vscode_terminal_font() {
    if [ "$MACHINE" != "Mac" ]; then
        return 0
    fi

    local settings_file="$HOME/Library/Application Support/Code/User/settings.json"
    local settings_dir
    settings_dir="$(dirname "$settings_file")"

    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[dry-run] set VS Code terminal.integrated.fontFamily to ${TERMINAL_FONT_FAMILY} in ${settings_file}${NC}"
        return 0
    fi

    mkdir -p "$settings_dir"

    if command -v node &> /dev/null; then
        SETTINGS_FILE="$settings_file" FONT_FAMILY="$TERMINAL_FONT_FAMILY" node <<'NODE'
const fs = require('fs');
const file = process.env.SETTINGS_FILE;
const fontFamily = process.env.FONT_FAMILY;
let settings = {};

if (fs.existsSync(file)) {
  const raw = fs.readFileSync(file, 'utf8').trim();
  if (raw) settings = JSON.parse(raw);
}

settings['terminal.integrated.fontFamily'] = fontFamily;
fs.writeFileSync(file, JSON.stringify(settings, null, 2) + '\n');
NODE
    elif command -v python3 &> /dev/null; then
        SETTINGS_FILE="$settings_file" FONT_FAMILY="$TERMINAL_FONT_FAMILY" python3 <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["SETTINGS_FILE"])
font_family = os.environ["FONT_FAMILY"]
settings = {}

if path.exists() and path.read_text().strip():
    settings = json.loads(path.read_text())

settings["terminal.integrated.fontFamily"] = font_family
path.write_text(json.dumps(settings, indent=2, ensure_ascii=False) + "\n")
PY
    else
        echo -e "${YELLOW}未找到 node 或 python3，无法自动修改 VS Code settings.json。${NC}"
        echo -e "${YELLOW}请手动设置 terminal.integrated.fontFamily 为 ${TERMINAL_FONT_FAMILY}。${NC}"
        return 1
    fi

    echo -e "${GREEN}✔ VS Code 终端字体已设置为 ${TERMINAL_FONT_FAMILY}。${NC}"
}

run_cmd mkdir -p "$HOME/.local/bin" "$HOME/.zsh" "$HOME/.config"

# --- 🚀 核心交互函数：经典的 Y/n 模式 ---
ask_confirm() {
    local prompt_text=$1
    if [ "$ASSUME_YES" = true ]; then
        echo -e "${YELLOW}${prompt_text} [Y/n]: Y${NC}"
        return 0
    fi

    echo -ne "${YELLOW}${prompt_text} [Y/n]: ${NC}"
    read -r response
    # 默认回车为 Y
    if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
        return 0 # true (同意)
    else
        return 1 # false (拒绝)
    fi
}

# --- 权限检查函数 ---
can_sudo() {
    if sudo -n true 2>/dev/null; then return 0; else return 1; fi
}

# --- 网络下载辅助函数：失败时给出明确提示，避免半安装继续推进 ---
download_file() {
    local url=$1
    local output=$2
    maybe_warn_github_proxy "$url"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[dry-run] download ${url} -> ${output}${NC}"
        return 0
    fi

    if ! curl -fL --connect-timeout 10 --max-time 120 --speed-time 20 --speed-limit 1024 --retry 2 --retry-delay 2 "$url" -o "$output"; then
        echo -e "${RED}下载失败: ${url}${NC}"
        echo -e "${YELLOW}如果这里显示长时间 0 字节，通常是 GitHub 直连问题。请打开代理后重试。${NC}"
        return 1
    fi
}

verify_sha256() {
    local file=$1
    local expected=$2

    if [ -z "$expected" ]; then
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[dry-run] verify sha256 ${file}${NC}"
        return 0
    fi

    local actual
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        echo -e "${RED}SHA256 校验失败: ${file}${NC}"
        echo -e "${RED}期望: ${expected}${NC}"
        echo -e "${RED}实际: ${actual}${NC}"
        return 1
    fi
}

download_file_sha256() {
    local url=$1
    local output=$2
    local expected_sha256=$3

    download_file "$url" "$output" && verify_sha256 "$output" "$expected_sha256"
}

download_to_stdout() {
    local url=$1
    maybe_warn_github_proxy "$url"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[dry-run] download ${url} -> stdout${NC}" >&2
        return 0
    fi

    if ! curl -fsSL --connect-timeout 10 --max-time 120 --speed-time 20 --speed-limit 1024 --retry 2 --retry-delay 2 "$url"; then
        echo -e "${RED}下载失败: ${url}${NC}" >&2
        echo -e "${YELLOW}如果这里显示长时间 0 字节，通常是 GitHub 直连问题。请打开代理后重试。${NC}" >&2
        return 1
    fi
}

run_remote_bash() {
    local url=$1
    local script_path
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[dry-run] download and run bash script: ${url}${NC}"
        return 0
    fi

    script_path="$(make_temp_file)"

    if ! download_file "$url" "$script_path"; then
        rm -f "$script_path"
        return 1
    fi

    bash "$script_path"
    local status=$?
    rm -f "$script_path"
    return "$status"
}

run_remote_sh() {
    local url=$1
    shift
    local script_path
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}[dry-run] download and run sh script: ${url} $*${NC}"
        return 0
    fi

    script_path="$(make_temp_file)"

    if ! download_file "$url" "$script_path"; then
        rm -f "$script_path"
        return 1
    fi

    sh "$script_path" "$@"
    local status=$?
    rm -f "$script_path"
    return "$status"
}

install_or_update_nvm_with_git() {
    local version=$1
    local repo_url="https://github.com/nvm-sh/nvm.git"

    if ! command -v git &> /dev/null; then
        return 1
    fi

    maybe_warn_github_proxy "$repo_url"

    if [ "$DRY_RUN" = true ]; then
        if [ -d "$NVM_DIR/.git" ]; then
            echo -e "${BLUE}[dry-run] git -C ${NVM_DIR} fetch origin tag ${version} --depth=1${NC}"
            echo -e "${BLUE}[dry-run] git -C ${NVM_DIR} checkout -f FETCH_HEAD${NC}"
        else
            echo -e "${BLUE}[dry-run] git clone --depth 1 --branch ${version} ${repo_url} ${NVM_DIR}${NC}"
        fi
        return 0
    fi

    if [ -d "$NVM_DIR/.git" ]; then
        echo -e "${GREEN}正在通过 git 更新 NVM 到 ${version}...${NC}"
        git -C "$NVM_DIR" fetch origin tag "$version" --depth=1 || git -C "$NVM_DIR" fetch origin "$version" --depth=1 || return 1
        git -C "$NVM_DIR" checkout -f FETCH_HEAD || return 1
    elif [ ! -e "$NVM_DIR" ] || [ -z "$(ls -A "$NVM_DIR" 2>/dev/null)" ]; then
        echo -e "${GREEN}正在通过 git 克隆 NVM ${version}...${NC}"
        rm -rf "$NVM_DIR"
        git clone --depth 1 --branch "$version" "$repo_url" "$NVM_DIR" || return 1
    else
        echo -e "${YELLOW}${NVM_DIR} 已存在但不是 git 仓库，跳过 git 方式。${NC}"
        return 1
    fi
}

ensure_brew() {
    if [ "$MACHINE" != "Mac" ]; then
        return 1
    fi

    if command -v brew &> /dev/null; then
        return 0
    fi

    echo -e "${YELLOW}未检测到 Homebrew，将直接下载并安装。${NC}"
    echo -e "${YELLOW}提示：Homebrew 安装脚本来自 GitHub。如果 raw.githubusercontent.com 访问慢或失败，请先打开代理，或提前设置 HTTPS_PROXY / ALL_PROXY。${NC}"
    echo -e "${GREEN}正在安装 Homebrew...${NC}"
    if run_remote_bash "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"; then
        if [ "$DRY_RUN" != true ]; then
            eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"
            eval "$(/usr/local/bin/brew shellenv 2>/dev/null)"
        fi
    else
        echo -e "${RED}Homebrew 安装失败。依赖 Homebrew 的步骤将被跳过。${NC}"
        return 1
    fi

    command -v brew &> /dev/null || [ "$DRY_RUN" = true ]
}

# ==========================================
# 0. 操作系统检测与包管理器初始化
# ==========================================
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE="Linux";;
    Darwin*)    MACHINE="Mac";;
    *)          MACHINE="UNKNOWN";;
esac

echo -e "${BLUE}检测到当前系统为: ${MACHINE}${NC}"

# 统一的包安装函数
install_package() {
    local pkg_name=$1
    if [ "$MACHINE" == "Mac" ]; then
        if ensure_brew; then
            run_cmd brew install "$pkg_name"
        else
            echo -e "${RED}Homebrew 不可用，跳过安装 ${pkg_name}。${NC}"
            return 1
        fi
    elif [ "$MACHINE" == "Linux" ]; then
        if can_sudo; then
            run_cmd sudo apt-get update && run_cmd sudo apt-get install -y "$pkg_name"
        else
            echo -e "${RED}无 sudo 权限，跳过通过 apt 安装 ${pkg_name}。${NC}"
            return 1
        fi
    fi
}

# Mac 专属：Homebrew 检查与更新
if [ "$MACHINE" == "Mac" ]; then
    if ensure_brew; then
        if ask_confirm "检测到 Homebrew 已安装。是否需要执行 brew update 获取最新软件源？"; then
            echo -e "${GREEN}正在更新 Homebrew...${NC}"
            run_cmd brew update
        fi
    else
        echo -e "${YELLOW}Homebrew 不可用。后续依赖 Homebrew 的步骤会自动跳过。${NC}"
    fi
fi

# ==========================================
# 1. 基础工具链检查 (Git & Git LFS)
# ==========================================
if ! command -v git &> /dev/null; then
    if ask_confirm "检测到 Git 缺失。是否立即安装？"; then
        install_package "git"
    fi
fi

if ! command -v git-lfs &> /dev/null; then
    if ask_confirm "检测到 Git LFS 缺失。是否立即安装？"; then
        if [ "$MACHINE" == "Mac" ] || can_sudo; then
            install_package "git-lfs"
        else
            # Linux 无 sudo 备用方案
            LFS_URL="https://github.com/git-lfs/git-lfs/releases/download/v3.4.0/git-lfs-linux-amd64-v3.4.0.tar.gz"
            LFS_SHA256="60b7e9b9b4bca04405af58a2cd5dff3e68a5607c5bc39ee88a5256dd7a07f58c"
            LFS_ARCHIVE="/tmp/git-lfs-linux-amd64-v3.4.0.tar.gz"
            if [ "$DRY_RUN" = true ]; then
                echo -e "${BLUE}[dry-run] download and verify ${LFS_URL}${NC}"
                echo -e "${BLUE}[dry-run] tar xz -C /tmp -f ${LFS_ARCHIVE}${NC}"
                echo -e "${BLUE}[dry-run] move git-lfs binary to $HOME/.local/bin/${NC}"
            elif download_file_sha256 "$LFS_URL" "$LFS_ARCHIVE" "$LFS_SHA256" && tar xzf "$LFS_ARCHIVE" -C /tmp; then
                run_cmd mv /tmp/git-lfs-3.4.0/git-lfs "$HOME/.local/bin/"
                run_cmd rm -f "$LFS_ARCHIVE"
            else
                run_cmd rm -f "$LFS_ARCHIVE"
                echo -e "${RED}Git LFS 下载失败，跳过安装。${NC}"
            fi
        fi
        if command -v git-lfs &> /dev/null || [ "$DRY_RUN" = true ]; then
            run_cmd git lfs install
            echo -e "${GREEN}Git LFS 安装成功。${NC}"
        fi
    fi
fi

# ==========================================
# 2. 炼丹炉环境 (Miniconda)
# ==========================================
if ! command -v conda &> /dev/null; then
    if ask_confirm "检测到 Miniconda 缺失。是否下载并安装？"; then
        echo -e "${GREEN}正在安装 Miniconda...${NC}"
        CONDA_INSTALLER="/tmp/miniconda_install.sh"
        if [ "$MACHINE" == "Mac" ]; then
            MAC_ARCH=$(uname -m)
            if [ "$MAC_ARCH" == "arm64" ]; then
                CONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_26.3.2-2-MacOSX-arm64.sh"
                CONDA_SHA256="6efc019c78003166fec1551486c68e08605eaca009039b1cda5f4e919e0c6dce"
            else
                CONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_25.7.0-2-MacOSX-x86_64.sh"
                CONDA_SHA256="9c88674b1a839eeb4cff006df397a05ea7d896472318fd84b7070278f9653dc6"
            fi
        else
            CONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-py313_26.3.2-2-Linux-x86_64.sh"
            CONDA_SHA256="2284bafb7863a23411b19874d216e237964d4b32dd9beb6807fa8b2d84570961"
        fi

        if ! download_file_sha256 "$CONDA_URL" "$CONDA_INSTALLER" "$CONDA_SHA256"; then
            echo -e "${RED}Miniconda 下载失败，跳过安装。${NC}"
        elif run_cmd bash "$CONDA_INSTALLER" -b -p "$HOME/miniconda3"; then
            run_cmd rm -f "$CONDA_INSTALLER"
            echo -e "${GREEN}Miniconda 已安装至 ~/miniconda3${NC}"
        else
            run_cmd rm -f "$CONDA_INSTALLER"
            echo -e "${RED}Miniconda 安装失败。${NC}"
        fi
    fi
fi

# ==========================================
# 3. 前端与 Agent 环境 (NVM & Node.js)
# ==========================================
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# 增加 -m 3 (3秒超时)，防止网络不佳时脚本死等
if [ "$DRY_RUN" = true ]; then
    LATEST_NVM_VERSION=""
else
    LATEST_NVM_VERSION=$(curl -m 3 -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
fi

if ! command -v nvm &> /dev/null; then
    # 如果没安装，且网络挂了没抓到，给一个默认的稳定版保底
    LATEST_NVM_VERSION=${LATEST_NVM_VERSION:-v0.40.1}
    if ask_confirm "未找到 NVM。是否首次下载安装 ($LATEST_NVM_VERSION)？"; then
        echo -e "${YELLOW}提示：优先通过 git 安装 NVM，避免 raw.githubusercontent.com 下载正文卡住。${NC}"
        if install_or_update_nvm_with_git "$LATEST_NVM_VERSION"; then
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        else
            echo -e "${YELLOW}git 方式安装失败，尝试使用 raw.githubusercontent.com 安装脚本。${NC}"
            echo -e "${YELLOW}如果 raw.githubusercontent.com 访问慢或失败，请检查代理是否对命令行 GitHub 流量生效。${NC}"
            if run_remote_bash "https://raw.githubusercontent.com/nvm-sh/nvm/${LATEST_NVM_VERSION}/install.sh"; then
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            fi
        fi
    fi
else
    CURRENT_NVM_VERSION="v$(nvm --version)"
    # 【核心防御】只有当抓到了线上版本，且线上版本和本地不同时，才提示更新！
    if [ -n "$LATEST_NVM_VERSION" ] && [ "$CURRENT_NVM_VERSION" != "$LATEST_NVM_VERSION" ]; then
        if ask_confirm "发现 NVM 新版本 ($LATEST_NVM_VERSION)，当前版本 ($CURRENT_NVM_VERSION)。是否更新？"; then
            echo -e "${YELLOW}提示：优先通过 git 更新 NVM，避免 raw.githubusercontent.com 下载正文卡住。${NC}"
            if install_or_update_nvm_with_git "$LATEST_NVM_VERSION"; then
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            else
                echo -e "${YELLOW}git 方式更新失败，尝试使用 raw.githubusercontent.com 安装脚本。${NC}"
                echo -e "${YELLOW}如果 raw.githubusercontent.com 访问慢或失败，请检查代理是否对命令行 GitHub 流量生效。${NC}"
                if run_remote_bash "https://raw.githubusercontent.com/nvm-sh/nvm/${LATEST_NVM_VERSION}/install.sh"; then
                    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
                fi
            fi
        fi
    fi
fi

if command -v nvm &> /dev/null; then
    if [ "$DRY_RUN" = true ]; then
        LATEST_NODE_LTS=""
    else
        LATEST_NODE_LTS=$(nvm ls-remote --lts | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' | tail -1)
    fi
    
    if ! command -v node &> /dev/null; then
        if ask_confirm "未找到 Node.js。是否使用 NVM 安装最新 LTS 长期支持版？"; then
            run_cmd nvm install --lts && run_cmd nvm use --lts && run_cmd nvm alias default 'lts/*'
        fi
    else
        CURRENT_NODE_VERSION=$(node -v)
        # 只在当前版本低于 LTS 时升级；如果当前版本比 LTS 新，不回退。
        if [ -n "$LATEST_NODE_LTS" ] && version_lt "$CURRENT_NODE_VERSION" "$LATEST_NODE_LTS"; then
            if ask_confirm "发现 Node.js LTS 版本 ($LATEST_NODE_LTS) 高于当前版本 ($CURRENT_NODE_VERSION)。是否平滑更新并迁移全局包？"; then
                run_cmd nvm install --lts --reinstall-packages-from=current
                run_cmd nvm use --lts && run_cmd nvm alias default 'lts/*'
                echo -e "${YELLOW}提示：NVM 会保留旧 Node.js 版本。如需清理旧版本，可之后运行 nvm uninstall <旧版本号>。${NC}"
            fi
        elif [ -n "$LATEST_NODE_LTS" ] && version_gt "$CURRENT_NODE_VERSION" "$LATEST_NODE_LTS"; then
            echo -e "${GREEN}当前 Node.js ($CURRENT_NODE_VERSION) 高于最新 LTS ($LATEST_NODE_LTS)，保持现有版本，不回退。${NC}"
        fi
    fi
fi
# --- 新增：Claude Code (AI Agent) 检查与安装 ---
if ! command -v claude &> /dev/null; then
    if ask_confirm "未找到 Claude Code (AI 编程助手)。是否立即安装？"; then
        if [ "$MACHINE" == "Mac" ]; then
            # Mac 专属路线：使用 Homebrew (Cask) 安装
            if ensure_brew; then
                echo -e "${GREEN}正在通过 Homebrew 安装 Claude Code...${NC}"
                run_cmd brew install --cask claude-code
            else
                echo -e "${RED}Homebrew 不可用，跳过 Claude Code 安装。${NC}"
            fi
        elif [ "$MACHINE" == "Linux" ]; then
            # Linux 专属路线：必须依赖 npm 全局安装
            if command -v npm &> /dev/null; then
                echo -e "${GREEN}正在通过 npm 全局安装 Claude Code...${NC}"
                run_cmd npm install -g @anthropic-ai/claude-code
            else
                echo -e "${RED}安装跳过：Linux 环境下需要 npm，请先确保上面的 Node.js 环境已成功安装。${NC}"
            fi
        fi
        
        # --- 极客专属：自动跳过新手引导 (Onboarding) ---
        CLAUDE_CONFIG="$HOME/.claude.json"
        if [ ! -f "$CLAUDE_CONFIG" ]; then
            # 如果文件不存在，直接生成并注入配置
            write_file "$CLAUDE_CONFIG" '{"hasCompletedOnboarding": true}'
            echo -e "${GREEN}已自动为你生成 ~/.claude.json，完美跳过初次启动引导！${NC}"
        else
            # 如果文件已存在，使用黄色字强提醒
            echo -e "${YELLOW}提示: 你的 ~/.claude.json 文件已存在。${NC}"
            echo -e "${YELLOW}建议手动打开它，并确保里面包含: \"hasCompletedOnboarding\": true${NC}"
        fi
    fi
fi

# ==========================================
# 4. 终端颜值与效率组件 (Terminal, Starship, Zsh, Fonts)
# ==========================================

# --- 新增：强制重置 Mac 自带终端的外观主题 ---
if [ "$MACHINE" == "Mac" ]; then
    if ask_confirm "是否要将 Mac 自带终端 Terminal.app 设置为 Clear Dark，并将终端字体设为 ${TERMINAL_FONT_FAMILY}？"; then
        echo -e "${YELLOW}正在通过 AppleScript 设置终端外观...${NC}"
        # 告诉 Mac 终端：以后新建的窗口都用 Clear Dark 主题，并使用 Nerd Font Mono。
        run_cmd osascript -e 'tell application "Terminal" to set default settings to settings set "Clear Dark"'
        run_cmd osascript -e "tell application \"Terminal\" to set font name of settings set \"Clear Dark\" to \"$TERMINAL_FONT_FAMILY\""
        run_cmd osascript -e "tell application \"Terminal\" to set font size of settings set \"Clear Dark\" to $TERMINAL_FONT_SIZE"
        # 告诉 Mac 终端：把当前正在开着的窗口也立刻变成 Clear Dark 主题和同一字体。
        run_cmd osascript -e 'tell application "Terminal" to set current settings of tabs of windows to settings set "Clear Dark"'
        run_cmd osascript -e "tell application \"Terminal\" to set font name of current settings of tabs of windows to \"$TERMINAL_FONT_FAMILY\""
        run_cmd osascript -e "tell application \"Terminal\" to set font size of current settings of tabs of windows to $TERMINAL_FONT_SIZE"
        echo -e "${GREEN}✔ Mac 终端外观已设置为 Clear Dark，字体已设置为 ${TERMINAL_FONT_FAMILY}。${NC}"
    fi
fi

echo -e "${YELLOW}正在检查系统 Nerd Font 极客字体环境...${NC}"
FONT_INSTALLED=false

# 粗略判断字体是否已存在
if [ "$MACHINE" == "Mac" ]; then
    MAC_FONT_DIR="$HOME/Library/Fonts"
    if [ -f "$MAC_FONT_DIR/MesloLGSNerdFontMono-Regular.ttf" ] && \
       [ -f "$MAC_FONT_DIR/MesloLGSNerdFontMono-Bold.ttf" ] && \
       [ -f "$MAC_FONT_DIR/MesloLGSNerdFontMono-Italic.ttf" ] && \
       [ -f "$MAC_FONT_DIR/MesloLGSNerdFontMono-BoldItalic.ttf" ]; then
        FONT_INSTALLED=true
    fi
elif command -v fc-list &> /dev/null; then
    if fc-list | grep -q "MesloLGS Nerd Font Mono"; then
        FONT_INSTALLED=true
    fi
fi

if [ "$FONT_INSTALLED" = false ]; then
    if ask_confirm "未检测到 Starship 推荐字体 (MesloLGS Nerd Font Mono 四个字重)。是否立即下载安装？"; then
        echo -e "${GREEN}正在安装 MesloLGS Nerd Font Mono 的 Regular / Bold / Italic / Bold Italic 四个字体文件...${NC}"
        if [ "$MACHINE" == "Mac" ]; then
            FONT_DIR="$HOME/Library/Fonts"
        else
            FONT_DIR="$HOME/.local/share/fonts"
        fi

        MESLO_VERSION="v3.4.0"
        MESLO_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${MESLO_VERSION}/Meslo.tar.xz"
        MESLO_ARCHIVE="/tmp/Meslo-${MESLO_VERSION}.tar.xz"
        MESLO_EXTRACT_DIR="/tmp/Meslo-${MESLO_VERSION}"
        FONTS_OK=true

        run_cmd mkdir -p "$FONT_DIR" "$MESLO_EXTRACT_DIR"
        echo -e "${YELLOW}提示：字体包来自 GitHub。如果下载慢或失败，请先打开代理，或提前设置 HTTPS_PROXY / ALL_PROXY。${NC}"
        if download_file "$MESLO_URL" "$MESLO_ARCHIVE"; then
            if [ "$DRY_RUN" = true ]; then
                echo -e "${BLUE}[dry-run] extract ${MESLO_ARCHIVE} -> ${MESLO_EXTRACT_DIR}${NC}"
            elif ! tar xJf "$MESLO_ARCHIVE" -C "$MESLO_EXTRACT_DIR"; then
                FONTS_OK=false
            fi
        else
            FONTS_OK=false
        fi

        if [ "$FONTS_OK" = true ]; then
            for font_file in \
                MesloLGSNerdFontMono-Regular.ttf \
                MesloLGSNerdFontMono-Bold.ttf \
                MesloLGSNerdFontMono-Italic.ttf \
                MesloLGSNerdFontMono-BoldItalic.ttf
            do
                if [ "$DRY_RUN" = true ]; then
                    echo -e "${BLUE}[dry-run] install ${font_file} -> ${FONT_DIR}/${font_file}${NC}"
                elif [ -f "$MESLO_EXTRACT_DIR/$font_file" ]; then
                    cp "$MESLO_EXTRACT_DIR/$font_file" "$FONT_DIR/$font_file"
                else
                    echo -e "${RED}字体包中缺少 ${font_file}${NC}"
                    FONTS_OK=false
                fi
            done
        fi

        if [ "$FONTS_OK" != true ]; then
            echo -e "${RED}字体安装失败，请稍后重新运行脚本。${NC}"
        elif [ "$MACHINE" == "Linux" ] && command -v fc-cache &> /dev/null; then
            run_cmd fc-cache -f -v > /dev/null
            echo -e "${GREEN}✔ MesloLGS Nerd Font Mono 四个字重已安装。${NC}"
        else
            echo -e "${GREEN}✔ MesloLGS Nerd Font Mono 四个字重已安装。${NC}"
        fi

        run_cmd rm -rf "$MESLO_EXTRACT_DIR" "$MESLO_ARCHIVE"
        echo -e "${YELLOW}提示：字体按固定文件名安装，重新运行会覆盖同名字体文件；脚本不会自动删除以前通过 Homebrew 安装的完整 Meslo 字体包。${NC}"
        if [ "$MACHINE" == "Mac" ]; then
            echo -e "${YELLOW}如需移除旧的 Homebrew 字体包，可手动执行: brew uninstall --cask font-meslo-lg-nerd-font${NC}"
        fi
    fi
else
    echo -e "${GREEN}✔ MesloLGS Nerd Font Mono 已安装，图标支持就绪。${NC}"
fi

if [ "$MACHINE" == "Mac" ]; then
    if ask_confirm "是否要将 VS Code 终端字体设置为 ${TERMINAL_FONT_FAMILY}？"; then
        set_vscode_terminal_font
    fi
fi

# starship与插件安装
if ! command -v starship &> /dev/null; then
    if ask_confirm "未找到 Starship 主题。是否下载安装？"; then
        if [ "$MACHINE" == "Mac" ]; then
            # Mac 路线：使用 Homebrew
            if ensure_brew; then
                echo -e "${GREEN}正在通过 Homebrew 安装 Starship...${NC}"
                run_cmd brew install starship
            else
                echo -e "${RED}Homebrew 不可用，跳过 Starship 安装。${NC}"
            fi
        else
            # Linux 路线：使用官方纯净脚本
            echo -e "${GREEN}正在通过官方脚本安装 Starship...${NC}"
            run_remote_sh "https://starship.rs/install.sh" -y -b "$HOME/.local/bin"
        fi
    fi
fi

if [ "$MACHINE" == "Mac" ]; then
    # Mac 专属：使用 Brew 安装和管理 Zsh 插件
    if ensure_brew && { [ ! -d "$(brew --prefix)/share/zsh-autosuggestions" ] || [ ! -d "$(brew --prefix)/share/zsh-syntax-highlighting" ]; }; then
        echo -e "${YELLOW}将安装的 Zsh 效率插件：${NC}"
        echo -e "${YELLOW}- zsh-autosuggestions：根据历史命令给出灰色自动建议。${NC}"
        echo -e "${YELLOW}- zsh-syntax-highlighting：输入命令时实时高亮语法和错误。${NC}"
        if ask_confirm "检测到 Zsh 效率插件未安装。是否通过 Homebrew 下载？"; then
            echo -e "${GREEN}正在通过 Homebrew 安装 Zsh 插件...${NC}"
            run_cmd brew install zsh-autosuggestions zsh-syntax-highlighting
        fi
    fi
else
    # Linux 专属：依然使用 Git Clone 到本地 (无需 root 和 brew)
    if [ ! -d "$HOME/.zsh/zsh-autosuggestions" ] || [ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ]; then
        echo -e "${YELLOW}将安装的 Zsh 效率插件：${NC}"
        echo -e "${YELLOW}- zsh-autosuggestions：根据历史命令给出灰色自动建议。${NC}"
        echo -e "${YELLOW}- zsh-syntax-highlighting：输入命令时实时高亮语法和错误。${NC}"
        if ask_confirm "检测到 Zsh 效率插件未完全同步。是否从 GitHub 克隆下载？"; then
            [ ! -d "$HOME/.zsh/zsh-autosuggestions" ] && run_cmd git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/zsh-autosuggestions"
            [ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ] && run_cmd git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.zsh/zsh-syntax-highlighting"
        fi
    fi
fi

# ==========================================
# 5. 收尾：配置文件挂载与动态配置追加
# ==========================================
echo -e "\n${YELLOW}正在挂载 Dotfiles 软链接...${NC}"
run_cmd ln -sf "$DOTFILES_DIR/zsh/zshrc" "$HOME/.zshrc"
run_cmd ln -sf "$DOTFILES_DIR/starship/starship.toml" "$HOME/.config/starship.toml"

# 1. 确保 .zshrc.local 文件存在
if [ ! -f "$HOME/.zshrc.local" ]; then
    run_cmd touch "$HOME/.zshrc.local"
    append_line "$HOME/.zshrc.local" "# 存放本机特有的环境变量或初始化代码"
    append_line "$HOME/.zshrc.local" "# 注意：等号两边绝对不能有空格！"
    append_line "$HOME/.zshrc.local" 'export STARSHIP_ROLE="YourNameHere"'
    echo -e "${GREEN}已为你创建缺省的 ~/.zshrc.local 模板。${NC}"
fi

echo -e "${YELLOW}正在向 ~/.zshrc.local 注入核心组件路径...${NC}"

# 2. 注入 NVM / Node.js 初始化代码 (防重复)
if ! file_contains 'export NVM_DIR="$HOME/.nvm"' "$HOME/.zshrc.local"; then
    append_line "$HOME/.zshrc.local" ""
    append_line "$HOME/.zshrc.local" "# 初始化 NVM (Node Version Manager)"
    append_line "$HOME/.zshrc.local" 'export NVM_DIR="$HOME/.nvm"'
    append_line "$HOME/.zshrc.local" '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm'
    append_line "$HOME/.zshrc.local" '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion'
    echo -e "${GREEN}✔ NVM 路径已添加${NC}"
fi

# 3. 注入 Miniconda 初始化代码 (防重复)
if ! file_contains "conda shell.zsh hook" "$HOME/.zshrc.local"; then
    append_line "$HOME/.zshrc.local" ""
    append_line "$HOME/.zshrc.local" "# 初始化 Miniconda"
    # 使用动态 hook 方式，最干净，不污染环境变量
    append_line "$HOME/.zshrc.local" 'eval "$($HOME/miniconda3/bin/conda shell.zsh hook 2>/dev/null)"'
    echo -e "${GREEN}✔ Miniconda 路径已添加${NC}"
fi

# 4. 注入 Starship 初始化命令 (防重复)
if ! file_contains "starship init zsh" "$HOME/.zshrc.local"; then
    append_line "$HOME/.zshrc.local" ""
    append_line "$HOME/.zshrc.local" "# 初始化 Starship 提示符"
    append_line "$HOME/.zshrc.local" 'eval "$(starship init zsh)"'
    echo -e "${GREEN}✔ Starship 启动命令已添加${NC}"
fi

# 5. 注入 Zsh 插件路径 (区分 Mac 和 Linux，防重复)
if [ "$MACHINE" == "Mac" ]; then
    if ! file_contains "zsh-autosuggestions.zsh" "$HOME/.zshrc.local"; then
        append_line "$HOME/.zshrc.local" ""
        append_line "$HOME/.zshrc.local" "# 自动建议（灰色提示）"
        append_line "$HOME/.zshrc.local" 'source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh'
    fi
    if ! file_contains "zsh-syntax-highlighting.zsh" "$HOME/.zshrc.local"; then
        append_line "$HOME/.zshrc.local" "# 语法高亮（命令颜色）"
        append_line "$HOME/.zshrc.local" 'source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
        echo -e "${GREEN}✔ Mac 版 Zsh 插件路径已添加${NC}"
    fi
else
    # Linux 使用本地克隆的路径
    if ! file_contains "zsh-autosuggestions.zsh" "$HOME/.zshrc.local"; then
        append_line "$HOME/.zshrc.local" ""
        append_line "$HOME/.zshrc.local" "# 自动建议（灰色提示）"
        append_line "$HOME/.zshrc.local" 'source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh'
    fi
    if ! file_contains "zsh-syntax-highlighting.zsh" "$HOME/.zshrc.local"; then
        append_line "$HOME/.zshrc.local" "# 语法高亮（命令颜色）"
        append_line "$HOME/.zshrc.local" 'source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
        echo -e "${GREEN}✔ Linux 版 Zsh 插件路径已添加${NC}"
    fi
fi

# --- 醒目的多设备配置提醒 ---
echo -e "\n${RED}======================================================================${NC}"
echo -e "${RED}⚠️  极其重要的最后两步：配置身份与激活字体 ⚠️${NC}"
echo -e "${YELLOW}为了让终端完美运作，请必须执行以下操作：${NC}"
echo -e "\n${BLUE}【任务 1：配置专属终端身份】${NC}"
echo -e "1. 输入命令打开本地配置：${GREEN}nano ~/.zshrc.local${NC}"
echo -e "2. 找到并修改变量为你的设备名 (如 MACyxy, HUSTyxy)："
echo -e "   export STARSHIP_ROLE=\"你的专属名字\""
echo -e "3. 保存退出后，敲下重启魔法：${GREEN}exec zsh${NC}"
echo -e "\n${BLUE}【任务 2：手动在终端软件中应用字体 (仅首次需要)】${NC}"
echo -e "由于脚本无法修改你的图形界面，请务必手动设置："
echo -e "- ${YELLOW}Mac 自带终端:${NC} 偏好设置 -> 描述文件 -> 文本 -> 字体 -> 更改为 ${GREEN}MesloLGS Nerd Font Mono${NC}"
echo -e "- ${YELLOW}VS Code:${NC} 设置 -> 搜索 'Terminal Font' -> 填入 ${GREEN}'MesloLGS Nerd Font Mono'${NC}"
echo -e "- ${YELLOW}iTerm2:${NC} Preferences -> Profiles -> Text -> Font -> 选 ${GREEN}MesloLGS Nerd Font Mono${NC}"
echo -e "${RED}======================================================================\n${NC}"

echo -e "${GREEN}===> [基础配置全部完成]${NC}"
