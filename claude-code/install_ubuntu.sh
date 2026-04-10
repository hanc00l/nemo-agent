#!/bin/bash
#
# Ubuntu 24.04 LTS PenTester Agent 环境安装脚本
#
# 使用方法:
#   chmod +x install_ubuntu.sh && sudo ./install_ubuntu.sh
#
# 安装的组件:
#   - 系统工具: nmap, whatweb, sqlmap, hydra, hashcat, proxychains4, weevely
#   - 框架: metasploit-framework
#   - 容器: docker, docker-compose
#   - Python 依赖: fastmcp, playwright, libtmux, docker 等
#   - Web UI: Django, markdown, bleach
#

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# 检查 sudo 权限
if ! sudo -v &> /dev/null; then
   log_error "此脚本需要 sudo 权限"
   exit 1
fi

SUDO="sudo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DEBIAN_FRONTEND=noninteractive

log_info "=== Ubuntu 24.04 LTS PenTester Agent 环境安装 ==="
echo ""

# ============================================================================
# 1. 系统更新和基础工具
# ============================================================================
log_step "[1/8] 安装基础工具..."

$SUDO apt-get update -qq
$SUDO apt-get install -y \
    curl wget git vim tmux htop \
    net-tools iputils-ping netcat-openbsd dnsutils \
    unzip jq sqlite3 p7zip-full \
    python3-venv python3-pip python3-full \
    build-essential libssl-dev libffi-dev python3-dev \
    libnss3-tools \
    pipx \
    openjdk-8-jdk

# 安装 Chrome 浏览器
if ! command -v google-chrome &> /dev/null && ! command -v google-chrome-stable &> /dev/null; then
    log_info "安装 Google Chrome..."
    if wget -q "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -O /tmp/google-chrome.deb; then
        $SUDO dpkg -i /tmp/google-chrome.deb 2>/dev/null || \
            ($SUDO apt-get install -y -f && $SUDO dpkg -i /tmp/google-chrome.deb)
        rm -f /tmp/google-chrome.deb
    else
        log_warn "Chrome 下载失败，安装 Chromium..."
        $SUDO apt-get install -y chromium-browser || true
    fi
else
    log_info "Chrome 已存在"
fi

# ============================================================================
# 2. 安装渗透测试工具 (apt)
# ============================================================================
log_step "[2/8] 安装渗透测试工具 (apt)..."

# nmap
if ! command -v nmap &> /dev/null; then
    $SUDO apt-get install -y nmap
    log_info "nmap 已安装"
else
    log_info "nmap 已存在"
fi

# whatweb
if ! command -v whatweb &> /dev/null; then
    $SUDO apt-get install -y whatweb
    log_info "whatweb 已安装"
else
    log_info "whatweb 已存在"
fi

# sqlmap
if ! command -v sqlmap &> /dev/null; then
    $SUDO apt-get install -y sqlmap
    log_info "sqlmap 已安装"
else
    log_info "sqlmap 已存在"
fi

# hydra
if ! command -v hydra &> /dev/null; then
    $SUDO apt-get install -y hydra
    log_info "hydra 已安装"
else
    log_info "hydra 已存在"
fi

# hashcat
if ! command -v hashcat &> /dev/null; then
    $SUDO apt-get install -y hashcat
    log_info "hashcat 已安装"
else
    log_info "hashcat 已存在"
fi

# proxychains4
if ! command -v proxychains4 &> /dev/null; then
    $SUDO apt-get install -y proxychains4
    log_info "proxychains4 已安装"
else
    log_info "proxychains4 已存在"
fi

# weevely
if ! command -v weevely &> /dev/null; then
    $SUDO apt-get install -y weevely
    log_info "weevely 已安装"
else
    log_info "weevely 已存在"
fi

# ============================================================================
# 3. 安装 Metasploit Framework
# ============================================================================
log_step "[3/8] 安装 Metasploit Framework..."

if ! command -v msfconsole &> /dev/null; then
    log_info "安装 metasploit-framework (较大，需要一些时间)..."
    $SUDO snap install metasploit-framework
    log_info "metasploit 已安装"
else
    log_info "metasploit 已存在"
fi

# ============================================================================
# 4. 安装 Docker + Docker Compose
# ============================================================================
log_step "[4/8] 安装 Docker + Docker Compose..."

if ! command -v docker &> /dev/null; then
    log_info "安装 Docker (使用阿里云镜像源)..."

    # 添加 Docker 官方 GPG key (通过阿里云镜像)
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

    # 添加 Docker apt 源 (阿里云镜像)
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

    $SUDO apt-get update -qq
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    $SUDO systemctl enable docker
    $SUDO systemctl start docker
    log_info "Docker 已安装"
else
    log_info "Docker 已存在"
fi

# 配置 Docker Hub 国内镜像加速
if [ ! -f /etc/docker/daemon.json ] || ! grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
    $SUDO mkdir -p /etc/docker
    $SUDO tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
    "registry-mirrors": [
        "https://docker.1ms.run",
        "https://docker.xuanyuan.me"
    ]
}
EOF
    $SUDO systemctl daemon-reload
    $SUDO systemctl restart docker
    log_info "Docker Hub 镜像加速已配置"
fi

# 将当前用户加入 docker 组 (免 sudo 使用 docker)
if ! groups "$(whoami)" 2>/dev/null | grep -q docker; then
    $SUDO usermod -aG docker "$(whoami)"
    log_info "已将当前用户加入 docker 组 (重新登录后生效)"
fi

# ============================================================================
# 5. Python 虚拟环境和依赖
# ============================================================================
log_step "[5/8] 安装 Python 依赖..."

VENV_DIR="$SCRIPT_DIR/.venv"

# pipx
pipx ensurepath 2>/dev/null || true

# 虚拟环境
[ ! -d "$VENV_DIR" ] && python3 -m venv "$VENV_DIR"

source "$VENV_DIR/bin/activate"
pip install --upgrade pip -q

# 核心 MCP + 执行器 + 浏览器 + 终端
pip install -q \
    fastmcp>=0.1.0 \
    jupyter-client>=8.0.0 \
    jupyter-core>=5.0.0 \
    ipykernel>=6.25.0 \
    nbformat>=5.9.0 \
    playwright>=1.40.0 \
    requests>=2.28.0 \
    pydantic>=2.0.0 \
    psutil>=5.9.0 \
    libtmux>=0.12.0 \
    python-dotenv>=1.0.0 \
    docstring-parser>=0.15

# solver / container 管理
pip install -q \
    docker>=7.0.0

# Web UI 依赖
pip install -q \
    django>=5.0 \
    markdown>=3.5 \
    bleach>=6.0

# 测试依赖
pip install -q \
    pytest>=7.0.0 \
    pytest-asyncio>=0.21.0

deactivate

# ============================================================================
# 6. 配置 IPykernel + Playwright
# ============================================================================
log_step "[6/8] 配置 IPykernel + Playwright..."

source "$VENV_DIR/bin/activate"
python -m ipykernel install --user --name python3 2>/dev/null || true

# 配置 Playwright 使用系统 Chrome
CHROME_EXECUTABLE=""
for cmd in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v $cmd &> /dev/null; then
        CHROME_EXECUTABLE=$cmd
        break
    fi
done

if [ -n "$CHROME_EXECUTABLE" ]; then
    export PLAYWRIGHT_BROWSERS_PATH=0
    log_info "Playwright 将使用系统浏览器: $CHROME_EXECUTABLE"
else
    log_warn "未检测到 Chrome，请手动安装"
fi

deactivate

# ============================================================================
# 7. 设置 sudo 免密码
# ============================================================================
log_step "[7/8] 设置 sudo 免密码..."

if [ ! -f /etc/sudoers.d/sudo-nopasswd ]; then
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" | $SUDO tee /etc/sudoers.d/sudo-nopasswd
    $SUDO visudo -c -f /etc/sudoers.d/sudo-nopasswd
    log_info "sudo 免密码已配置"
else
    log_info "sudo 免密码已存在"
fi

# ============================================================================
# 8. 清理
# ============================================================================
log_step "[8/8] 清理临时文件..."

$SUDO apt-get autoremove -y -qq 2>/dev/null || true
$SUDO apt-get clean -qq 2>/dev/null || true

# ============================================================================
# 安装验证
# ============================================================================
echo ""
log_info "=========================================="
log_info " 安装验证"
log_info "=========================================="
echo ""

echo "  基础工具:"
echo -n "    curl:         " && (command -v curl &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    wget:         " && (command -v wget &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    git:          " && (command -v git &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    tmux:         " && (command -v tmux &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    jq:           " && (command -v jq &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    java:         " && (java -version 2>&1 | head -1 || echo "MISSING")
echo -n "    Chrome:       " && ([ -n "$CHROME_EXECUTABLE" ] && echo "$CHROME_EXECUTABLE" || echo "MISSING")
echo ""

echo "  渗透测试工具:"
echo -n "    nmap:         " && (nmap --version 2>/dev/null | head -1 || echo "MISSING")
echo -n "    whatweb:      " && (command -v whatweb &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    sqlmap:       " && (command -v sqlmap &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    hydra:        " && (command -v hydra &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    hashcat:      " && (command -v hashcat &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    proxychains4: " && (command -v proxychains4 &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    weevely:      " && (command -v weevely &>/dev/null && echo "OK" || echo "MISSING")
echo -n "    msfconsole:   " && (command -v msfconsole &>/dev/null && echo "OK" || echo "MISSING")
echo ""

echo "  容器工具:"
echo -n "    docker:       " && (docker --version 2>/dev/null || echo "MISSING")
echo -n "    compose:      " && (docker compose version 2>/dev/null || command -v docker-compose &>/dev/null && echo "OK" || echo "MISSING")
echo ""

source "$VENV_DIR/bin/activate" 2>/dev/null && {
    echo "  Python 依赖:"
    echo -n "    fastmcp:       " && python -c "import fastmcp; print('OK')" 2>/dev/null || echo "MISSING"
    echo -n "    playwright:    " && python -c "from playwright.sync_api import sync_playwright; print('OK')" 2>/dev/null || echo "MISSING"
    echo -n "    libtmux:       " && python -c "import libtmux; print('OK')" 2>/dev/null || echo "MISSING"
    echo -n "    django:        " && python -c "import django; print('OK')" 2>/dev/null || echo "MISSING"
    echo -n "    docker:        " && python -c "import docker; print('OK')" 2>/dev/null || echo "MISSING"
    echo -n "    jupyter-client:" && python -c "import jupyter_client; print('OK')" 2>/dev/null || echo "MISSING"
    echo -n "    ipykernel:     " && python -c "import ipykernel; print('OK')" 2>/dev/null || echo "MISSING"
    echo -n "    pydantic:      " && python -c "import pydantic; print('OK')" 2>/dev/null || echo "MISSING"
    echo -n "    requests:      " && python -c "import requests; print('OK')" 2>/dev/null || echo "MISSING"
    echo -n "    python-dotenv: " && python -c "import dotenv; print('OK')" 2>/dev/null || echo "MISSING"
    echo -n "    pytest:        " && python -c "import pytest; print('OK')" 2>/dev/null || echo "MISSING"
    deactivate
}

echo ""
log_info "安装脚本执行完成!"
