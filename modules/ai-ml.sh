#!/usr/bin/env bash
# ============================================================
#  ai-ml.sh - AI / ML 工具
#  Stable Diffusion / ComfyUI / Whisper / TTS / 翻译 / AnythingLLM / LibreChat / vLLM / MLflow / Label Studio / JupyterHub
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
AIML_BASE="${HOME}/ai-ml"

# ============================================================
#  Stable Diffusion WebUI
# ============================================================
aiml_sd() {
    header "安装 Stable Diffusion WebUI"
    echo "  AUTOMATIC1111 WebUI，AI 画图（需GPU）"
    _ensure_docker || return 1
    local dir="$AIML_BASE/sd"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "7860")"
    step "启动 Stable Diffusion WebUI"
    docker run -d --name sd-webui -p "${port}:7860" \
        -e TZ=Asia/Shanghai \
        -v "$dir:/stable-diffusion-webui" \
        --gpus all 2>/dev/null \
        --restart=always siutin/stable-diffusion-webui-docker:latest
    sleep 10
    success "Stable Diffusion WebUI 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    warn "首次启动需下载模型，可能较慢；建议GPU环境"
}

# ============================================================
#  ComfyUI
# ============================================================
aiml_comfyui() {
    header "安装 ComfyUI"
    echo "  节点式 AI 画图工作流"
    _ensure_docker || return 1
    local dir="$AIML_BASE/comfyui"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8188")"
    docker run -d --name comfyui -p "${port}:8188" \
        -e TZ=Asia/Shanghai \
        -v "$dir:/comfyui" \
        --gpus all 2>/dev/null \
        --restart=always yanwk/comfyui-boot:latest
    sleep 8
    success "ComfyUI 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  Whisper
# ============================================================
aiml_whisper() {
    header "安装 Whisper"
    echo "  OpenAI 语音识别（本地离线）"
    if has_cmd whisper; then
        success "Whisper 已安装: $(whisper --version 2>/dev/null)"
        return 0
    fi
    step "安装 Whisper"
    pip3 install -U openai-whisper 2>/dev/null || {
        pkg_install python3-pip ffmpeg
        pip3 install -U openai-whisper
    }
    success "Whisper 安装完成"
    echo "  转录: whisper audio.mp3 --model medium"
    echo "  模型: tiny/base/small/medium/large"
}

# ============================================================
#  Piper TTS
# ============================================================
aiml_tts() {
    header "安装 Piper TTS"
    echo "  本地神经语音合成，速度快质量高"
    if has_cmd piper; then
        success "Piper 已安装"
        return 0
    fi
    local arch_map
    case "$ARCH" in x86_64) arch_map="amd64" ;; aarch64) arch_map="arm64" ;; *) error "不支持"; return 1 ;; esac
    step "下载 Piper"
    local ver
    ver="$(curl -s https://api.github.com/repos/rhasspy/piper/releases/latest | grep tag_name | cut -d'"' -f4)"
    [ -z "$ver" ] && ver="v1.2.0"
    curl -fsSL "https://github.com/rhasspy/piper/releases/download/${ver}/piper_${arch_map}.tar.gz" | tar -xz -C /usr/local/bin
    success "Piper 安装完成"
    echo "  使用: echo '你好' | piper --model zh_CN-huayan-medium.onnx --output_file out.wav"
    echo "  模型下载: https://huggingface.co/rhasspy/piper-voices"
}

# ============================================================
#  LibreTranslate
# ============================================================
aiml_translate() {
    header "安装 LibreTranslate"
    echo "  离线机器翻译（支持中英等多语言）"
    _ensure_docker || return 1
    local port
    port="$(ask "Web端口" "5000")"
    docker run -d --name libretranslate -p "${port}:5000" \
        -e TZ=Asia/Shanghai \
        -v "$AIML_BASE/libretranslate:/home/libretranslate/.local" \
        --restart=always libretranslate/libretranslate
    sleep 15
    success "LibreTranslate 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  API: http://localhost:${port}/translate"
}

# ============================================================
#  AnythingLLM
# ============================================================
aiml_anythingllm() {
    header "安装 AnythingLLM"
    echo "  本地 RAG 知识库（桌面+服务端）"
    _ensure_docker || return 1
    local dir="$AIML_BASE/anythingllm"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "3001")"
    step "下载 compose"
    curl -fsSL https://raw.githubusercontent.com/Mintplex-Labs/anything-llm/master/docker/docker-compose.yml -o docker-compose.yml 2>/dev/null
    curl -fsSL https://raw.githubusercontent.com/Mintplex-Labs/anything-llm/master/docker/.env.example -o .env 2>/dev/null
    [ -f .env ] && sed -i "s/^PORT=.*/PORT=${port}/" .env
    docker compose up -d 2>/dev/null || warn "启动失败，请检查配置"
    sleep 10
    success "AnythingLLM 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  LibreChat
# ============================================================
aiml_librechat() {
    header "安装 LibreChat"
    echo "  多模型 ChatGPT 前端"
    _ensure_docker || return 1
    local dir="$AIML_BASE/librechat"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "3080")"
    step "克隆配置"
    git clone --depth 1 https://github.com/danny-avila/LibreChat.git . 2>/dev/null || true
    [ -f .env.example ] && cp .env.example .env 2>/dev/null
    [ -f docker-compose.yml ] && sed -i "s/3080:3080/${port}:3080/" docker-compose.yml 2>/dev/null
    docker compose up -d 2>/dev/null || warn "启动失败，LibreChat 依赖较多"
    sleep 15
    success "LibreChat 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  vLLM
# ============================================================
aiml_vllm() {
    header "安装 vLLM"
    echo "  大模型高吞吐推理服务（需GPU）"
    if has_cmd vllm; then
        success "vLLM 已安装"
        return 0
    fi
    step "安装 vLLM"
    pip3 install vllm 2>/dev/null || warn "pip 安装失败，建议使用 Docker"
    if _ensure_docker 2>/dev/null; then
        local port model
        port="$(ask "API端口" "8000")"
        model="$(ask "模型名(如 Qwen/Qwen2-7B-Instruct)" "Qwen/Qwen2-7B-Instruct")"
        step "启动 vLLM OpenAI 兼容 API"
        docker run -d --name vllm -p "${port}:8000" \
            --gpus all 2>/dev/null \
            --restart=always vllm/vllm-openai:latest \
            --model "$model"
        success "vLLM 部署完成: http://localhost:${port}/v1"
        echo "  兼容 OpenAI API，base_url=http://localhost:${port}/v1"
    fi
}

# ============================================================
#  MLflow
# ============================================================
aiml_mlflow() {
    header "安装 MLflow"
    echo "  ML 实验跟踪/模型管理"
    _ensure_docker || return 1
    local port
    port="$(ask "Web端口" "5000")"
    docker run -d --name mlflow -p "${port}:5000" \
        -e TZ=Asia/Shanghai \
        -v "$AIML_BASE/mlflow:/mlflow" \
        --restart=always ghcr.io/mlflow/mlflow:latest mlflow server --host 0.0.0.0 --port 5000
    sleep 5
    success "MLflow 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  Label Studio
# ============================================================
aiml_labelstudio() {
    header "安装 Label Studio"
    echo "  数据标注平台（图像/文本/音频/视频）"
    _ensure_docker || return 1
    local dir="$AIML_BASE/labelstudio"
    mkdir -p "$dir"
    local port
    port="$(ask "Web端口" "8080")"
    docker run -d --name label-studio -p "${port}:8080" \
        -e TZ=Asia/Shanghai \
        -v "$dir:/label-studio/data" \
        --restart=always heartexlabs/label-studio:latest
    sleep 8
    success "Label Studio 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  JupyterHub
# ============================================================
aiml_jupyterhub() {
    header "安装 JupyterHub"
    echo "  多用户 Jupyter 笔记本平台"
    _ensure_docker || return 1
    local port
    port="$(ask "Web端口" "8000")"
    docker run -d --name jupyterhub -p "${port}:8000" \
        -e TZ=Asia/Shanghai \
        -v "$AIML_BASE/jupyterhub:/home" \
        --restart=always jupyterhub/jupyterhub
    sleep 8
    success "JupyterHub 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  菜单
# ============================================================
aiml_menu() {
    while true; do
        header "AI / ML 工具"
        echo "  ── 图像生成 ──"
        echo "  1) Stable Diffusion WebUI"
        echo "  2) ComfyUI (节点式)"
        echo "  ── 语音/翻译 ──"
        echo "  3) Whisper (语音识别)"
        echo "  4) Piper TTS (语音合成)"
        echo "  5) LibreTranslate (离线翻译)"
        echo "  ── LLM 应用 ──"
        echo "  6) AnythingLLM (RAG知识库)"
        echo "  7) LibreChat (多模型前端)"
        echo "  8) vLLM (大模型推理服务)"
        echo "  ── ML 平台 ──"
        echo "  9) MLflow (实验跟踪)"
        echo " 10) Label Studio (数据标注)"
        echo " 11) JupyterHub (多用户笔记本)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) aiml_sd; pause ;;
            2) aiml_comfyui; pause ;;
            3) aiml_whisper; pause ;;
            4) aiml_tts; pause ;;
            5) aiml_translate; pause ;;
            6) aiml_anythingllm; pause ;;
            7) aiml_librechat; pause ;;
            8) aiml_vllm; pause ;;
            9) aiml_mlflow; pause ;;
            10) aiml_labelstudio; pause ;;
            11) aiml_jupyterhub; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    aiml_menu
fi
