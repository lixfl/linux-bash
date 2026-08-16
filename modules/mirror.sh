#!/usr/bin/env bash
# ============================================================
#  mirror.sh - 软件源换源
#  集成 linuxmirrors.cn 一键换源脚本，支持主流发行版
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
    warn "将运行官方换源脚本，会交互式询问选择镜像源"
    if ! confirm "继续?" "y"; then return 0; fi

    if ! has_cmd curl; then
        step "安装 curl"
        pkg_install curl
    fi

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

# ---- 手动换源（常见发行版） ----
mirror_manual() {
    require_root || return 1
    header "手动换源"
    echo "  支持的发行版:"
    echo "    1) Ubuntu / Debian (清华源)"
    echo "    2) CentOS / Rocky / Alma (清华源)"
    echo "    3) Alpine (清华源)"
    echo "    4) Arch Linux (清华源)"
    echo "    0) 返回"
    local opt
    opt="$(ask "请选择" "0")"
    case "$opt" in
        1) _mirror_debian ;;
        2) _mirror_rhel ;;
        3) _mirror_alpine ;;
        4) _mirror_arch ;;
        0) return 0 ;;
        *) warn "无效选项" ;;
    esac
}

_mirror_debian() {
    local mirror="https://mirrors.tuna.tsinghua.edu.cn"
    if [ "$OS_NAME" = "ubuntu" ]; then
        safe_backup_file /etc/apt/sources.list
        cat > /etc/apt/sources.list <<EOF
deb ${mirror}/ubuntu/ $(lsb_release -cs 2>/dev/null || echo jammy) main restricted universe multiverse
deb ${mirror}/ubuntu/ $(lsb_release -cs 2>/dev/null || echo jammy)-updates main restricted universe multiverse
deb ${mirror}/ubuntu/ $(lsb_release -cs 2>/dev/null || echo jammy)-backports main restricted universe multiverse
deb ${mirror}/ubuntu/ $(lsb_release -cs 2>/dev/null || echo jammy)-security main restricted universe multiverse
EOF
    else
        safe_backup_file /etc/apt/sources.list
        cat > /etc/apt/sources.list <<EOF
deb ${mirror}/debian/ $(lsb_release -cs 2>/dev/null || echo bookworm) main contrib non-free non-free-firmware
deb ${mirror}/debian/ $(lsb_release -cs 2>/dev/null || echo bookworm)-updates main contrib non-free non-free-firmware
deb ${mirror}/debian-security/ $(lsb_release -cs 2>/dev/null || echo bookworm)-security main contrib non-free non-free-firmware
EOF
    fi
    apt-get update -qq
    success "Debian/Ubuntu 源已切换为清华源"
}

_mirror_rhel() {
    local mirror="https://mirrors.tuna.tsinghua.edu.cn"
    if [ "$OS_NAME" = "centos" ]; then
        safe_backup_file /etc/yum.repos.d/CentOS-Base.repo 2>/dev/null
        sed -i "s|^mirrorlist=|#mirrorlist=|g; s|^#baseurl=http://mirror.centos.org|baseurl=${mirror}|g" /etc/yum.repos.d/CentOS-*.repo 2>/dev/null
    else
        # Rocky/Alma
        for f in /etc/yum.repos.d/*.repo; do
            [ -f "$f" ] || continue
            safe_backup_file "$f"
            sed -i "s|^mirrorlist=|#mirrorlist=|g; s|^#baseurl=|baseurl=|g" "$f"
            sed -i "s|download.rockylinux.org/pub|${mirror}/rocky|g; s|repo.almalinux.org|${mirror}/almalinux|g" "$f"
        done
    fi
    dnf makecache 2>/dev/null || yum makecache
    success "RHEL 系源已切换"
}

_mirror_alpine() {
    local mirror="https://mirrors.tuna.tsinghua.edu.cn/alpine"
    safe_backup_file /etc/apk/repositories
    cat > /etc/apk/repositories <<EOF
${mirror}/v3.20/main
${mirror}/v3.20/community
EOF
    apk update
    success "Alpine 源已切换为清华源"
}

_mirror_arch() {
    local mirror="https://mirrors.tuna.tsinghua.edu.cn/archlinux"
    local conf="/etc/pacman.d/mirrorlist"
    safe_backup_file "$conf"
    sed -i "1i Server = ${mirror}/\$repo/os/\$arch" "$conf"
    pacman -Syy
    success "Arch Linux 源已切换为清华源"
}

# ---- 模块菜单 ----
mirror_menu() {
    while true; do
        header "软件源换源"
        echo "  1) 一键换源 (linuxmirrors.cn 交互式)"
        echo "  2) 查看当前源配置"
        echo "  3) 手动换源 (清华源)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) mirror_auto; pause ;;
            2) mirror_show; pause ;;
            3) mirror_manual; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    mirror_menu
fi
