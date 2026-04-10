#!/bin/bash
# ============================================
# Claude Code 中国大陆安装脚本
# 适配网络环境，使用国内镜像源
# ============================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ============================================
# 配置项
# ============================================
NODE_VERSION="${NODE_VERSION:-20}"
NPM_REGISTRY="https://registry.npmmirror.com"
NODE_MIRROR="https://npmmirror.com/mirrors/node"
NVM_MIRROR="https://npmmirror.com/mirrors/nvm"

# ============================================
# 检测系统环境
# ============================================
detect_os() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
    else
        error "不支持的系统，请手动安装 Node.js 后运行: npm install -g @anthropic-ai/claude-code"
    fi
    info "检测到包管理器: $PKG_MANAGER"
}

# ============================================
# 安装基础依赖
# ============================================
install_deps() {
    info "安装基础依赖..."
    case $PKG_MANAGER in
        apt)
            sudo apt-get update -qq
            sudo apt-get install -y -qq curl wget git ca-certificates gnupg >/dev/null
            ;;
        yum)
            sudo yum install -y -q curl wget git ca-certificates gnupg2 >/dev/null
            ;;
        dnf)
            sudo dnf install -y -q curl wget git ca-certificates gnupg2 >/dev/null
            ;;
        pacman)
            sudo pacman -S --noconfirm --quiet curl wget git ca-certificates gnupg >/dev/null
            ;;
    esac
    info "基础依赖安装完成"
}

# ============================================
# 安装 Node.js（直接下载 npmmirror 二进制包）
# ============================================
install_node() {
    if command -v node &>/dev/null; then
        local version
        version=$(node -v 2>/dev/null)
        local major
        major=$(echo "$version" | sed 's/^v//' | cut -d. -f1)
        if [ "$major" -ge 18 ]; then
            info "已安装 Node.js $version，跳过安装"
            return 0
        else
            warn "Node.js $version 版本过低（需要 >= 18），将重新安装"
        fi
    fi

    # 获取最新的 LTS 版本号
    info "从 npmmirror 获取 Node.js ${NODE_VERSION} 最新版本..."
    local version_list
    version_list=$(curl -fsSL --connect-timeout 15 "${NODE_MIRROR}/index.json" 2>/dev/null) || {
        error "无法连接 npmmirror 镜像，请检查网络"
    }

    # 提取指定大版本的最新版本号（如 20.x.y）
    local node_version
    node_version=$(echo "$version_list" | grep -oP "\"version\":\s*\"v${NODE_VERSION}\.\d+\.\d+\"" | head -1 | grep -oP 'v[0-9.]+' | head -1)
    if [ -z "$node_version" ]; then
        error "未找到 Node.js ${NODE_VERSION} 的版本"
    fi
    info "将安装 Node.js ${node_version}"

    # 确定架构
    local arch
    case "$(uname -m)" in
        x86_64)  arch="x64" ;;
        aarch64) arch="arm64" ;;
        *)       error "不支持的架构: $(uname -m)" ;;
    esac

    local pkg_name="node-${node_version}-linux-${arch}.tar.xz"
    local download_url="${NODE_MIRROR}/${node_version}/${pkg_name}"
    local install_dir="/usr/local/lib/nodejs/${node_version}"

    info "下载 ${pkg_name}..."
    wget -q --show-progress -O "/tmp/${pkg_name}" "$download_url" || {
        error "Node.js 下载失败，请检查网络连接"
    }

    info "解压并安装到 ${install_dir}..."
    sudo mkdir -p "$install_dir"
    sudo tar -xJf "/tmp/${pkg_name}" -C "$install_dir" --strip-components=1
    rm -f "/tmp/${pkg_name}"

    # 创建符号链接到 /usr/local/bin
    sudo ln -sf "${install_dir}/bin/node" /usr/local/bin/node
    sudo ln -sf "${install_dir}/bin/npm" /usr/local/bin/npm
    sudo ln -sf "${install_dir}/bin/npx" /usr/local/bin/npx

    # 确保 npm 全局 bin 目录在 PATH 中
    local npm_global_bin="${install_dir}/bin"
    local profile_file="${HOME}/.bashrc"
    if ! grep -q "$npm_global_bin" "$profile_file" 2>/dev/null; then
        echo "" >> "$profile_file"
        echo "# Node.js global bin" >> "$profile_file"
        echo "export PATH=\"${npm_global_bin}:\$PATH\"" >> "$profile_file"
        info "已将 Node.js bin 目录写入 $profile_file"
    fi
    export PATH="${npm_global_bin}:$PATH"

    # 验证
    if command -v node &>/dev/null; then
        info "Node.js $(node -v) 安装完成"
    else
        error "Node.js 安装失败"
    fi
}

# ============================================
# 配置 npm 使用国内镜像
# ============================================
config_npm_mirror() {
    info "配置 npm 使用国内镜像源: $NPM_REGISTRY"
    npm config set registry "$NPM_REGISTRY"

    # 同时设置二进制镜像（加速 node-gyp 等编译依赖）
    # npm config set sass_binary_site "https://npmmirror.com/mirrors/node-sass"
    # npm config set electron_mirror "https://npmmirror.com/mirrors/electron/"
    # npm config set puppeteer_download_host "https://npmmirror.com/mirrors"
    # npm config set chromedriver_cdnurl "https://npmmirror.com/mirrors/chromedriver"
    # npm config set operadriver_cdnurl "https://npmmirror.com/mirrors/operadriver"
    # npm config set phantomjs_cdnurl "https://npmmirror.com/mirrors/phantomjs/"
    # npm config set python_mirror "https://npmmirror.com/mirrors/python/"
    # npm config set sqlite3_binary_site "https://npmmirror.com/mirrors/sqlite3"

    info "npm 镜像配置完成"
}

# ============================================
# 安装 Claude Code
# ============================================
install_claude_code() {
    info "正在通过国内镜像安装 Claude Code..."

    # 使用国内镜像安装（需要 sudo，因为 Node.js 安装在系统目录）
    sudo npm install -g @anthropic-ai/claude-code --registry="$NPM_REGISTRY"

    if command -v claude &>/dev/null; then
        info "Claude Code 安装成功！"
        claude --version 2>/dev/null || true
    else
        # 可能是 PATH 问题
        warn "claude 命令未在 PATH 中找到，尝试修复..."
        local npm_bin
        npm_bin=$(npm bin -g 2>/dev/null || echo "/usr/local/bin")
        export PATH="$npm_bin:$PATH"
        if command -v claude &>/dev/null; then
            info "Claude Code 安装成功！"
        else
            error "安装可能失败，请尝试手动运行: npm install -g @anthropic-ai/claude-code"
        fi
    fi
}

# ============================================
# 安装后说明
# ============================================
post_install() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}   Claude Code 安装完成！${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    echo -e "使用方法："
    echo -e "  ${GREEN}claude${NC}              # 交互式启动"
    echo -e "  ${GREEN}claude \"query\"${NC}      # 带问题启动"
    echo -e "  ${GREEN}claude -p \"query\"${NC}   # 管道模式（非交互）"
    echo ""
    echo -e "首次使用需要配置 API Key："
    echo -e "  1. 运行 ${GREEN}claude${NC} 启动"
    echo -e "  2. 选择登录方式（API Key / OAuth）"
    echo -e "  3. 如使用 API Key，在 ${YELLOW}https://console.anthropic.com/${NC} 获取"
    echo ""
    echo -e "中国大陆用户注意："
    echo -e "  - API 调用可能需要代理，设置方法："
    echo -e "    ${YELLOW}export HTTPS_PROXY=http://your-proxy:port${NC}"
    echo -e "  - 或使用支持 Anthropic API 的转发服务"
    echo ""
    echo -e "如需更新 Claude Code："
    echo -e "  ${GREEN}npm update -g @anthropic-ai/claude-code --registry=$NPM_REGISTRY${NC}"
    echo ""

    # 检查当前 shell 是否需要重新加载
    if ! command -v claude &>/dev/null; then
        echo -e "${YELLOW}请运行以下命令刷新环境变量：${NC}"
        echo -e "  ${GREEN}source ~/.bashrc${NC}  (bash 用户)"
        echo -e "  ${GREEN}source ~/.zshrc${NC}   (zsh 用户)"
        echo ""
    fi
}

# ============================================
# 主流程
# ============================================
main() {
    echo -e "${CYAN}Claude Code 中国大陆安装脚本${NC}"
    echo -e "${CYAN}=============================${NC}"
    echo ""

    detect_os
    install_deps
    install_node

    config_npm_mirror
    install_claude_code
    post_install
}

main "$@"
