#!/usr/bin/env bash
# ============================================================
#  mirror.sh - 软件源换源
#  直接调用 linuxmirrors.cn 官方一键换源脚本
# ============================================================
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MIRROR_SCRIPT_URL="https://linuxmirrors.cn/main.sh"

# ---- 一键换源 ----
mirror_auto() {
    require_root || return 1
    header "一键换源 (linuxmirrors.cn)"
    echo "  当前系统: $OS_PRETTY"
    echo "  包管理器: $PKG_MANAGER"
    echo ""
    if ! has_cmd curl; then
        step "安装 curl"
        pkg_install curl
    fi
    info "即将运行 linuxmirrors.cn 官方换源脚本"
    echo "  脚本会交互式询问选择镜像源，按提示操作即可"
    echo ""
    if ! confirm "继续?" "y"; then return 0; fi
    step "下载并执行换源脚本"
    bash <(curl -sSL "$MIRROR_SCRIPT_URL")
}

# ---- 查看当前源 ----
mirror_show() {
    header "当前软件源配置"
    case "$PKG_MANAGER" in
        apt)
            section "/etc/apt/sources.list"
            [ -f /etc/apt/sources.list ] && grep -v '^#' /etc/apt/sources.list | grep -v '^$' | sed 's/^/  /'
            section "/etc/apt/sources.list.d/"
            for f in /etc/apt/sources.list.d/*.list; do
                [ -f "$f" ] || continue
                echo "  --- $(basename "$f") ---"
                grep -v '^#' "$f" | grep -v '^$' | sed 's/^/  /'
            done
            ;;
        dnf|yum)
            section "/etc/yum.repos.d/"
            for f in /etc/yum.repos.d/*.repo; do
                [ -f "$f" ] || continue
                echo "  --- $(basename "$f") ---"
                grep -E '^\[|^baseurl|^mirrorlist|^enabled' "$f" | sed 's/^/  /'
            done
            ;;
        apk)
            section "/etc/apk/repositories"
            cat /etc/apk/repositories 2>/dev/null | sed 's/^/  /'
            ;;
        pacman)
            section "/etc/pacman.conf"
            grep -A1 '^\[' /etc/pacman.conf | grep -E '^\[|Server' | sed 's/^/  /'
            ;;
        *)
            warn "不支持的包管理器: $PKG_MANAGER"
            ;;
    esac
}

# ---- 模块菜单 ----
mirror_menu() {
    while true; do
        header "软件源换源"
        echo "  1) 一键换源 (linuxmirrors.cn 官方脚本)"
        echo "  2) 查看当前源配置"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) mirror_auto; pause ;;
            2) mirror_show; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    mirror_menu
fi
