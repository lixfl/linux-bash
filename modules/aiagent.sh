#!/usr/bin/env bash
# ============================================================
#  AI Agent 一键安装模块
#  支持: DeepSeek Harness / Claude Code / OpenAI Codex /
#        PenguinHarness / LangGraph / CrewAI / AutoGen
# ============================================================

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

AGENT_BASE="${HOME}/ai-agents"

# ============================================================
#  通用环境准备
# ============================================================
_ensure_node20() {
    if has_cmd node && [ "$(node -v | sed 's/v//' | cut -d. -f1)" -ge 20 ] 2>/dev/null; then
        success "Node.js $(node -v) 已安装"
        return 0
    fi
    warn "需要 Node.js 20+"
    if has_cmd nvm; then
        step "通过 nvm 安装 Node.js 22"
        source "$HOME/.nvm/nvm.sh" 2>/dev/null
        nvm install 22 && nvm use 22
    else
        step "安装 Node.js 22 (NodeSource)"
        if [ "$PKG_MGR" = "apt" ]; then
            curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
            apt-get install -y nodejs
        elif [ "$PKG_MGR" = "dnf" ] || [ "$PKG_MGR" = "yum" ]; then
            curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
            yum install -y nodejs
        else
            pkg_install nodejs npm
        fi
    fi
    npm config set registry https://registry.npmmirror.com 2>/dev/null
    success "Node.js $(node -v) 安装完成"
}

_ensure_python311() {
    if has_cmd python3 && [ "$(python3 -c 'import sys; print(sys.version_info >= (3,11))' 2>/dev/null)" = "True" ]; then
        success "Python $(python3 --version) 已安装"
        return 0
    fi
    warn "需要 Python 3.11+"
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get update -qq
        apt-get install -y python3.11 python3.11-venv python3-pip 2>/dev/null || {
            warn "仓库无 python3.11，使用 deadsnakes PPA"
            apt-get install -y software-properties-common
            add-apt-repository -y ppa:deadsnakes/ppa
            apt-get update -qq
            apt-get install -y python3.11 python3.11-venv python3.11-dev
        }
    elif [ "$PKG_MGR" = "dnf" ]; then
        dnf install -y python3.11 python3.11-devel
    elif [ "$PKG_MGR" = "pacman" ]; then
        pacman -S --noconfirm python
    else
        pkg_install python3 python3-pip
    fi
    success "Python 安装完成"
}

_ensure_uv() {
    if has_cmd uv; then
        return 0
    fi
    step "安装 uv (Python 包管理器)"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    success "uv 安装完成"
}

# ============================================================
#  1. DeepSeek Harness (dsh)
# ============================================================
aiagent_deepseek() {
    header "安装 DeepSeek Harness"
    echo "  DeepSeek 官方开源 Agent 平台，Web UI + 插件生态"
    echo ""
    _ensure_node20 || return 1
    mkdir -p "$AGENT_BASE/deepseek-harness"

    echo ""
    echo "  1) 全局安装 (npm install -g)"
    echo "  2) npx 快速体验"
    echo "  3) 源码安装 (git clone + pnpm)"
    local method
    method="$(ask "选择方式" "1")"

    if [ "$method" = "1" ]; then
        step "全局安装 @deepseek-ai/dsh"
        npm install -g @deepseek-ai/dsh
        if has_cmd dsh; then
            success "DeepSeek Harness 安装完成: $(dsh --version 2>/dev/null || echo 'installed')"
            echo "  启动 Web UI: dsh web"
            echo "  启动 CLI: dsh"
        else
            error "安装失败，请检查网络"
            return 1
        fi
    elif [ "$method" = "2" ]; then
        success "npx 快速体验命令:"
        echo "  npx @deepseek-ai/dsh web    # Web UI"
        echo "  npx @deepseek-ai/dsh        # CLI"
        echo ""
        warn "首次运行会自动下载依赖"
    else
        step "克隆源码"
        cd "$AGENT_BASE" || return 1
        git clone --depth 1 https://github.com/deepseek-ai/deepseek-harness.git || {
            error "克隆失败"
            return 1
        }
        cd deepseek-harness || return 1
        step "安装依赖 (pnpm)"
        corepack enable 2>/dev/null
        npm install -g pnpm 2>/dev/null
        pnpm install
        pnpm run build
        success "DeepSeek Harness 源码安装完成"
        echo "  目录: $AGENT_BASE/deepseek-harness"
        echo "  启动: pnpm run dev"
    fi
    echo ""
    info "需要配置 DeepSeek API Key: https://platform.deepseek.com"
}

# ============================================================
#  2. Claude Code
# ============================================================
aiagent_claude() {
    header "安装 Claude Code"
    echo "  Anthropic 官方编程 AI Agent CLI，支持 MCP/Skills"
    echo ""
    _ensure_node20 || return 1

    echo ""
    echo "  1) 官方一键脚本 (推荐)"
    echo "  2) npm 全局安装"
    local method
    method="$(ask "选择方式" "1")"

    if [ "$method" = "1" ]; then
        step "运行官方安装脚本"
        curl -fsSL https://claude.ai/install.sh | bash
    else
        step "npm 全局安装 @anthropic-ai/claude-code"
        npm install -g @anthropic-ai/claude-code --foreground-scripts
    fi

    if has_cmd claude; then
        success "Claude Code 安装完成: $(claude --version 2>/dev/null || echo 'installed')"
        echo "  启动: claude"
        echo "  登录: claude login"
    else
        warn "命令未找到，可能需要重新打开终端或添加 PATH"
        echo "  手动安装: npm install -g @anthropic-ai/claude-code"
    fi
    echo ""
    info "需要 Anthropic API Key 或订阅 Claude Pro/Max"
}

# ============================================================
#  3. OpenAI Codex
# ============================================================
aiagent_codex() {
    header "安装 OpenAI Codex CLI"
    echo "  OpenAI 官方编程 Agent CLI，支持 Skills/MCP"
    echo ""
    _ensure_node20 || return 1

    echo ""
    echo "  1) 官方一键脚本 (推荐)"
    echo "  2) npm 全局安装"
    local method
    method="$(ask "选择方式" "1")"

    if [ "$method" = "1" ]; then
        step "运行官方安装脚本"
        curl -fsSL https://chatgpt.com/codex/install.sh | sh
    else
        step "npm 全局安装 @openai/codex"
        npm install -g @openai/codex
    fi

    if has_cmd codex; then
        success "OpenAI Codex 安装完成: $(codex --version 2>/dev/null || echo 'installed')"
        echo "  启动: codex"
        echo "  登录: codex login"
    else
        warn "命令未找到，可能需要重新打开终端"
        echo "  手动安装: npm install -g @openai/codex"
    fi
    echo ""
    info "需要 OpenAI API Key 或 ChatGPT Plus/Pro 订阅"
}

# ============================================================
#  4. PenguinHarness
# ============================================================
aiagent_penguin() {
    header "安装 PenguinHarness"
    echo "  Agent 构建 Agent 的自进化引擎，Codex 本地平替"
    echo "  仓库: https://github.com/Prism-Shadow/penguin-harness"
    echo ""
    _ensure_node20 || return 1

    echo ""
    echo "  1) 官方一键脚本 (推荐)"
    echo "  2) npm 全局安装"
    local method
    method="$(ask "选择方式" "1")"

    if [ "$method" = "1" ]; then
        step "运行官方安装脚本"
        curl -fsSL https://penguin.ooo/install.sh | sh
    else
        step "npm 全局安装 @prismshadow/penguin-cli"
        npm install -g @prismshadow/penguin-cli
    fi

    if has_cmd penguin; then
        success "PenguinHarness 安装完成"
        echo "  启动: penguin"
    else
        warn "命令未找到，请检查安装输出"
        echo "  手动: curl -fsSL https://penguin.ooo/install.sh | sh"
    fi
}

# ============================================================
#  5. LangGraph
# ============================================================
aiagent_langgraph() {
    header "安装 LangGraph"
    echo "  LangChain 生态的有状态图 Agent 框架，支持循环决策"
    echo ""
    _ensure_python311 || return 1
    _ensure_uv

    mkdir -p "$AGENT_BASE/langgraph-project"
    cd "$AGENT_BASE/langgraph-project" || return 1

    echo ""
    echo "  1) uv 虚拟环境安装 (推荐)"
    echo "  2) pip 全局安装"
    local method
    method="$(ask "选择方式" "1")"

    if [ "$method" = "1" ]; then
        step "创建虚拟环境并安装"
        uv venv
        uv pip install langgraph langchain langchain-openai langchain-community
        success "LangGraph 安装完成"
        echo "  激活: source $AGENT_BASE/langgraph-project/.venv/bin/activate"
    else
        step "pip 安装"
        pip3 install --user langgraph langchain langchain-openai langchain-community
        success "LangGraph 安装完成"
    fi

    # 生成示例代码
    cat > example.py <<'EOF'
from langgraph.graph import StateGraph, END
from typing import TypedDict

class State(TypedDict):
    input: str
    output: str

def node1(state):
    return {"output": f"处理: {state['input']}"}

builder = StateGraph(State)
builder.add_node("process", node1)
builder.set_entry_point("process")
builder.add_edge("process", END)
graph = builder.compile()
print(graph.invoke({"input": "你好 LangGraph"}))
EOF
    echo "  示例: $AGENT_BASE/langgraph-project/example.py"
    info "需要配置 LLM API Key (OpenAI/Anthropic/DeepSeek 等)"
}

# ============================================================
#  6. CrewAI
# ============================================================
aiagent_crewai() {
    header "安装 CrewAI"
    echo "  角色扮演多 Agent 协作框架，概念清晰易上手"
    echo ""
    _ensure_python311 || return 1
    _ensure_uv

    mkdir -p "$AGENT_BASE/crewai-project"
    cd "$AGENT_BASE/crewai-project" || return 1

    echo ""
    echo "  1) uv 虚拟环境安装 (推荐)"
    echo "  2) pip 全局安装"
    local method
    method="$(ask "选择方式" "1")"

    if [ "$method" = "1" ]; then
        step "创建虚拟环境并安装"
        uv venv
        uv pip install crewai 'crewai[tools]'
        success "CrewAI 安装完成"
        echo "  激活: source $AGENT_BASE/crewai-project/.venv/bin/activate"
    else
        step "pip 安装"
        pip3 install --user crewai 'crewai[tools]'
        success "CrewAI 安装完成"
    fi

    cat > example.py <<'EOF'
from crewai import Agent, Task, Crew

researcher = Agent(
    role="研究员",
    goal="深入研究指定主题",
    backstory="你是一位经验丰富的研究专家",
    verbose=True
)
task = Task(
    description="研究 AI Agent 的最新进展",
    expected_output="一份简要报告",
    agent=researcher
)
crew = Crew(agents=[researcher], tasks=[task])
result = crew.kickoff()
print(result)
EOF
    echo "  示例: $AGENT_BASE/crewai-project/example.py"
    info "需要配置 LLM API Key (设置 OPENAI_API_KEY 或使用其他模型)"
}

# ============================================================
#  7. AutoGen
# ============================================================
aiagent_autogen() {
    header "安装 AutoGen"
    echo "  微软多 Agent 对话框架，支持代码执行和人类介入"
    echo ""
    _ensure_python311 || return 1
    _ensure_uv

    mkdir -p "$AGENT_BASE/autogen-project"
    cd "$AGENT_BASE/autogen-project" || return 1

    echo ""
    echo "  1) uv 虚拟环境安装 (推荐)"
    echo "  2) pip 全局安装"
    local method
    method="$(ask "选择方式" "1")"

    if [ "$method" = "1" ]; then
        step "创建虚拟环境并安装"
        uv venv
        uv pip install "autogen-agentchat" "autogen-ext[openai]"
        success "AutoGen 安装完成"
        echo "  激活: source $AGENT_BASE/autogen-project/.venv/bin/activate"
    else
        step "pip 安装"
        pip3 install --user "autogen-agentchat" "autogen-ext[openai]"
        success "AutoGen 安装完成"
    fi

    cat > example.py <<'EOF'
import os
from autogen import AssistantAgent, UserProxyAgent

config_list = [{"model": "gpt-4o", "api_key": os.getenv("OPENAI_API_KEY")}]

assistant = AssistantAgent("assistant", llm_config={"config_list": config_list})
user_proxy = UserProxyAgent("user_proxy", code_execution_config={"work_dir": "coding"})

user_proxy.initiate_chat(assistant, message="写一个 Python 脚本打印斐波那契数列前10项")
EOF
    echo "  示例: $AGENT_BASE/autogen-project/example.py"
    info "需要配置 OpenAI API Key (或兼容接口如 DeepSeek)"
    warn "AutoGen 官方仓库已进入维护模式，新项目可考虑 LangGraph/CrewAI"
}

# ============================================================
#  状态查看
# ============================================================
aiagent_status() {
    header "已安装 AI Agent 状态"
    echo ""
    section "CLI 工具"
    for cmd in dsh claude codex penguin; do
        if has_cmd "$cmd"; then
            echo "  ✓ $cmd: $($cmd --version 2>/dev/null | head -1)"
        else
            echo "  ✗ $cmd: 未安装"
        fi
    done
    echo ""
    section "Python 框架"
    for pkg in langgraph crewai autogen; do
        if python3 -c "import $pkg" 2>/dev/null; then
            echo "  ✓ $pkg: $(python3 -c "import $pkg; print($pkg.__version__)" 2>/dev/null || echo 'installed')"
        else
            echo "  ✗ $pkg: 未安装"
        fi
    done
    echo ""
    section "项目目录"
    if [ -d "$AGENT_BASE" ]; then
        ls -1 "$AGENT_BASE" 2>/dev/null | while read -r d; do
            echo "  • $d"
        done
    else
        echo "  暂无项目目录"
    fi
}

# ============================================================
#  模块菜单
# ============================================================
aiagent_menu() {
    while true; do
        header "AI Agent 一键安装"
        echo "  自动配置运行环境 (Node.js 20+ / Python 3.11+ / uv)"
        echo ""
        echo "  ── CLI 编程助手 ──"
        echo "  1) DeepSeek Harness (DeepSeek官方, Web+CLI)"
        echo "  2) Claude Code      (Anthropic, MCP/Skills)"
        echo "  3) OpenAI Codex     (OpenAI, Skills/MCP)"
        echo "  4) PenguinHarness   (自进化Agent, Codex平替)"
        echo ""
        echo "  ── Python Agent 框架 ──"
        echo "  5) LangGraph        (有状态图, LangChain生态)"
        echo "  6) CrewAI           (角色扮演多Agent协作)"
        echo "  7) AutoGen          (微软多Agent对话框架)"
        echo ""
        echo "  8) 查看已安装状态"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "选择要安装的 Agent" "")"
        case "$choice" in
            1) aiagent_deepseek; pause ;;
            2) aiagent_claude; pause ;;
            3) aiagent_codex; pause ;;
            4) aiagent_penguin; pause ;;
            5) aiagent_langgraph; pause ;;
            6) aiagent_crewai; pause ;;
            7) aiagent_autogen; pause ;;
            8) aiagent_status; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    aiagent_menu
fi
