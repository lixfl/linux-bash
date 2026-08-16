#!/usr/bin/env bash
# ============================================================
#  info.sh - 系统信息查看
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

info_hardware() {
    header "硬件信息"
    echo "  CPU 型号: $(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)"
    echo "  CPU 核心: $CPU_CORES"
    echo "  架构: $ARCH"
    echo "  内存总量: ${TOTAL_MEM_GB} GB"
    echo "  交换分区: $(free -h | awk '/^Swap:/ {print $2}')"
    echo ""
    section "CPU 详细"
    lscpu 2>/dev/null | grep -E "Model name|Socket|Core|Thread|CPU MHz|Vendor|Architecture" | sed 's/^/  /'
    echo ""
    section "内存插槽"
    if has_cmd dmidecode && [ "$IS_ROOT" = "1" ]; then
        dmidecode -t memory 2>/dev/null | grep -E "Size:|Speed:|Manufacturer:|Type:" | grep -v "No Module" | sed 's/^/  /'
    else
        free -h | sed 's/^/  /'
    fi
    echo ""
    section "磁盘"
    lsblk 2>/dev/null | sed 's/^/  /' || fdisk -l 2>/dev/null | sed 's/^/  /'
}

info_os() {
    header "操作系统信息"
    printf "  %-18s %s\n" "发行版:" "$OS_PRETTY"
    printf "  %-18s %s\n" "内核版本:" "$(uname -r)"
    printf "  %-18s %s\n" "内核编译:" "$(uname -v)"
    printf "  %-18s %s\n" "主机名:" "$(hostname)"
    printf "  %-18s %s\n" "时区:" "$(timedatectl 2>/dev/null | grep 'Time zone' | awk '{print $3}' || date +%Z)"
    printf "  %-18s %s\n" "当前时间:" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf "  %-18s %s\n" "运行时长:" "$(uptime -p 2>/dev/null || uptime)"
    printf "  %-18s %s\n" "负载:" "$(cat /proc/loadavg)"
    printf "  %-18s %s\n" "语言:" "${LANG:-N/A}"
    echo ""
    section "已安装包数量"
    case "$PKG_MANAGER" in
        apt)    dpkg -l 2>/dev/null | grep -c '^ii' ;;
        dnf|yum) rpm -qa 2>/dev/null | wc -l ;;
        apk)    apk info 2>/dev/null | wc -l ;;
        pacman) pacman -Q 2>/dev/null | wc -l ;;
        *) echo "N/A" ;;
    esac | sed 's/^/  /'
}

info_network() {
    header "网络信息"
    printf "  %-18s %s\n" "主机名:" "$(hostname)"
    printf "  %-18s %s\n" "主 IP:" "${HOST_IP:-N/A}"
    echo ""
    section "网卡信息"
    ip addr 2>/dev/null | grep -E "^[0-9]+:|inet " | sed 's/^/  /'
    echo ""
    section "路由表"
    ip route 2>/dev/null | sed 's/^/  /'
    echo ""
    section "DNS"
    if [ -f /etc/resolv.conf ]; then
        grep -E "^nameserver|^search" /etc/resolv.conf | sed 's/^/  /'
    fi
    echo ""
    section "公网 IP"
    if has_cmd curl; then
        local pub
        pub="$(curl -s --max-time 3 ifconfig.me 2>/dev/null || curl -s --max-time 3 ip.sb 2>/dev/null)"
        echo "  ${pub:-获取失败}"
    else
        echo "  (未安装 curl)"
    fi
}

info_users() {
    header "用户与登录"
    section "当前登录用户"
    who 2>/dev/null | sed 's/^/  /'
    echo ""
    section "最近登录记录"
    last -n 10 2>/dev/null | sed 's/^/  /'
    echo ""
    section "可登录用户(UID>=1000)"
    awk -F: '$3>=1000 && $7 !~ /(nologin|false)/ {print "  "$1" ("$3") - "$6}' /etc/passwd
    echo ""
    section "sudo 用户"
    getent group sudo 2>/dev/null | sed 's/^/  /'
    getent group wheel 2>/dev/null | sed 's/^/  /'
}

info_services() {
    header "服务状态"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        section "运行中的服务"
        systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -30 | sed 's/^/  /'
        echo ""
        section "失败的服务"
        systemctl --failed --no-pager 2>/dev/null | sed 's/^/  /'
    else
        section "服务列表"
        service --status-all 2>/dev/null | sed 's/^/  /' || ls /etc/init.d/ | sed 's/^/  /'
    fi
}

info_full() {
    info_os
    info_hardware
    info_network
    info_users
    info_services
}

info_menu() {
    while true; do
        header "系统信息"
        echo "  1) 操作系统信息"
        echo "  2) 硬件信息"
        echo "  3) 网络信息"
        echo "  4) 用户与登录"
        echo "  5) 服务状态"
        echo "  6) 全部信息"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) info_os; pause ;;
            2) info_hardware; pause ;;
            3) info_network; pause ;;
            4) info_users; pause ;;
            5) info_services; pause ;;
            6) info_full; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    info_menu
fi
