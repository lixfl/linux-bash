#!/usr/bin/env bash
# ============================================================
#  reinstall.sh - 一键 DD / 重装系统
#  集成 bin456789/reinstall，支持 Linux/Windows/Alpine/netboot.xyz
#  警告：此操作将清除整个硬盘所有数据！
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

REINSTALL_URL_GITHUB="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
REINSTALL_URL_CN="https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh"
REINSTALL_SCRIPT="/tmp/reinstall.sh"

# ---- 下载 reinstall 脚本 ----
_download_reinstall() {
    if [ -f "$REINSTALL_SCRIPT" ]; then
        debug "reinstall.sh 已存在，跳过下载"
        return 0
    fi
    step "下载 reinstall 脚本..."
    if has_cmd curl; then
        curl -fsSL "$REINSTALL_URL_CN" -o "$REINSTALL_SCRIPT" 2>/dev/null || \
        curl -fsSL "$REINSTALL_URL_GITHUB" -o "$REINSTALL_SCRIPT" 2>/dev/null
    elif has_cmd wget; then
        wget -qO "$REINSTALL_SCRIPT" "$REINSTALL_URL_CN" 2>/dev/null || \
        wget -qO "$REINSTALL_SCRIPT" "$REINSTALL_URL_GITHUB" 2>/dev/null
    else
        error "需要 curl 或 wget"
        return 1
    fi
    if [ ! -s "$REINSTALL_SCRIPT" ]; then
        error "下载失败，请检查网络"
        return 1
    fi
    chmod +x "$REINSTALL_SCRIPT"
    done_msg "脚本已下载: $REINSTALL_SCRIPT"
    return 0
}

# ---- 危险警告 ----
_danger_warning() {
    echo ""
    echo -e "${RED}${BOLD}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║              ⚠  危险操作警告  ⚠                   ║${NC}"
    echo -e "${RED}${BOLD}╠═══════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}${BOLD}║  此操作将清除当前系统整个硬盘的全部数据！           ║${NC}"
    echo -e "${RED}${BOLD}║  包含所有分区、文件、数据库，且不可恢复！           ║${NC}"
    echo -e "${RED}${BOLD}║                                                   ║${NC}"
    echo -e "${RED}${BOLD}║  请确保：                                         ║${NC}"
    echo -e "${RED}${BOLD}║  1. 已备份所有重要数据                            ║${NC}"
    echo -e "${RED}${BOLD}║  2. 记住新系统的用户名和密码                      ║${NC}"
    echo -e "${RED}${BOLD}║  3. 服务器支持 VNC / 控制台（以防网络配置失败）   ║${NC}"
    echo -e "${RED}${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ---- 收集通用参数 ----
_collect_common_args() {
    local args=""
    local username password ssh_key ssh_port
    username="$(ask "新系统用户名(留空默认 root)" "")"
    [ -n "$username" ] && args="$args --username $username"
    echo -n "  新系统密码(留空则随机生成，输入不回显): "
    read -rs password
    echo ""
    [ -n "$password" ] && args="$args --password $password"
    ssh_key="$(ask "SSH公钥(留空不设置，支持 github:用户名)" "")"
    [ -n "$ssh_key" ] && args="$args --ssh-key \"$ssh_key\""
    ssh_port="$(ask "SSH端口(留空默认22)" "")"
    [ -n "$ssh_port" ] && args="$args --ssh-port $ssh_port"
    echo "$args"
}

# ---- 重装 Linux ----
reinstall_linux() {
    require_root || return 1
    _danger_warning
    header "重装为 Linux"

    echo "  支持的系统:"
    echo "    1) Ubuntu        2) Debian        3) CentOS"
    echo "    4) Rocky Linux   5) AlmaLinux     6) Oracle"
    echo "    7) Alpine        8) Arch Linux    9) Kali"
    echo "    10) openCloudOS  11) Anolis       12) Fedora"
    echo "    0) 返回"
    echo ""
    local sys_choice
    sys_choice="$(ask "选择系统" "1")"

    local distro=""
    case "$sys_choice" in
        1) distro="ubuntu" ;;
        2) distro="debian" ;;
        3) distro="centos" ;;
        4) distro="rocky" ;;
        5) distro="almalinux" ;;
        6) distro="oracle" ;;
        7) distro="alpine" ;;
        8) distro="arch" ;;
        9) distro="kali" ;;
        10) distro="opencloudos" ;;
        11) distro="anolis" ;;
        12) distro="fedora" ;;
        0) return 0 ;;
        *) warn "无效选项"; return 1 ;;
    esac

    local version
    version="$(ask "版本号(留空安装最新版)" "")"

    local args
    args="$(_collect_common_args)"

    echo ""
    echo "  将执行: bash reinstall.sh $distro $version $args"
    echo ""
    if ! confirm "确认重装？此操作不可撤销！" "n"; then
        warn "已取消"
        return 0
    fi

    _download_reinstall || return 1
    step "开始重装系统，重启后可通过 SSH 或 80 端口查看进度..."
    bash "$REINSTALL_SCRIPT" $distro $version $args
}

# ---- 安装 Windows ----
reinstall_windows() {
    require_root || return 1
    _danger_warning
    header "安装 Windows"

    echo "  常用镜像名称示例:"
    echo "    - Windows 11 Pro"
    echo "    - Windows 11 Enterprise LTSC 2024"
    echo "    - Windows 10 Pro"
    echo "    - Windows 10 Enterprise LTSC 2021"
    echo "    - Windows Server 2022 Datacenter"
    echo "    - Windows Server 2019 Datacenter"
    echo ""

    local image_name lang iso rdp_port
    image_name="$(ask "镜像名称 (--image-name)" "Windows 11 Pro")"
    lang="$(ask "语言 (zh-cn/en-us等)" "zh-cn")"
    iso="$(ask "自定义ISO链接(留空自动查找)" "")"
    rdp_port="$(ask "RDP端口(留空默认3389)" "")"

    local args="--image-name \"$image_name\" --lang $lang"
    [ -n "$iso" ] && args="$args --iso \"$iso\""
    [ -n "$rdp_port" ] && args="$args --rdp-port $rdp_port"

    local username password
    username="$(ask "管理员用户名(留空默认 administrator)" "")"
    [ -n "$username" ] && args="$args --username $username"
    echo -n "  管理员密码(留空随机生成，输入不回显): "
    read -rs password
    echo ""
    [ -n "$password" ] && args="$args --password $password"

    if confirm "允许 Ping?" "y"; then
        args="$args --allow-ping"
    fi

    echo ""
    echo "  将执行: bash reinstall.sh windows $args"
    echo ""
    if ! confirm "确认安装 Windows？将清除整个硬盘！" "n"; then
        warn "已取消"
        return 0
    fi

    _download_reinstall || return 1
    step "开始安装 Windows..."
    bash "$REINSTALL_SCRIPT" windows $args
}

# ---- DD 自定义镜像 ----
reinstall_dd() {
    require_root || return 1
    _danger_warning
    header "DD 自定义镜像"
    echo "  支持 .img .gz .xz .zip .tar.gz 等格式的 RAW 镜像"
    echo ""
    local img_url
    img_url="$(ask "镜像直链 URL" "")"
    [ -z "$img_url" ] && { warn "URL 不能为空"; return 1; }

    echo ""
    echo "  将执行: bash reinstall.sh dd --img=\"$img_url\""
    echo ""
    if ! confirm "确认 DD？将清除整个硬盘！" "n"; then
        warn "已取消"
        return 0
    fi

    _download_reinstall || return 1
    bash "$REINSTALL_SCRIPT" dd --img="$img_url"
}

# ---- 引导到 Alpine Live ----
reinstall_alpine_live() {
    require_root || return 1
    header "引导到 Alpine Live OS (内存系统)"
    echo "  此功能不会删除数据，重启后回到原系统"
    echo "  可用于：备份恢复、手动DD、修改分区、救砖"
    echo ""
    local args
    args="$(_collect_common_args)"

    if confirm "确认重启到 Alpine Live?" "y"; then
        _download_reinstall || return 1
        bash "$REINSTALL_SCRIPT" alpine --hold 1 $args
    fi
}

# ---- 引导到 netboot.xyz ----
reinstall_netboot() {
    require_root || return 1
    header "引导到 netboot.xyz"
    echo "  此功能不会删除数据，通过 VNC 手动选择系统安装"
    echo ""
    if confirm "确认重启到 netboot.xyz?" "y"; then
        _download_reinstall || return 1
        bash "$REINSTALL_SCRIPT" netboot.xyz
    fi
}

# ---- 取消重装 ----
reinstall_cancel() {
    require_root || return 1
    header "取消重装"
    if [ ! -f "$REINSTALL_SCRIPT" ]; then
        _download_reinstall || return 1
    fi
    warn "将取消已计划的重装操作（仅在重启前有效）"
    if confirm "确认取消?" "y"; then
        bash "$REINSTALL_SCRIPT" reset
        success "已取消重装计划"
    fi
}

# ---- 模块菜单 ----
reinstall_menu() {
    while true; do
        header "一键 DD / 重装系统"
        echo -e "  ${RED}⚠ 本模块所有操作都可能清除硬盘数据，请谨慎操作${NC}"
        echo ""
        echo "  1) 重装为 Linux (Ubuntu/Debian/CentOS等)"
        echo "  2) 安装 Windows"
        echo "  3) DD 自定义镜像"
        echo "  4) 引导到 Alpine Live (不删数据)"
        echo "  5) 引导到 netboot.xyz (不删数据)"
        echo "  6) 取消已计划的重装"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) reinstall_linux; pause ;;
            2) reinstall_windows; pause ;;
            3) reinstall_dd; pause ;;
            4) reinstall_alpine_live; pause ;;
            5) reinstall_netboot; pause ;;
            6) reinstall_cancel; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    reinstall_menu
fi
