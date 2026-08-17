#!/usr/bin/env bash
# ============================================================
#  devtools.sh - 开发工具与常用软件
#  功能：常用工具一键安装、Mise多版本管理、NextTrace、Speedtest
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# ---- 常用系统工具 ----
devtools_common() {
    header "安装常用系统工具"
    local tools=(
        curl wget git vim htop jq tree rsync
        dnsutils net-tools iputils-ping traceroute
        unzip zip tar gzip xz-utils
        build-essential gcc g++ make cmake
        python3 python3-pip
        cron sudo psmisc locales
        software-properties-common apt-transport-https ca-certificates gnupg
    )

    # 按包管理器过滤调整包名
    local install_list=()
    for t in "${tools[@]}"; do
        case "$PKG_MANAGER" in
            dnf|yum)
                case "$t" in
                    dnsutils) install_list+=("bind-utils") ;;
                    net-tools) install_list+=("net-tools") ;;
                    build-essential) install_list+=("gcc" "gcc-c++" "make" "cmake") ;;
                    python3-pip) install_list+=("python3-pip") ;;
                    software-properties-common) ;;
                    apt-transport-https) ;;
                    *) install_list+=("$t") ;;
                esac
                ;;
            apk)
                case "$t" in
                    build-essential) install_list+=("build-base") ;;
                    dnsutils) install_list+=("bind-tools") ;;
                    python3-pip) install_list+=("py3-pip") ;;
                    software-properties-common) ;;
                    apt-transport-https) ;;
                    *) install_list+=("$t") ;;
                esac
                ;;
            pacman)
                case "$t" in
                    build-essential) install_list+=("base-devel") ;;
                    dnsutils) install_list+=("bind") ;;
                    python3-pip) install_list+=("python-pip") ;;
                    software-properties-common) ;;
                    apt-transport-https) ;;
                    *) install_list+=("$t") ;;
                esac
                ;;
            *)
                install_list+=("$t")
                ;;
        esac
    done

    echo "  将安装 ${#install_list[@]} 个工具包"
    echo ""
    if confirm "确认安装?" "y"; then
        pkg_install "${install_list[@]}"
        success "常用工具安装完成"
    fi
}

# ---- Mise 多版本管理 ----
devtools_mise() {
    header "安装 Mise (多语言版本管理)"

    if has_cmd mise; then
        success "Mise 已安装: $(mise --version 2>/dev/null | head -1)"
    else
        step "安装 Mise"
        if has_cmd curl; then
            curl https://mise.run | sh
        else
            pkg_install curl
            curl https://mise.run | sh
        fi

        # 添加到 PATH
        local mise_bin="$HOME/.local/bin/mise"
        if [ -f "$mise_bin" ]; then
            # 添加到 .bashrc 和 .zshrc
            for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
                [ -f "$rc" ] || continue
                grep -q 'mise activate' "$rc" || echo 'eval "$(~/.local/bin/mise activate bash)"' >> "$rc"
            done
            export PATH="$HOME/.local/bin:$PATH"
        fi
    fi

    has_cmd mise || { error "Mise 安装失败"; return 1; }

    echo ""
    echo "  Mise 可管理: Python, Node.js, Go, Rust, Java, Ruby, PHP 等"
    echo ""
    if confirm "安装 Python (最新版)?" "y"; then
        mise use --global python@latest
        done_msg "Python: $(mise exec python --version 2>/dev/null)"
    fi
    if confirm "安装 Node.js (LTS)?" "y"; then
        mise use --global node@lts
        done_msg "Node.js: $(mise exec node --version 2>/dev/null)"
    fi
    if confirm "安装 Go (最新版)?" "n"; then
        mise use --global go@latest
        done_msg "Go: $(mise exec go version 2>/dev/null)"
    fi

    success "Mise 配置完成，重新加载 shell 或执行 source ~/.bashrc 生效"
}

# ---- NextTrace ----
devtools_nexttrace() {
    header "安装 NextTrace (可视化路由追踪)"
    if has_cmd nexttrace; then
        success "NextTrace 已安装"
        return 0
    fi

    if has_cmd curl; then
        # 官方一键脚本
        bash <(curl -Ls https://raw.githubusercontent.com/sjlleo/nexttrace/main/nt_install.sh)
    else
        error "需要 curl"
        return 1
    fi

    if has_cmd nexttrace; then
        success "NextTrace 安装完成"
        echo "  用法: nexttrace example.com"
    else
        warn "自动安装可能失败，可手动下载: https://github.com/sjlleo/nexttrace"
    fi
}

# ---- Speedtest CLI ----
devtools_speedtest() {
    header "安装 Speedtest CLI"
    if has_cmd speedtest; then
        success "Speedtest 已安装"
        return 0
    fi

    case "$PKG_MANAGER" in
        apt)
            step "添加 Ookla 官方源"
            pkg_install curl
            curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
            pkg_install speedtest
            ;;
        dnf|yum)
            curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | bash
            pkg_install speedtest
            ;;
        *)
            warn "当前系统暂不支持自动安装，请访问: https://www.speedtest.net/apps/cli"
            return 1
            ;;
    esac

    if has_cmd speedtest; then
        success "Speedtest 安装完成，执行 speedtest 开始测速"
    fi
}

# ---- 检查已安装工具 ----
devtools_check() {
    header "已安装开发工具检查"
    local tools=(curl wget git vim htop jq tree gcc make python3 node npm go docker mise nexttrace speedtest)
    printf "  %-15s %s\n" "工具" "状态"
    printf "  %s\n" "----------------------------------------"
    for t in "${tools[@]}"; do
        if has_cmd "$t"; then
            local ver
            ver="$($t --version 2>/dev/null | head -1 | awk '{print $NF}' | cut -c1-15)"
            printf "  %-15s %s\n" "$t" "✓ ${ver}"
        else
            printf "  %-15s %s\n" "$t" "✗ 未安装"
        fi
    done
}

# ---- 模块菜单 ----
devtools_menu() {
    while true; do
        header "开发工具与常用软件"
        echo "  1) 常用系统工具一键安装"
        echo "  2) Mise 多语言版本管理"
        echo "  3) NextTrace 可视化路由"
        echo "  4) Speedtest CLI 测速"
        echo "  5) Java (sdkman 多版本)"
        echo "  6) Go 语言"
        echo "  7) Rust"
        echo "  8) .NET SDK"
        echo "  9) K3s (轻量K8s)"
        echo " 10) MinIO (对象存储)"
        echo " 11) Node.js nvm"
        echo " 12) Python pyenv"
        echo " 13) Jenkins (CI/CD)"
        echo " 14) ttyd (Web终端)"
        echo " 15) 检查已安装工具"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) devtools_common; pause ;;
            2) devtools_mise; pause ;;
            3) devtools_nexttrace; pause ;;
            4) devtools_speedtest; pause ;;
            5) devtools_java; pause ;;
            6) devtools_go; pause ;;
            7) devtools_rust; pause ;;
            8) devtools_dotnet; pause ;;
            9) devtools_k3s; pause ;;
            10) devtools_minio; pause ;;
            11) devtools_nvm; pause ;;
            12) devtools_pyenv; pause ;;
            13) devtools_jenkins; pause ;;
            14) devtools_ttyd; pause ;;
            15) devtools_check; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    devtools_menu
fi
