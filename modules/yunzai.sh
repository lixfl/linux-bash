#!/usr/bin/env bash
# ============================================================
#  yunzai.sh - Yunzai 机器人 + NapCat 一键部署
#  功能：Node环境、系统依赖、Valkey、Yunzai、NapCat安装与管理
#  说明：换源/Docker安装请使用主菜单对应模块，本模块不重复
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# ---- 配置 ----
NVM_VERSION="v0.40.3"
NODE_VERSION="24"
YUNZAI_REPO="https://git.trss.me/Yunzai"
YUNZAI_DIR="$HOME/Yunzai"
NAPCAT_DIR="$HOME/NapCat"
QQ_VERSION="3.2.30-50828"
QQ_BUILD="727ce4e5"
NAPCAT_CLI_URL="https://raw.githubusercontent.com/NapNeko/NapCat-TUI-CLI/main/script/install-cli.sh"

# ============================================================
#  环境检查
# ============================================================
yunzai_check_env() {
    header "环境检查"
    local issues=0

    # 架构检查
    local arch_map
    case "$ARCH" in
        x86_64)  arch_map="amd64" ;;
        aarch64) arch_map="arm64" ;;
        *)       arch_map="unknown" ;;
    esac
    echo "  系统架构: $ARCH ($arch_map)"
    if [ "$arch_map" = "unknown" ]; then
        error "不支持的架构: $ARCH"
        issues=$((issues+1))
    fi

    # 内存检查
    echo "  内存: ${TOTAL_MEM_GB} GB"
    if [ "$TOTAL_MEM_GB" -lt 1 ]; then
        warn "内存不足 1GB，可能影响运行"
    fi

    # 磁盘检查
    local free_gb
    free_gb="$(disk_free_gb "$HOME")"
    echo "  $HOME 剩余空间: ${free_gb} GB"
    if [ "$(echo "$free_gb < 5" | bc -l 2>/dev/null)" = "1" ]; then
        warn "磁盘空间不足 5GB"
    fi

    # 必要命令
    for cmd in curl wget git unzip jq; do
        if ! has_cmd "$cmd"; then
            warn "缺少命令: $cmd (将在依赖安装步骤中安装)"
        fi
    done

    # Docker 提示
    if ! has_cmd docker; then
        echo ""
        warn "未检测到 Docker，部分 Yunzai 插件可能需要"
        echo "  可在主菜单选择 [Docker管理] 安装"
    fi

    echo ""
    if [ "$issues" -eq 0 ]; then
        success "环境检查通过"
    else
        error "存在 $issues 个问题"
    fi
}

# ============================================================
#  安装系统依赖
# ============================================================
yunzai_install_deps() {
    require_root || return 1
    header "安装系统依赖"

    local deps_common=(curl wget git unzip jq ffmpeg screen xvfb xauth procps cpio)
    local deps_chrome=(libnss3 libgbm1 libglib2.0-0 libatk1.0-0 libatspi2.0-0 libgtk-3-0 libasound2)
    local deps_fonts=(fonts-noto-cjk fonts-noto-color-emoji)

    # 按包管理器映射
    local to_install=()
    case "$PKG_MANAGER" in
        apt)
            to_install=("${deps_common[@]}" "${deps_chrome[@]}" "${deps_fonts[@]}" lsb-release ca-certificates)
            ;;
        dnf|yum)
            to_install=(curl wget git unzip jq ffmpeg screen xorg-x11-server-Xvfb xauth procps-ng cpio
                nss gb glib2 atk at-spi2-atk gtk3 alsa-lib
                google-noto-sans-cjk-fonts google-noto-color-emoji-fonts redhat-lsb-core)
            ;;
        apk)
            to_install=(curl wget git unzip jq ffmpeg screen xvfb xauth procps cpio
                nss glib gtk+3.0 atk at-spi2-core alsa-lib
                noto-fonts-cjk noto-fonts-emoji ttf-freefont)
            ;;
        pacman)
            to_install=(curl wget git unzip jq ffmpeg screen xorg-server-xvfb xauth procps-ng cpio
                nss glib2 gtk3 atk at-spi2-atk alsa-lib
                noto-fonts-cjk noto-fonts-emoji)
            ;;
        *)
            error "不支持的包管理器"
            return 1
            ;;
    esac

    echo "  将安装 ${#to_install[@]} 个依赖包"
    echo ""
    pkg_install "${to_install[@]}"

    # 刷新字体缓存
    has_cmd fc-cache && fc-cache -fv >/dev/null 2>&1

    success "系统依赖安装完成"
}

# ============================================================
#  安装 Node.js 环境 (NVM + Node + PNPM)
# ============================================================
yunzai_install_node() {
    header "安装 Node.js 环境"

    export NVM_DIR="$HOME/.nvm"

    # 安装 NVM
    if [ ! -d "$NVM_DIR" ]; then
        step "安装 NVM $NVM_VERSION"
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
        if [ ! -d "$NVM_DIR" ]; then
            error "NVM 安装失败"
            return 1
        fi
    else
        done_msg "NVM 已安装"
    fi

    # 加载 NVM
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # 安装 Node.js
    if ! command -v node &>/dev/null || [ -z "$(node -v 2>/dev/null | grep -E "v${NODE_VERSION}|v2[0-9]")" ]; then
        step "安装 Node.js $NODE_VERSION"
        nvm install "$NODE_VERSION"
        nvm use "$NODE_VERSION"
        nvm alias default "$NODE_VERSION"
    else
        done_msg "Node.js 已安装: $(node -v)"
    fi

    # 配置 NPM 国内源 + 安装 PNPM
    step "配置 NPM 淘宝源并安装 PNPM"
    npm config set registry https://registry.npmmirror.com
    npm i -g pnpm
    pnpm config set registry https://registry.npmmirror.com

    echo ""
    echo "  Node: $(node -v)"
    echo "  NPM:  $(npm -v)"
    echo "  PNPM: $(pnpm -v)"
    success "Node.js 环境配置完成"

    # 写入 shell 配置
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] || continue
        grep -q 'NVM_DIR' "$rc" || cat >> "$rc" <<'EOF'

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOF
    done
}

# ============================================================
#  安装 Valkey / Redis
# ============================================================
yunzai_install_valkey() {
    require_root || return 1
    header "安装 Valkey (Redis 替代品)"

    # 检查是否已安装
    if has_cmd valkey-cli || has_cmd redis-cli; then
        local existing
        existing="$(has_cmd valkey-cli && echo valkey-cli || echo redis-cli)"
        if "$existing" ping 2>/dev/null | grep -q PONG; then
            success "Valkey/Redis 已在运行"
            return 0
        fi
    fi

    # 尝试安装 valkey，失败则安装 redis
    local installed=0
    case "$PKG_MANAGER" in
        apt)
            if apt-cache search valkey 2>/dev/null | grep -q '^valkey '; then
                pkg_install valkey && installed=1
            fi
            ;;
        dnf|yum)
            pkg_install valkey 2>/dev/null && installed=1
            ;;
        apk)
            apk search valkey 2>/dev/null | grep -q '^valkey' && pkg_install valkey && installed=1
            ;;
        pacman)
            pacman -Si valkey 2>/dev/null | grep -q Name && pkg_install valkey && installed=1
            ;;
    esac

    if [ "$installed" -eq 0 ]; then
        warn "valkey 不可用，改用 redis"
        case "$PKG_MANAGER" in
            apt)    pkg_install redis-server ;;
            dnf|yum) pkg_install redis ;;
            apk)    pkg_install redis ;;
            pacman) pkg_install redis ;;
        esac
    fi

    # 启动服务
    local svc_name="valkey-server"
    has_cmd valkey-server || svc_name="redis"
    svc_enable "$svc_name" 2>/dev/null
    svc_start "$svc_name" 2>/dev/null
    sleep 1

    local cli
    cli="$(has_cmd valkey-cli && echo valkey-cli || echo redis-cli)"
    if "$cli" ping 2>/dev/null | grep -q PONG; then
        success "Valkey/Redis 安装成功并运行中"
    else
        warn "安装完成但服务未启动，请手动检查: systemctl status $svc_name"
    fi
}

# ============================================================
#  安装 Yunzai
# ============================================================
yunzai_install_yunzai() {
    header "安装 Yunzai 机器人"

    # 检查 Node
    if ! has_cmd node; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    fi
    has_cmd node || { error "未找到 Node.js，请先安装 Node 环境"; return 1; }
    has_cmd pnpm || { error "未找到 pnpm，请先安装 Node 环境"; return 1; }

    if [ -d "$YUNZAI_DIR" ]; then
        warn "Yunzai 目录已存在: $YUNZAI_DIR"
        if confirm "删除并重新克隆?" "n"; then
            rm -rf "$YUNZAI_DIR"
        else
            step "跳过克隆，直接安装依赖"
            cd "$YUNZAI_DIR" || return 1
            pnpm install
            success "Yunzai 依赖更新完成"
            return 0
        fi
    fi

    step "克隆 Yunzai 项目"
    git clone --depth 1 "$YUNZAI_REPO" "$YUNZAI_DIR" || {
        error "克隆失败，尝试 GitHub 镜像..."
        git clone --depth 1 "https://github.com/TimeRainStarSky/Yunzai" "$YUNZAI_DIR" || {
            error "克隆失败，请检查网络"
            return 1
        }
    }

    step "安装依赖"
    cd "$YUNZAI_DIR" || return 1
    pnpm install || { error "依赖安装失败"; return 1; }

    success "Yunzai 安装完成: $YUNZAI_DIR"
    echo ""
    echo "  启动方式:"
    echo "    cd $YUNZAI_DIR && pnpm start"
    echo "    或使用本模块 [启动 Yunzai]"
}

# ============================================================
#  安装 NapCat
# ============================================================
yunzai_install_napcat() {
    header "安装 NapCat (QQ 协议端)"

    # 架构映射
    local arch_map
    case "$ARCH" in
        x86_64)  arch_map="amd64" ;;
        aarch64) arch_map="arm64" ;;
        *)       error "不支持的架构: $ARCH"; return 1 ;;
    esac
    echo "  架构: $arch_map"

    # 检查依赖
    has_cmd unzip || { error "缺少 unzip，请先安装系统依赖"; return 1; }
    has_cmd jq || { error "缺少 jq，请先安装系统依赖"; return 1; }

    cd "$HOME" || return 1

    # 下载 NapCat
    local napcat_zip="NapCat.Shell.zip"
    if [ ! -f "$napcat_zip" ]; then
        step "下载 NapCat..."
        curl -f -L -# "https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip" -o "$napcat_zip" || {
            error "NapCat 下载失败"
            return 1
        }
    else
        done_msg "NapCat 安装包已存在，跳过下载"
    fi

    # 解压
    step "解压 NapCat"
    mkdir -p "$NAPCAT_DIR"
    unzip -q -o "$napcat_zip" -d "$NAPCAT_DIR"

    # 下载 Linux QQ
    local qq_deb="QQ.deb"
    local qq_url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/beta/${QQ_BUILD}/linuxqq_${QQ_VERSION}_${arch_map}.deb"
    if [ ! -f "$qq_deb" ]; then
        step "下载 Linux QQ $QQ_VERSION ($arch_map)..."
        curl -f -L -# "$qq_url" -o "$qq_deb" || {
            error "QQ 安装包下载失败"
            return 1
        }
    else
        done_msg "QQ 安装包已存在，跳过下载"
    fi

    # 解压 QQ 到 NapCat 目录
    step "安装 Linux QQ (Rootless 模式)"
    mkdir -p "$NAPCAT_DIR"
    dpkg -x "./$qq_deb" "$NAPCAT_DIR" 2>/dev/null || {
        # 非 deb 系系统用 ar + tar 解压
        step "使用 ar 解包..."
        cd /tmp && ar x "$HOME/$qq_deb" && tar -xf data.tar.* -C "$NAPCAT_DIR" 2>/dev/null
        cd "$HOME"
    }

    # 配置 NapCat
    step "配置 NapCat"
    local qq_path="$NAPCAT_DIR/opt/QQ"
    local target="$qq_path/resources/app/app_launcher"
    local pkg_json="$qq_path/resources/app/package.json"
    local build_id="${QQ_VERSION##*-}"

    # QQ 版本配置
    local cfg_dir="$HOME/.config/QQ/versions"
    mkdir -p "$cfg_dir"
    if [ -f "$cfg_dir/config.json" ]; then
        jq --arg tv "$QQ_VERSION" --arg bid "$build_id" \
            '.baseVersion=$tv | .curVersion=$tv | .buildId=$bid' \
            "$cfg_dir/config.json" > "${cfg_dir}/config.json.tmp" && \
            mv "${cfg_dir}/config.json.tmp" "$cfg_dir/config.json"
    fi

    # 注入 NapCat
    mkdir -p "$target/napcat"
    cp -rf "$NAPCAT_DIR"/* "$target/napcat/" 2>/dev/null
    cp -rf "$NAPCAT_DIR/napcat"/* "$target/napcat/" 2>/dev/null
    chmod -R +x "$target/napcat/" 2>/dev/null

    echo "(async () => {await import('file:///${target}/napcat/napcat.mjs');})();" > "$qq_path/resources/app/loadNapCat.js"
    jq '.main="./loadNapCat.js"' "$pkg_json" > ./package.json.tmp && mv ./package.json.tmp "$pkg_json"

    # 安装 TUI-CLI
    step "安装 NapCat TUI-CLI"
    local cli_script="/tmp/install-napcat-cli.sh"
    curl -f -L -# "$NAPCAT_CLI_URL" -o "$cli_script" 2>/dev/null
    if [ -f "$cli_script" ]; then
        chmod +x "$cli_script"
        yes "" | "$cli_script" 2>/dev/null
        rm -f "$cli_script"
    fi

    # 清理
    rm -f "$napcat_zip" "$qq_deb" ./package.json.tmp

    success "NapCat 安装完成"
    echo ""
    echo "  启动方式: napcat"
    echo "  安装路径: $NAPCAT_DIR"
}

# ============================================================
#  启动管理
# ============================================================
yunzai_start() {
    header "启动 Yunzai"
    if [ ! -d "$YUNZAI_DIR" ]; then
        error "Yunzai 未安装，请先安装"
        return 1
    fi
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if has_cmd screen; then
        step "使用 screen 后台启动 (session: yunzai)"
        screen -dmS yunzai bash -c "cd $YUNZAI_DIR && pnpm start"
        sleep 2
        if screen -list | grep -q yunzai; then
            success "Yunzai 已在 screen 会话中启动"
            echo "  查看: screen -r yunzai"
            echo "  退出会话: Ctrl+A 然后 D"
        else
            warn "启动可能失败，尝试前台启动..."
            cd "$YUNZAI_DIR" && pnpm start
        fi
    else
        warn "未安装 screen，前台启动 (Ctrl+C 停止)"
        cd "$YUNZAI_DIR" && pnpm start
    fi
}

napcat_start() {
    header "启动 NapCat"
    if has_cmd napcat; then
        step "启动 NapCat TUI-CLI"
        napcat
    elif [ -f "$NAPCAT_DIR/opt/QQ/qq" ]; then
        warn "napcat 命令未找到，直接启动 QQ"
        "$NAPCAT_DIR/opt/QQ/qq" --no-sandbox 2>/dev/null &
        success "QQ 已后台启动"
    else
        error "NapCat 未安装"
        return 1
    fi
}

yunzai_status() {
    header "Yunzai / NapCat 状态"
    echo ""
    echo "  --- Yunzai ---"
    if [ -d "$YUNZAI_DIR" ]; then
        echo "  安装路径: $YUNZAI_DIR"
        if screen -list 2>/dev/null | grep -q yunzai; then
            success "运行中 (screen: yunzai)"
        else
            warn "未在运行"
        fi
    else
        echo "  未安装"
    fi

    echo ""
    echo "  --- NapCat ---"
    if [ -d "$NAPCAT_DIR/opt/QQ" ]; then
        echo "  安装路径: $NAPCAT_DIR"
        if pgrep -f "qq" &>/dev/null || pgrep -f "napcat" &>/dev/null; then
            success "运行中"
        else
            warn "未在运行"
        fi
        has_cmd napcat && echo "  CLI: 已安装" || echo "  CLI: 未安装"
    else
        echo "  未安装"
    fi

    echo ""
    echo "  --- 运行环境 ---"
    has_cmd node && echo "  Node: $(node -v)" || echo "  Node: 未安装"
    has_cmd pnpm && echo "  PNPM: $(pnpm -v)" || echo "  PNPM: 未安装"
    local cli
    cli="$(has_cmd valkey-cli && echo valkey-cli || (has_cmd redis-cli && echo redis-cli || echo ''))"
    [ -n "$cli" ] && echo "  Redis/Valkey: $($cli ping 2>/dev/null || echo 未运行)" || echo "  Redis/Valkey: 未安装"
}

yunzai_logs() {
    header "Yunzai 日志"
    if screen -list 2>/dev/null | grep -q yunzai; then
        echo "  正在连接 screen 会话 (Ctrl+A D 退出)..."
        sleep 1
        screen -r yunzai
    elif [ -f "$YUNZAI_DIR/logs/$(date +%Y-MM-DD).log" ]; then
        tail -f "$YUNZAI_DIR/logs/$(date +%Y-MM-DD).log"
    else
        warn "未找到运行中的 Yunzai 或日志文件"
        echo "  日志目录: $YUNZAI_DIR/logs/"
        ls -la "$YUNZAI_DIR/logs/" 2>/dev/null | sed 's/^/  /'
    fi
}

# ============================================================
#  一键安装
# ============================================================
yunzai_install_all() {
    header "一键安装 Yunzai + NapCat"
    echo "  将执行以下步骤:"
    echo "    1. 环境检查"
    echo "    2. 安装系统依赖 (ffmpeg/字体/Chrome依赖等)"
    echo "    3. 安装 Node.js 环境 (NVM+Node+PNPM)"
    echo "    4. 安装 Valkey/Redis"
    echo "    5. 安装 Yunzai"
    echo "    6. 安装 NapCat + Linux QQ"
    echo ""
    echo "  注意: 换源和 Docker 安装请使用主菜单对应模块"
    echo ""
    if ! confirm "确认开始一键安装?" "y"; then
        warn "已取消"
        return 0
    fi

    echo ""
    yunzai_check_env
    echo ""
    yunzai_install_deps
    echo ""
    yunzai_install_node
    echo ""
    yunzai_install_valkey
    echo ""
    yunzai_install_yunzai
    echo ""
    yunzai_install_napcat

    echo ""
    echo "═══════════════════════════════════════════════════"
    success "全部安装完成！"
    echo ""
    echo "  启动 Yunzai:  cd $YUNZAI_DIR && pnpm start"
    echo "  启动 NapCat:  napcat"
    echo "  或使用本模块菜单中的启动选项"
    echo "═══════════════════════════════════════════════════"
}

# ============================================================
#  模块菜单
# ============================================================
yunzai_menu() {
    while true; do
        header "Yunzai 机器人部署"
        echo "  1) 一键安装 Yunzai + NapCat (推荐)"
        echo "  2) 环境检查"
        echo "  3) 安装系统依赖"
        echo "  4) 安装 Node.js 环境"
        echo "  5) 安装 Valkey/Redis"
        echo "  6) 安装 Yunzai"
        echo "  7) 安装 NapCat"
        echo "  8) 启动 Yunzai"
        echo "  9) 启动 NapCat"
        echo " 10) 查看运行状态"
        echo " 11) 查看 Yunzai 日志"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1)  yunzai_install_all; pause ;;
            2)  yunzai_check_env; pause ;;
            3)  yunzai_install_deps; pause ;;
            4)  yunzai_install_node; pause ;;
            5)  yunzai_install_valkey; pause ;;
            6)  yunzai_install_yunzai; pause ;;
            7)  yunzai_install_napcat; pause ;;
            8)  yunzai_start ;;
            9)  napcat_start ;;
            10) yunzai_status; pause ;;
            11) yunzai_logs ;;
            0)  break ;;
            *)  warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    yunzai_menu
fi
