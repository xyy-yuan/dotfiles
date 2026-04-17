#!/bin/bash

# --- 颜色定义 (让输出不枯燥) ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}===> [施工开始] 正在为您的一站式终端进行环境初始化...${NC}"

# 1. 基础文件夹建设
mkdir -p ~/.config
mkdir -p ~/.zsh
mkdir -p ~/.local/bin

# 2. 安装 Starship (本地安装，无需 sudo)
if ! command -v starship &> /dev/null; then
    echo -e "${YELLOW}正在安装 Starship 主题引擎...${NC}"
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
else
    echo -e "${GREEN}Starship 已存在，跳过安装。${NC}"
fi

# 3. 下载 Zsh 插件
echo -e "${YELLOW}正在同步 Zsh 必备插件...${NC}"
if [ ! -d "$HOME/.zsh/zsh-autosuggestions" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
fi
if [ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting
fi

# 4. 牵红线 (建立软链接)
echo -e "${YELLOW}正在建立配置文件关联...${NC}"
# -f 代表强制覆盖，这样即使原本有旧文件也会被踢掉
ln -sf ~/dotfiles/zsh/zshrc ~/.zshrc
ln -sf ~/dotfiles/starship/starship.toml ~/.config/starship.toml

# 5. 初始化本地私人储物柜 (关键！)
# 如果不存在 .zshrc.local，就建一个空的，防止 zshrc 报错
if [ ! -f ~/.zshrc.local ]; then
    echo -e "${YELLOW}创建空的本地私人配置表 (~/.zshrc.local)...${NC}"
    touch ~/.zshrc.local
    echo "# 以后请把 Conda 初始化等特定机器的路径写在这里" >> ~/.zshrc.local
fi

# 6. 最后的叮嘱
echo -e "${GREEN}===> [施工完毕] 环境已就绪！${NC}"
echo -e "${BLUE}后续动作建议：${NC}"
echo -e "1. 如果当前不是 Zsh，请运行: ${YELLOW}chsh -s \$(which zsh)${NC}"
echo -e "2. 别忘了把这台机器的 Conda 块移入 ${YELLOW}~/.zshrc.local${NC}"
echo -e "3. 执行 ${YELLOW}exec zsh${NC} 立即体验新环境！"
