k#!/bin/bash

# --- 颜色与基础设置 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}===> [自动化环境初始化] 启动中...${NC}"

# 创建必要的本地目录
mkdir -p ~/.local/bin ~/.zsh ~/.config

# --- 权限检查函数 ---
can_sudo() {
    # 检查当前用户是否有 sudo 权限且无需交互
    if sudo -n true 2>/dev/null; then return 0; else return 1; fi
}

# --- 1. 确保 Git 存在 ---
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}检测到 Git 缺失...${NC}"
    if can_sudo; then
        sudo apt-get update && sudo apt-get install -y git
    else
        echo -e "${RED}错误：无 sudo 权限且未发现 Git，请联系管理员预装基础工具。${NC}"
        exit 1
    fi
fi

# --- 2. 确保 Git LFS 存在 ---
if ! command -v git-lfs &> /dev/null; then
    echo -e "${YELLOW}正在安装 Git LFS...${NC}"
    if can_sudo; then
        sudo apt-get update && sudo apt-get install -y git-lfs
    else
        # 非 sudo 方案：下载二进制包
        LFS_URL="https://github.com/git-lfs/git-lfs/releases/download/v3.4.0/git-lfs-linux-amd64-v3.4.0.tar.gz"
        curl -L $LFS_URL | tar xz -C /tmp
        mv /tmp/git-lfs-3.4.0/git-lfs ~/.local/bin/
    fi
    git lfs install
    echo -e "${GREEN}Git LFS 安装成功。${NC}"
fi

# --- 3. 确保 Miniconda 存在 ---
if ! command -v conda &> /dev/null; then
    echo -e "${YELLOW}正在安装 Miniconda...${NC}"
    CONDA_INSTALLER="/tmp/miniconda_install.sh"
    curl -L https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o $CONDA_INSTALLER
    # -b: 批量模式 (不提问), -p: 安装路径
    bash $CONDA_INSTALLER -b -p $HOME/miniconda3
    rm $CONDA_INSTALLER
    echo -e "${GREEN}Miniconda 已安装至 ~/miniconda3${NC}"
    echo -e "${YELLOW}请稍后手动运行 'conda init zsh' 或检查 .zshrc.local${NC}"
fi

# --- 4. 安装 Starship ---
if ! command -v starship &> /dev/null; then
    echo -e "${YELLOW}正在安装 Starship...${NC}"
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
fi

# --- 5. 下载 Zsh 插件 ---
echo -e "${YELLOW}同步 Zsh 插件...${NC}"
[ ! -d "$HOME/.zsh/zsh-autosuggestions" ] && git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
[ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ] && git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting

# --- 6. 建立软链接 ---
echo -e "${YELLOW}配置文件挂载...${NC}"
ln -sf ~/dotfiles/zsh/zshrc ~/.zshrc
ln -sf ~/dotfiles/starship/starship.toml ~/.config/starship.toml

# --- 7. 初始化本地私人配置 ---
if [ ! -f ~/.zshrc.local ]; then
    touch ~/.zshrc.local
    echo "# 存放本机特有的环境变量或 Conda 初始化代码" >> ~/.zshrc.local
fi

echo -e "${GREEN}===> [配置完成] 请执行 'exec zsh' 进入新世界！${NC}"
