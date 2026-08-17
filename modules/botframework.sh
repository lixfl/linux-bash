#!/usr/bin/env bash
# ============================================================
#  botframework.sh - 主流机器人框架一键安装
#  支持：AstrBot / NoneBot2 / Koishi / Mirai / LangBot / qq-ai-bot
#  自动配置所需运行环境（Python/Node.js/Java/Docker）
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

BOT_BASE="$HOME/bots"

# ============================================================
#  通用环境准备
# ============================================================

# 确保 Python 3.10+
_ensure_python() {
    if has_cmd python3 && python3 -c 'import sys; exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
        done_msg "Python: $(python3 --version)"
        return 0
    fi
    step "安装 Python 3.11+"
    case "$PKG_MANAGER" in
        apt)    pkg_install python3 python3-pip python3-venv python3-dev ;;
        dnf|yum) pkg_install python3 python3-pip ;;
        apk)    pkg_install python3 py3-pip ;;
        pacman) pkg_install python python-pip ;;
    esac
    has_cmd python3 && done_msg "Python: $(python3 --version)" || error "Python 安装失败"
}

# 确保 uv (Python 包管理器)
_ensure_uv() {
    if has_cmd uv; then
        done_msg "uv: $(uv --version)"
        return 0
    fi
    step "安装 uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    has_cmd uv && done_msg "uv 安装完成" || warn "uv 安装可能失败，请手动执行: curl -LsSf https://astral.sh/uv/install.sh | sh"
}

# 确保 Node.js 18+
_ensure_node() {
    if has_cmd node && node -e "process.exit(process.versions.node.split('.')[0] >= 18 ? 0 : 1)" 2>/dev/null; then
        done_msg "Node.js: $(node -v)"
        return 0
    fi
    step "安装 Node.js 20 (NodeSource)"
    if has_cmd nvm; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install 20 && nvm use 20 && nvm alias default 20
    else
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null
        pkg_install nodejs
    fi
    npm config set registry https://registry.npmmirror.com
    has_cmd node && done_msg "Node.js: $(node -v)" || error "Node.js 安装失败"
}

# 确保 Java 17+
_ensure_java() {
    if has_cmd java && java -version 2>&1 | grep -qE 'version "?(17|21|25)'; then
        done_msg "Java: $(java -version 2>&1 | head -1)"
        return 0
    fi
    step "安装 OpenJDK 17"
    case "$PKG_MANAGER" in
        apt)    pkg_install openjdk-17-jre-headless ;;
        dnf|yum) pkg_install java-17-openjdk-headless ;;
        apk)    pkg_install openjdk17-jre ;;
        pacman) pkg_install jre17-openjdk ;;
    esac
    has_cmd java && done_msg "Java: $(java -version 2>&1 | head -1)" || error "Java 安装失败"
}

# 确保 Docker
_ensure_docker() {
    if has_cmd docker && docker info &>/dev/null; then
        done_msg "Docker: $(docker -v)"
        return 0
    fi
    warn "未检测到 Docker，部分框架需要 Docker"
    echo "  请在主菜单选择 [Docker管理] → 安装 Docker"
    return 1
}

# ============================================================
#  1. AstrBot
# ============================================================
botframework_astrbot() {
    header "安装 AstrBot"
    echo "  多平台 LLM 聊天机器人框架，支持 QQ/微信/Telegram/Discord 等"
    echo "  官方推荐 Docker Compose 部署"
    echo ""
    echo "  1) Docker Compose 部署 (推荐)"
    echo "  2) uv 原生部署"
    local method
    method="$(ask "选择部署方式" "1")"

    mkdir -p "$BOT_BASE"
    cd "$BOT_BASE" || return 1

    if [ "$method" = "1" ]; then
        _ensure_docker || return 1
        local dir="$BOT_BASE/AstrBot"
        if [ -d "$dir" ]; then
            warn "目录已存在: $dir"
            confirm "删除并重新安装?" "n" || return 0
            rm -rf "$dir"
        fi
        step "克隆 AstrBot 仓库"
        git clone --depth 1 https://github.com/AstrBotDevs/AstrBot "$dir" || {
            error "克隆失败"
            return 1
        }
        cd "$dir" || return 1
        step "启动 Docker Compose"
        docker compose up -d
        sleep 3
        success "AstrBot 部署完成"
        echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):6180"
        echo "  管理: docker compose ps / logs / down"
    else
        _ensure_python
        _ensure_uv
        step "通过 uv 安装 AstrBot"
        uv tool install astrbot --python 3.12
        export PATH="$HOME/.local/bin:$PATH"
        if [ ! -d "$BOT_BASE/astrbot-data" ]; then
            mkdir -p "$BOT_BASE/astrbot-data"
        fi
        cd "$BOT_BASE/astrbot-data" || return 1
        step "初始化 AstrBot"
        astrbot init 2>/dev/null || warn "init 可能已执行过，跳过"
        success "AstrBot 安装完成"
        echo "  启动: cd $BOT_BASE/astrbot-data && astrbot run"
        echo "  访问: http://localhost:6180"
    fi
}

# ============================================================
#  2. NoneBot2
# ============================================================
botframework_nonebot() {
    header "安装 NoneBot2"
    echo "  异步 Python 机器人框架，插件生态丰富"
    echo ""
    _ensure_python
    _ensure_uv

    step "安装 nb-cli (通过 pipx/uv)"
    if has_cmd pipx; then
        pipx install nb-cli 2>/dev/null || uv tool install nb-cli
    else
        uv tool install nb-cli
    fi
    export PATH="$HOME/.local/bin:$PATH"

    if ! has_cmd nb; then
        warn "nb 命令未找到，尝试 pip 安装"
        pip3 install nb-cli 2>/dev/null
    fi

    mkdir -p "$BOT_BASE"
    cd "$BOT_BASE" || return 1

    echo ""
    echo "  将运行 nb-cli 交互式创建项目"
    echo "  提示：项目名建议 nonebot-project，驱动器选 FastAPI"
    echo ""
    if confirm "开始创建项目?" "y"; then
        nb create
        success "NoneBot2 项目创建完成"
        echo ""
        echo "  启动方式:"
        echo "    cd $BOT_BASE/<项目名>"
        echo "    nb run  (或 python bot.py)"
    fi
}

# ============================================================
#  3. Koishi
# ============================================================
botframework_koishi() {
    header "安装 Koishi"
    echo "  跨平台聊天机器人框架，Node.js 开发，Web 控制台"
    echo ""
    echo "  1) Docker 部署 (推荐，开箱即用)"
    echo "  2) npm 原生部署"
    local method
    method="$(ask "选择部署方式" "1")"

    if [ "$method" = "1" ]; then
        _ensure_docker || return 1
        local port
        port="$(ask "Web控制台端口" "5140")"
        step "启动 Koishi Docker 容器"
        docker run -d \
            --name koishi \
            -p "${port}:5140" \
            -e TZ=Asia/Shanghai \
            -v "$BOT_BASE/koishi:/koishi" \
            --restart=always \
            koishijs/koishi
        sleep 3
        success "Koishi 部署完成"
        echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    else
        _ensure_node
        mkdir -p "$BOT_BASE/koishi"
        cd "$BOT_BASE/koishi" || return 1
        step "通过 npm 创建 Koishi 项目"
        npm init koishi@latest
        success "Koishi 项目创建完成"
        echo "  启动: cd $BOT_BASE/koishi && npm start"
    fi
}

# ============================================================
#  4. Mirai
# ============================================================
botframework_mirai() {
    header "安装 Mirai (MCL)"
    echo "  QQ 机器人框架，Java/Kotlin 开发，插件生态成熟"
    echo ""
    _ensure_java

    local dir="$BOT_BASE/mirai"
    mkdir -p "$dir"
    cd "$dir" || return 1

    if [ -f "$dir/mcl" ]; then
        warn "MCL 已安装"
        confirm "重新安装?" "n" || return 0
        rm -rf "$dir"/*
    fi

    step "下载 mcl-installer"
    local installer_url
    installer_url="https://github.com/iTXTech/mcl-installer/releases/latest/download/mcl-installer-linux-x64"
    curl -fL "$installer_url" -o mcl-installer 2>/dev/null || {
        warn "GitHub 下载失败，尝试镜像..."
        curl -fL "https://ghproxy.net/$installer_url" -o mcl-installer 2>/dev/null || {
            error "下载失败，请手动下载: https://github.com/iTXTech/mcl-installer/releases"
            return 1
        }
    }
    chmod +x mcl-installer

    step "运行安装器（自动下载 MCL + Java）"
    ./mcl-installer <<EOF
y
y
y
EOF

    if [ -f "$dir/mcl" ]; then
        chmod +x mcl
        success "Mirai (MCL) 安装完成"
        echo ""
        echo "  启动: cd $dir && ./mcl"
        echo "  登录: 在控制台输入 /login <QQ号> <密码>"
        echo "  推荐安装 mirai-api-http 插件以供其他框架调用"
    else
        error "安装可能失败，请检查 $dir 目录"
    fi
}

# ============================================================
#  5. LangBot
# ============================================================
botframework_langbot() {
    header "安装 LangBot"
    echo "  大模型即时通信机器人平台，支持 QQ/微信/Telegram/飞书/钉钉/Slack"
    echo ""
    echo "  1) uvx 一键启动 (最简单)"
    echo "  2) Docker Compose 部署 (推荐生产)"
    local method
    method="$(ask "选择部署方式" "2")"

    if [ "$method" = "1" ]; then
        _ensure_python
        _ensure_uv
        step "通过 uvx 启动 LangBot"
        export PATH="$HOME/.local/bin:$PATH"
        success "LangBot 启动命令已准备"
        echo "  运行: uvx langbot"
        echo "  访问: http://localhost:5300"
        echo "  (首次运行会自动下载依赖)"
    else
        _ensure_docker || return 1
        local dir="$BOT_BASE/LangBot"
        if [ -d "$dir" ]; then
            warn "目录已存在: $dir"
            confirm "删除并重新安装?" "n" || return 0
            rm -rf "$dir"
        fi
        step "克隆 LangBot 仓库"
        git clone --depth 1 https://github.com/langbot-app/LangBot "$dir" || {
            git clone --depth 1 https://github.com/RockChinQ/LangBot "$dir" || {
                error "克隆失败"
                return 1
            }
        }
        cd "$dir/docker" || return 1
        step "启动 Docker Compose (含运行时沙盒)"
        docker compose --profile all up -d
        sleep 3
        success "LangBot 部署完成"
        echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):5300"
        echo "  管理: cd $dir/docker && docker compose ps / logs"
    fi
}

# ============================================================
#  6. qq-ai-bot
# ============================================================
botframework_qqai() {
    header "安装 qq-ai-bot"
    echo "  轻量 QQ AI 机器人，支持多种 LLM"
    echo ""
    _ensure_docker || {
        echo "  也可选择源码部署，需要 Python 3.10+"
        if ! confirm "继续用源码部署?" "n"; then return 1; fi
        _ensure_python
        local dir="$BOT_BASE/qq-ai-bot"
        git clone --depth 1 https://github.com/happysnaker/qq-ai-bot "$dir"
        cd "$dir" || return 1
        pip3 install -r requirements.txt
        success "qq-ai-bot 源码部署完成"
        echo "  配置: 编辑 config.yaml"
        echo "  启动: python3 main.py"
        return 0
    }

    local port
    port="$(ask "Web端口" "8080")"
    step "拉取并启动 qq-ai-bot Docker"
    docker run -d \
        --name qq-ai-bot \
        -p "${port}:8080" \
        -e TZ=Asia/Shanghai \
        -v "$BOT_BASE/qq-ai-bot:/app/data" \
        --restart=always \
        ghcr.io/happysnaker/qq-ai-bot:latest
    sleep 3
    success "qq-ai-bot 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
}


# ============================================================
#  7. Yunzai
# ============================================================
botframework_yunzai() {
    header "安装 Yunzai 机器人"
    echo "  TRSS Yunzai + NapCat(QQ) + Valkey/Redis 全自动部署"
    echo "  自动识别系统/架构，安装 Node.js/Redis/依赖"
    echo ""
    local mod_dir
    mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$mod_dir/yunzai.sh"
    yunzai_install_all
}
# ============================================================
#  状态查看
# ============================================================
botframework_status() {
    header "已安装机器人框架状态"
    echo ""
    local found=0

    # Docker 容器
    if has_cmd docker; then
        section "Docker 容器"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | \
            grep -iE "astrbot|koishi|langbot|qq-ai|nonebot|mirai|NAMES" | sed 's/^/  /'
        found=1
    fi

    # 目录检查
    section "安装目录"
    for name in AstrBot nonebot-project koishi mirai LangBot qq-ai-bot; do
        if [ -d "$BOT_BASE/$name" ]; then
            echo "  ✓ $BOT_BASE/$name"
            found=1
        fi
    done

    # 命令检查
    section "可用命令"
    for cmd in astrbot nb koishi uv; do
        has_cmd "$cmd" && echo "  ✓ $cmd: $($cmd --version 2>/dev/null | head -1)"
    done

    [ "$found" -eq 0 ] && echo "  暂无已安装的机器人框架"
}


# ============================================================
#  7. OpenClaw
# ============================================================
botframework_openclaw() {
    header "安装 OpenClaw"
    echo "  轻量 AI Agent 平台，支持多 IM 接入，Python 开发"
    echo ""
    _ensure_docker || return 1
    mkdir -p "$BOT_BASE/openclaw"

    local port
    port="$(ask "Web端口" "8080")"
    step "拉取并启动 OpenClaw"
    docker run -d \
        --name openclaw \
        -p "${port}:8080" \
        -e TZ=Asia/Shanghai \
        -v "$BOT_BASE/openclaw/data:/root/.openclaw" \
        -v "$BOT_BASE/openclaw/workspace:/workspace" \
        --restart=unless-stopped \
        --privileged \
        openclaw/openclaw:latest
    sleep 3
    success "OpenClaw 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  数据: $BOT_BASE/openclaw/"
}

# ============================================================
#  8. LobeChat
# ============================================================
botframework_lobechat() {
    header "安装 LobeChat"
    echo "  开源 AI 聊天工作台，支持多模型、知识库、插件"
    echo ""
    _ensure_docker || return 1
    mkdir -p "$BOT_BASE/lobechat"

    local port
    port="$(ask "Web端口" "3210")"
    echo ""
    echo "  1) 轻量版 (无数据库，本地存储)"
    echo "  2) 数据库版 (PostgreSQL，支持多用户/知识库)"
    local mode
    mode="$(ask "选择版本" "1")"

    if [ "$mode" = "1" ]; then
        step "启动 LobeChat 轻量版"
        docker run -d \
            --name lobe-chat \
            -p "${port}:3210" \
            -e TZ=Asia/Shanghai \
            -v "$BOT_BASE/lobechat/data:/app/data" \
            --restart=always \
            lobehub/lobe-chat:latest
    else
        cd "$BOT_BASE/lobechat" || return 1
        step "生成 Docker Compose (数据库版)"
        local secret
        secret="$(openssl rand -hex 32 2>/dev/null || echo 'lobechat-secret-key-change-me')"
        cat > docker-compose.yml <<EOF
version: '3.8'
services:
  lobe-chat:
    image: lobehub/lobe-chat-database:latest
    container_name: lobe-chat
    ports:
      - "${port}:3210"
    environment:
      - DATABASE_URL=postgresql://lobe:lobe123456@postgres:5432/lobechat
      - KEY_VAULTS_SECRET=${secret}
      - TZ=Asia/Shanghai
    depends_on:
      postgres:
        condition: service_healthy
    restart: always
  postgres:
    image: pgvector/pgvector:pg16
    container_name: lobe-postgres
    environment:
      - POSTGRES_DB=lobechat
      - POSTGRES_USER=lobe
      - POSTGRES_PASSWORD=lobe123456
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U lobe"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: always
EOF
        step "启动服务"
        docker compose up -d
    fi
    sleep 3
    success "LobeChat 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
}

# ============================================================
#  9. Dify
# ============================================================
botframework_dify() {
    header "安装 Dify"
    echo "  开源 LLM 应用开发平台，支持可视化编排、RAG、Agent"
    echo ""
    _ensure_docker || return 1

    local dir="$BOT_BASE/dify"
    if [ -d "$dir" ]; then
        warn "目录已存在: $dir"
        if confirm "删除并重新安装?" "n"; then
            rm -rf "$dir"
        else
            cd "$dir/docker" 2>/dev/null && docker compose ps
            return 0
        fi
    fi

    step "克隆 Dify 仓库"
    git clone --depth 1 https://github.com/langgenius/dify.git "$dir" || {
        error "克隆失败，请检查网络"
        return 1
    }
    cd "$dir/docker" || return 1

    step "复制环境配置"
    cp .env.example .env 2>/dev/null

    local port
    port="$(ask "Web端口" "80")"
    sed -i "s/^EXPOSE_NGINX_PORT=.*/EXPOSE_NGINX_PORT=${port}/" .env 2>/dev/null

    step "启动 Dify (约 10 个容器，首次拉取较慢)"
    docker compose up -d
    sleep 5
    success "Dify 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  默认账号: admin@dify.ltd / dify123456"
    echo "  管理: cd $dir/docker && docker compose ps / logs"
}

# ============================================================
#  10. n8n
# ============================================================
botframework_n8n() {
    header "安装 n8n"
    echo "  开源工作流自动化平台，可视化连接各种服务和 API"
    echo ""
    _ensure_docker || return 1
    mkdir -p "$BOT_BASE/n8n"

    local port
    port="$(ask "Web端口" "5678")"
    step "启动 n8n"
    docker run -d \
        --name n8n \
        -p "${port}:5678" \
        -e TZ=Asia/Shanghai \
        -e GENERIC_TIMEZONE=Asia/Shanghai \
        -v "$BOT_BASE/n8n/data:/home/node/.n8n" \
        --restart=always \
        docker.n8n.io/n8nio/n8n
    sleep 3
    success "n8n 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  数据: $BOT_BASE/n8n/data"
}

# ============================================================
#  11. Lagrange.Core (OneBot 协议端)
# ============================================================
botframework_lagrange() {
    header "安装 Lagrange.Core"
    echo "  NTQQ 协议端，提供 OneBot V11 API，C#/.NET 开发"
    echo ""
    echo "  1) Docker 部署 (推荐)"
    echo "  2) 二进制自包含部署"
    local method
    method="$(ask "选择部署方式" "1")"

    mkdir -p "$BOT_BASE/lagrange/data"
    cd "$BOT_BASE/lagrange" || return 1

    if [ "$method" = "1" ]; then
        _ensure_docker || return 1
        local port
        port="$(ask "OneBot API 端口" "8081")"
        step "启动 Lagrange.OneBot"
        docker run -d \
            --name lagrange \
            -p "${port}:8081" \
            -e TZ=Asia/Shanghai \
            -v "$BOT_BASE/lagrange/data:/app/data" \
            --restart=unless-stopped \
            ghcr.io/lagrangedev/lagrange.onebot:edge
        sleep 3
        success "Lagrange.Core 部署完成"
        echo "  配置文件: $BOT_BASE/lagrange/data/appsettings.json"
        echo "  首次启动后扫码登录"
        echo "  日志: docker logs -f lagrange"
    else
        local arch_map
        case "$ARCH" in
            x86_64)  arch_map="linux-x64" ;;
            aarch64) arch_map="linux-arm64" ;;
            *)       error "不支持的架构: $ARCH"; return 1 ;;
        esac
        step "下载 Lagrange.OneBot ($arch_map)"
        local dl_url
        dl_url="https://github.com/LagrangeDev/Lagrange.Core/releases/download/nightly/Lagrange.OneBot_${arch_map}_net9.0_SelfContained.tar.gz"
        curl -fL "$dl_url" -o lagrange.tar.gz 2>/dev/null || {
            warn "GitHub 下载失败，尝试镜像..."
            curl -fL "https://ghproxy.net/$dl_url" -o lagrange.tar.gz 2>/dev/null || {
                error "下载失败"
                return 1
            }
        }
        tar -xzf lagrange.tar.gz -C "$BOT_BASE/lagrange"
        rm -f lagrange.tar.gz
        chmod +x "$BOT_BASE/lagrange/Lagrange.OneBot"
        success "Lagrange.Core 二进制部署完成"
        echo "  启动: cd $BOT_BASE/lagrange && ./Lagrange.OneBot"
        echo "  首次启动生成配置文件后扫码登录"
    fi
}

# ============================================================
#  12. Wechaty
# ============================================================
botframework_wechaty() {
    header "安装 Wechaty"
    echo "  微信机器人 SDK，Node.js 开发，支持个人微信"
    echo ""
    echo "  1) Docker 快速体验"
    echo "  2) npm 项目初始化"
    local method
    method="$(ask "选择方式" "1")"

    if [ "$method" = "1" ]; then
        _ensure_docker || return 1
        step "拉取 Wechaty 镜像"
        docker pull wechaty/wechaty:latest 2>/dev/null
        success "Wechaty Docker 镜像已拉取"
        echo ""
        echo "  使用示例:"
        echo "    docker run -ti --rm -e WECHATY_TOKEN=your_token \\"
        echo "      -v \$(pwd):/bot wechaty/wechaty your_bot.js"
        echo ""
        warn "Wechaty 需要 Token (puppet service)，个人微信需申请"
        echo "  详见: https://wechaty.js.org"
    else
        _ensure_node
        mkdir -p "$BOT_BASE/wechaty-bot"
        cd "$BOT_BASE/wechaty-bot" || return 1
        step "初始化 Wechaty 项目"
        npm init -y
        npm install wechaty
        cat > bot.js <<'EOF'
const { Wechaty } = require('wechaty');
const bot = new Wechaty();
bot.on('scan', (qrcode, status) => console.log('Scan QR Code to login:', qrcode))
   .on('login', user => console.log('User', user, 'logined'))
   .on('message', message => console.log('Message:', message))
   .start();
EOF
        success "Wechaty 项目初始化完成"
        echo "  启动: cd $BOT_BASE/wechaty-bot && node bot.js"
    fi
}

# ============================================================
#  13. nanobot
# ============================================================
botframework_nanobot() {
    header "安装 nanobot"
    echo "  超轻量个人 AI 助理 (香港大学开源)，Python 开发，<100MB 内存"
    echo ""
    _ensure_python
    _ensure_uv

    echo ""
    echo "  1) 一键脚本安装 (推荐)"
    echo "  2) uv/pip 安装"
    local method
    method="$(ask "选择方式" "1")"

    if [ "$method" = "1" ]; then
        step "运行 nanobot 一键安装脚本"
        curl -fsSL https://raw.githubusercontent.com/HKUDS/nanobot/main/scripts/install.sh | sh
    else
        step "通过 uv 安装 nanobot-ai"
        uv tool install nanobot-ai
        export PATH="$HOME/.local/bin:$PATH"
    fi

    if has_cmd nanobot; then
        success "nanobot 安装完成"
        echo "  启动: nanobot webui"
        echo "  配置: ~/.nanobot/config.json"
        echo "  支持 QQ / Telegram / Discord 等渠道"
    else
        warn "安装可能未完成，请手动执行:"
        echo "  curl -fsSL https://raw.githubusercontent.com/HKUDS/nanobot/main/scripts/install.sh | sh"
    fi
}

# ============================================================
#  模块菜单
# ============================================================
botframework_menu() {
    while true; do
        header "机器人/AI 框架一键安装"
        echo "  自动配置所需运行环境 (Python/Node.js/Java/Docker/.NET)"
        echo ""
        echo "  ── 机器人框架 ──"
        echo "  1) AstrBot      (LLM多平台, Python, Docker/uv)"
        echo "  2) NoneBot2     (异步Python, 插件生态丰富)"
        echo "  3) Koishi       (跨平台, Node.js, Web控制台)"
        echo "  4) Mirai (MCL)  (QQ, Java, 插件成熟)"
        echo "  5) LangBot      (大模型多平台, Python, Docker)"
        echo "  6) qq-ai-bot    (轻量QQ AI, Docker/Python)"
        echo "  7) Yunzai       (QQ机器人, Node.js, 全自动部署)"
        echo "  8) 早柚核心     (gsuid_core, 游戏机器人, Python/uv)"
        echo "  9) Wechaty      (微信, Node.js, Docker/npm)"
        echo " 10) nanobot      (超轻量AI助理, Python, <100MB)"
        echo ""
        echo "  ── AI 平台 / 工作流 ──"
        echo " 11) LobeChat     (AI聊天工作台, Docker)"
        echo " 12) OpenClaw     (AI Agent平台, Docker)"
        echo " 13) Dify         (LLM应用开发, Docker Compose)"
        echo " 14) n8n          (工作流自动化, Docker)"
        echo ""
        echo "  ── 协议端 ──"
        echo " 15) Lagrange.Core (NTQQ OneBot协议端, Docker/二进制)"
        echo ""
        echo " 16) 查看已安装状态"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "选择要安装的框架" "")"
        case "$choice" in
            1)  botframework_astrbot; pause ;;
            2)  botframework_nonebot; pause ;;
            3)  botframework_koishi; pause ;;
            4)  botframework_mirai; pause ;;
            5)  botframework_langbot; pause ;;
            6)  botframework_qqai; pause ;;
            7)  botframework_yunzai; pause ;;
            8)  botframework_sayu; pause ;;
            9)  botframework_wechaty; pause ;;
            10) botframework_nanobot; pause ;;
            11) botframework_lobechat; pause ;;
            12) botframework_openclaw; pause ;;
            13) botframework_dify; pause ;;
            14) botframework_n8n; pause ;;
            15) botframework_lagrange; pause ;;
            16) botframework_status; pause ;;
            0)  break ;;
            *)  warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    botframework_menu
fi
