#!/bin/bash

# --- 颜色与基础设置 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}===> [自动化环境初始化] 启动中...${NC}"

# 创建必要的本地目录
mkdir -p ~/.local/bin ~/.zsh ~/.config

# --- 🚀 核心交互函数：经典的 Y/n 模式 ---
ask_confirm() {
    local prompt_text=$1
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
        brew install "$pkg_name"
    elif [ "$MACHINE" == "Linux" ]; then
        if can_sudo; then
            sudo apt-get update && sudo apt-get install -y "$pkg_name"
        else
            echo -e "${RED}无 sudo 权限，跳过通过 apt 安装 ${pkg_name}。${NC}"
            return 1
        fi
    fi
}

# Mac 专属：Homebrew 检查与更新
if [ "$MACHINE" == "Mac" ]; then
    if ! command -v brew &> /dev/null; then
        if ask_confirm "未检测到包管理器 Homebrew。是否立即下载并安装？"; then
            echo -e "${GREEN}正在安装 Homebrew...${NC}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # 无缝桥接：将新装的 brew 注入当前会话
            eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"
            eval "$(/usr/local/bin/brew shellenv 2>/dev/null)"
        else
            echo -e "${RED}已跳过 Homebrew 安装。后续依赖可能无法正常配置。${NC}"
        fi
    else
        if ask_confirm "检测到 Homebrew 已安装。是否需要执行 brew update 获取最新软件源？"; then
            echo -e "${GREEN}正在更新 Homebrew...${NC}"
            brew update
        fi
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
            curl -L $LFS_URL | tar xz -C /tmp
            mv /tmp/git-lfs-3.4.0/git-lfs ~/.local/bin/
        fi
        git lfs install
        echo -e "${GREEN}Git LFS 安装成功。${NC}"
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
                curl -L https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh -o $CONDA_INSTALLER
            else
                curl -L https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -o $CONDA_INSTALLER
            fi
        else
            curl -L https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o $CONDA_INSTALLER
        fi
        bash $CONDA_INSTALLER -b -p $HOME/miniconda3
        rm $CONDA_INSTALLER
        echo -e "${GREEN}Miniconda 已安装至 ~/miniconda3${NC}"
    fi
fi

# ==========================================
# 3. 前端与 Agent 环境 (NVM & Node.js)
# ==========================================
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# 增加 -m 3 (3秒超时)，防止网络不佳时脚本死等
LATEST_NVM_VERSION=$(curl -m 3 -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if ! command -v nvm &> /dev/null; then
    # 如果没安装，且网络挂了没抓到，给一个默认的稳定版保底
    LATEST_NVM_VERSION=${LATEST_NVM_VERSION:-v0.40.1}
    if ask_confirm "未找到 NVM。是否首次下载安装 ($LATEST_NVM_VERSION)？"; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${LATEST_NVM_VERSION}/install.sh | bash
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    fi
else
    CURRENT_NVM_VERSION="v$(nvm --version)"
    # 【核心防御】只有当抓到了线上版本，且线上版本和本地不同时，才提示更新！
    if [ -n "$LATEST_NVM_VERSION" ] && [ "$CURRENT_NVM_VERSION" != "$LATEST_NVM_VERSION" ]; then
        if ask_confirm "发现 NVM 新版本 ($LATEST_NVM_VERSION)，当前版本 ($CURRENT_NVM_VERSION)。是否更新？"; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${LATEST_NVM_VERSION}/install.sh | bash
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        fi
    fi
fi

if command -v nvm &> /dev/null; then
    LATEST_NODE_LTS=$(nvm ls-remote --lts | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' | tail -1)
    
    if ! command -v node &> /dev/null; then
        if ask_confirm "未找到 Node.js。是否使用 NVM 安装最新 LTS 长期支持版？"; then
            nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
        fi
    else
        CURRENT_NODE_VERSION=$(node -v)
        # 【核心防御】只有当抓到了 LTS 版本列表（不为空），且本地版本和线上不一致时，才提示！
        if [ -n "$LATEST_NODE_LTS" ] && [ "$CURRENT_NODE_VERSION" != "$LATEST_NODE_LTS" ]; then
            if ask_confirm "发现 Node.js 新 LTS 版本 ($LATEST_NODE_LTS)，当前 ($CURRENT_NODE_VERSION)。是否平滑更新并迁移全局包？"; then
                nvm install --lts --reinstall-packages-from=current
                nvm use --lts && nvm alias default 'lts/*'
            fi
        fi
    fi
fi
# --- 新增：Claude Code (AI Agent) 检查与安装 ---
if ! command -v claude &> /dev/null; then
    if ask_confirm "未找到 Claude Code (AI 编程助手)。是否立即安装？"; then
        if [ "$MACHINE" == "Mac" ]; then
            # Mac 专属路线：使用 Homebrew (Cask) 安装
            echo -e "${GREEN}正在通过 Homebrew 安装 Claude Code...${NC}"
            brew install --cask claude-code
        elif [ "$MACHINE" == "Linux" ]; then
            # Linux 专属路线：必须依赖 npm 全局安装
            if command -v npm &> /dev/null; then
                echo -e "${GREEN}正在通过 npm 全局安装 Claude Code...${NC}"
                npm install -g @anthropic-ai/claude-code
            else
                echo -e "${RED}安装跳过：Linux 环境下需要 npm，请先确保上面的 Node.js 环境已成功安装。${NC}"
            fi
        fi
        
        # --- 极客专属：自动跳过新手引导 (Onboarding) ---
        CLAUDE_CONFIG="$HOME/.claude.json"
        if [ ! -f "$CLAUDE_CONFIG" ]; then
            # 如果文件不存在，直接生成并注入配置
            echo '{"hasCompletedOnboarding": true}' > "$CLAUDE_CONFIG"
            echo -e "${GREEN}已自动为你生成 ~/.claude.json，完美跳过初次启动引导！${NC}"
        else
            # 如果文件已存在，使用黄色字强提醒
            echo -e "${YELLOW}提示: 你的 ~/.claude.json 文件已存在。${NC}"
            echo -e "${YELLOW}建议手动打开它，并确保里面包含: \"hasCompletedOnboarding\": true${NC}"
        fi
    fi
fi

# ==========================================
# 4. 终端颜值与效率组件 (Starship & Zsh)
# ==========================================
if ! command -v starship &> /dev/null; then
    if ask_confirm "未找到 Starship 主题。是否下载安装？"; then
        curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
    fi
fi

if [ ! -d "$HOME/.zsh/zsh-autosuggestions" ] || [ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ]; then
    if ask_confirm "检测到 Zsh 效率插件未完全同步。是否从 GitHub 克隆下载？"; then
        [ ! -d "$HOME/.zsh/zsh-autosuggestions" ] && git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
        [ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ] && git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting
    fi
fi

# ==========================================
# 5. 收尾：配置文件挂载与极其重要的身份认证
# ==========================================
echo -e "\n${YELLOW}正在挂载 Dotfiles 软链接...${NC}"
ln -sf ~/dotfiles/zsh/zshrc ~/.zshrc
ln -sf ~/dotfiles/starship/starship.toml ~/.config/starship.toml

if [ ! -f ~/.zshrc.local ]; then
    touch ~/.zshrc.local
    echo "# 存放本机特有的环境变量或 Conda 初始化代码" >> ~/.zshrc.local
    echo "# 注意：等号两边绝对不能有空格！" >> ~/.zshrc.local
    echo 'export STARSHIP_ROLE="YourNameHere"' >> ~/.zshrc.local
    echo -e "${GREEN}已为你创建缺省的 ~/.zshrc.local 模板。${NC}"
fi

# --- 醒目的多设备配置提醒 ---
echo -e "\n${RED}======================================================================${NC}"
echo -e "${RED}⚠️  极其重要的最后一步：在.zshrc.local配置你的专属终端身份 ⚠️${NC}"
echo -e "${YELLOW}为了让 Starship 正确显示当前设备的名称，请务必执行以下操作：${NC}"
echo -e "1. 输入命令打开本地配置：${BLUE}nano ~/.zshrc.local${NC}"
echo -e "2. 找到并修改变量为你的设备名 (如 MACyxy, HUSTyxy, JLUyxy)："
echo -e "   ${GREEN}export STARSHIP_ROLE=\"你的专属名字\"${NC}"
echo -e "3. 保存退出后，敲下重启魔法：${BLUE}exec zsh${NC}"
echo -e "${RED}======================================================================\n${NC}"

echo -e "${GREEN}===> [基础配置全部完成] 欢迎来到极客新世界！${NC}"