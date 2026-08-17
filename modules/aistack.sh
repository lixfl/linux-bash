#!/usr/bin/env bash
# ============================================================
#  aistack.sh - AI 应用栈一键部署
#  OneAPI / new-api / Ollama / Open WebUI / FastGPT / MaxKB / RAGFlow
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

AISTACK_BASE="${HOME}/ai-stack"

# 通用 Docker 运行辅助
_docker_run() {
    local name="$1" port="$2" image="$3"
    shift 3
    local extra_args="$*"
    docker run -d \
        --name "$name" \
        -p "${port}" \
        -e TZ=Asia/Shanghai \
        --restart=always \
        $extra_args \
        "$image"
}

# ============================================================
#  1. OneAPI
# ============================================================
aistack_oneapi() {
    header "安装 OneAPI"
    echo "  LLM API 中转分发，统一管理多模型 Key，支持渠道负载均衡"
    _ensure_docker || return 1
    mkdir -p "$AISTACK_BASE/oneapi"
    local port
    port="$(ask "Web端口" "3000")"
    step "启动 OneAPI"
    _docker_run oneapi "${port}:3000" justsong/one-api:latest \
        -v "$AISTACK_BASE/oneapi:/data"
    sleep 3
    success "OneAPI 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  默认账号: root / 123456"
}

# ============================================================
#  2. new-api
# ============================================================
aistack_newapi() {
    header "安装 new-api"
    echo "  OneAPI 增强分支，支持更多模型和支付功能"
    _ensure_docker || return 1
    mkdir -p "$AISTACK_BASE/new-api"
    local port
    port="$(ask "Web端口" "3001")"
    step "启动 new-api"
    _docker_run new-api "${port}:3000" calciumion/new-api:latest \
        -v "$AISTACK_BASE/new-api:/data"
    sleep 3
    success "new-api 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  默认账号: root / 123456"
}

# ============================================================
#  3. Ollama
# ============================================================
aistack_ollama() {
    header "安装 Ollama"
    echo "  本地大模型运行时，支持 Llama/Qwen/DeepSeek 等"
    echo ""
    echo "  1) Docker 部署"
    echo "  2) 官方脚本安装(裸机)"
    local method
    method="$(ask "选择方式" "1")"
    if [ "$method" = "1" ]; then
        _ensure_docker || return 1
        mkdir -p "$AISTACK_BASE/ollama"
        local port
        port="$(ask "API端口" "11434")"
        step "启动 Ollama"
        _docker_run ollama "${port}:11434" ollama/ollama:latest \
            -v "$AISTACK_BASE/ollama:/root/.ollama" \
            --gpus=all
        sleep 3
        success "Ollama 部署完成"
        echo "  API: http://localhost:${port}"
        echo "  拉模型: docker exec -it ollama ollama pull qwen2.5:7b"
    else
        step "运行官方安装脚本"
        curl -fsSL https://ollama.com/install.sh | sh
        svc_enable ollama 2>/dev/null
        svc_start ollama 2>/dev/null
        success "Ollama 安装完成: $(ollama --version 2>/dev/null)"
        echo "  拉模型: ollama pull qwen2.5:7b"
        echo "  运行: ollama run qwen2.5:7b"
    fi
}

# ============================================================
#  4. Open WebUI
# ============================================================
aistack_openwebui() {
    header "安装 Open WebUI"
    echo "  自托管 ChatGPT 界面前端，支持 Ollama/OpenAI 兼容接口"
    _ensure_docker || return 1
    mkdir -p "$AISTACK_BASE/open-webui"
    local port
    port="$(ask "Web端口" "8080")"
    local ollama_url
    ollama_url="$(ask "Ollama地址(留空则不连)" "")"
    step "启动 Open WebUI"
    local extra=""
    [ -n "$ollama_url" ] && extra="-e OLLAMA_BASE_URL=$ollama_url"
    _docker_run open-webui "${port}:8080" ghcr.io/open-webui/open-webui:main \
        -v "$AISTACK_BASE/open-webui:/app/backend/data" \
        $extra \
        --add-host=host.docker.internal:host-gateway
    sleep 5
    success "Open WebUI 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  首次注册的账号为管理员"
}

# ============================================================
#  5. FastGPT
# ============================================================
aistack_fastgpt() {
    header "安装 FastGPT"
    echo "  开源知识库问答平台，支持 RAG / 工作流 / API"
    _ensure_docker || return 1
    local dir="$AISTACK_BASE/fastgpt"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "3000")"
    step "生成 Docker Compose"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  fastgpt:
    image: registry.cn-hangzhou.aliyuncs.com/fastgpt/fastgpt:latest
    container_name: fastgpt
    ports:
      - "${port}:3000"
    depends_on:
      - mongo
      - pg
    environment:
      - TZ=Asia/Shanghai
      - rootname=root
      - rootpassword=fastgpt123
      - MONGODB_URI=mongodb://mongo:27017/fastgpt
      - PG_HOST=pg
      - PG_PORT=5432
      - PG_USER=postgres
      - PG_PASSWORD=fastgpt123
      - PG_DATABASE=fastgpt
    restart: always
  mongo:
    image: mongo:5.0
    container_name: fastgpt-mongo
    volumes:
      - ./mongo:/data/db
    restart: always
  pg:
    image: ankane/pgvector:latest
    container_name: fastgpt-pg
    environment:
      - POSTGRES_PASSWORD=fastgpt123
      - POSTGRES_DB=fastgpt
    volumes:
      - ./pg:/var/lib/postgresql/data
    restart: always
EOF
    step "启动 FastGPT (3个容器)"
    docker compose up -d
    sleep 5
    success "FastGPT 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  默认账号: root / fastgpt123"
}

# ============================================================
#  6. MaxKB
# ============================================================
aistack_maxkb() {
    header "安装 MaxKB"
    echo "  开源知识库问答平台，1Panel 团队出品，简单易用"
    _ensure_docker || return 1
    mkdir -p "$AISTACK_BASE/maxkb"
    local port
    port="$(ask "Web端口" "8080")"
    step "启动 MaxKB"
    _docker_run maxkb "${port}:8080" 1panel/maxkb:latest \
        -v "$AISTACK_BASE/maxkb:/var/lib/maxkb"
    sleep 5
    success "MaxKB 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  默认账号: admin / MaxKB@123456"
}

# ============================================================
#  7. RAGFlow
# ============================================================
aistack_ragflow() {
    header "安装 RAGFlow"
    echo "  深度文档理解的 RAG 引擎，支持复杂格式文档解析"
    _ensure_docker || return 1
    local dir="$AISTACK_BASE/ragflow"
    if [ -d "$dir" ]; then
        warn "目录已存在: $dir"
        confirm "删除并重新安装?" "n" || { cd "$dir/docker" 2>/dev/null && docker compose ps; return 0; }
        rm -rf "$dir"
    fi
    step "克隆 RAGFlow 仓库"
    git clone --depth 1 https://github.com/infiniflow/ragflow.git "$dir" || {
        error "克隆失败，请检查网络"
        return 1
    }
    cd "$dir/docker" || return 1
    local port
    port="$(ask "Web端口" "80")"
    sed -i "s/80:80/${port}:80/" docker-compose.yml 2>/dev/null
    step "启动 RAGFlow (约8个容器，首次较慢)"
    docker compose up -d
    sleep 10
    success "RAGFlow 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  默认账号: admin / admin@ragflow.com"
    echo "  管理: cd $dir/docker && docker compose ps"
}

# ============================================================
#  状态查看
# ============================================================
aistack_status() {
    header "AI 应用栈状态"
    echo ""
    if has_cmd docker; then
        section "Docker 容器"
        for c in oneapi new-api ollama open-webui fastgpt fastgpt-mongo fastgpt-pg maxkb ragflow; do
            docker inspect "$c" &>/dev/null && {
                local status
                status="$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)"
                echo "  ✓ $c: $status"
            }
        done
    fi
    echo ""
    section "安装目录"
    [ -d "$AISTACK_BASE" ] && ls -1 "$AISTACK_BASE" | sed 's/^/  • /' || echo "  暂无"
}

# ============================================================
#  菜单
# ============================================================
aistack_menu() {
    while true; do
        header "AI 应用栈一键部署"
        echo "  自动配置 Docker 环境，数据统一存放在 ~/ai-stack/"
        echo ""
        echo "  ── API 中转 ──"
        echo "  1) OneAPI       (LLM API分发, 多渠道管理)"
        echo "  2) new-api      (OneAPI增强分支, 支付/更多模型)"
        echo ""
        echo "  ── 本地模型 ──"
        echo "  3) Ollama       (本地大模型运行时)"
        echo ""
        echo "  ── 前端/知识库 ──"
        echo "  4) Open WebUI   (ChatGPT界面前端)"
        echo "  5) FastGPT      (知识库问答+工作流)"
        echo "  6) MaxKB        (轻量知识库问答)"
        echo "  7) RAGFlow      (深度文档理解RAG)"
        echo ""
        echo "  8) 查看已安装状态"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "选择要部署的应用" "")"
        case "$choice" in
            1) aistack_oneapi; pause ;;
            2) aistack_newapi; pause ;;
            3) aistack_ollama; pause ;;
            4) aistack_openwebui; pause ;;
            5) aistack_fastgpt; pause ;;
            6) aistack_maxkb; pause ;;
            7) aistack_ragflow; pause ;;
            8) aistack_status; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    aistack_menu
fi
