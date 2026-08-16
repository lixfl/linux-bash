#!/usr/bin/env bash
# ============================================================
#  optimize.sh - 系统性能优化
#  功能：sysctl 内核调优、文件描述符、时间同步、缓存清理等
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SYSCTL_CONF="/etc/sysctl.conf"
SYSCTL_D="/etc/sysctl.d/99-toolkit.conf"

# ---- 内核参数优化 ----
optimize_sysctl() {
    require_root || return 1
    header "内核参数优化 (sysctl)"

    echo "  将优化以下参数:"
    echo "    - 网络连接队列 / backlog"
    echo "    - TCP 连接复用 / 快速回收"
    echo "    - 虚拟内存 swappiness"
    echo "    - 文件句柄上限"
    echo "    - 内核 panic 自动重启"
    echo ""

    if ! confirm "确认应用?" "y"; then return 0; fi

    local conf
    if [ -d /etc/sysctl.d ]; then
        conf="$SYSCTL_D"
    else
        conf="$SYSCTL_CONF"
    fi
    safe_backup_file "$conf" 2>/dev/null

    cat > "$conf" <<EOF
# === 服务器优化参数 $(date +%Y-%m-%d) ===

# --- 网络优化 ---
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 5000
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# --- 虚拟内存 ---
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1

# --- 文件句柄 ---
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

# --- 内核 ---
kernel.panic = 30
kernel.panic_on_oops = 1
kernel.core_uses_pid = 1
EOF

    step "应用参数"
    sysctl -p "$conf" 2>/dev/null || sysctl --system 2>/dev/null
    success "内核参数优化完成，写入: $conf"
}

# ---- 文件描述符限制 ----
optimize_ulimit() {
    require_root || return 1
    header "文件描述符限制"
    local limits="/etc/security/limits.conf"
    safe_backup_file "$limits" 2>/dev/null

    # 清理旧配置
    sed -i '/# === 工具集优化 ===/,/# === END ===/d' "$limits" 2>/dev/null

    cat >> "$limits" <<EOF
# === 工具集优化 ===
* soft nofile 655350
* hard nofile 655350
* soft nproc 655350
* hard nproc 655350
root soft nofile 655350
root hard nofile 655350
# === END ===
EOF

    # systemd 系统也需要改
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        local sysconf="/etc/systemd/system.conf"
        [ -f "$sysconf" ] && safe_backup_file "$sysconf"
        sed -i 's/^#\?DefaultLimitNOFILE=.*/DefaultLimitNOFILE=655350/' "$sysconf"
        sed -i 's/^#\?DefaultLimitNPROC=.*/DefaultLimitNPROC=655350/' "$sysconf"
        grep -q '^DefaultLimitNOFILE' "$sysconf" || echo "DefaultLimitNOFILE=655350" >> "$sysconf"
        grep -q '^DefaultLimitNPROC' "$sysconf" || echo "DefaultLimitNPROC=655350" >> "$sysconf"
    fi

    success "文件描述符上限已设为 655350（重新登录后生效）"
    echo "  当前限制: $(ulimit -n)"
}

# ---- 时间同步 ----
optimize_time() {
    require_root || return 1
    header "时间同步"

    if has_cmd timedatectl; then
        echo "  当前时区: $(timedatectl 2>/dev/null | grep 'Time zone' | awk '{print $3}')"
        echo "  NTP 同步: $(timedatectl 2>/dev/null | grep 'NTP service' | awk '{print $3}')"
        echo ""
        if confirm "设置时区为 Asia/Shanghai?" "y"; then
            timedatectl set-timezone Asia/Shanghai
            done_msg "时区已设置"
        fi
        if confirm "启用 NTP 自动同步?" "y"; then
            timedatectl set-ntp true
            sleep 2
            timedatectl | grep -E "Time zone|System clock|NTP"
            done_msg "NTP 同步已启用"
        fi
    else
        # 传统方式
        if ! has_cmd ntpd && ! has_cmd chronyd; then
            pkg_install chrony 2>/dev/null || pkg_install ntp 2>/dev/null
        fi
        cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null
        echo "Asia/Shanghai" > /etc/timezone 2>/dev/null
        svc_restart chronyd 2>/dev/null || svc_restart ntpd 2>/dev/null || svc_restart ntp 2>/dev/null
        done_msg "时间同步已配置"
    fi
    echo "  当前时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
}

# ---- 清理缓存 ----
optimize_drop_caches() {
    require_root || return 1
    header "清理系统缓存"
    local before after
    before="$(free -h | awk '/^Mem:/ {print $7}')"
    sync
    echo 3 > /proc/sys/vm/drop_caches
    after="$(free -h | awk '/^Mem:/ {print $7}')"
    echo "  清理前可用内存: $before"
    echo "  清理后可用内存: $after"
    success "缓存已清理"
}

# ---- BBR + fq 网络加速 ----
optimize_bbr() {
    require_root || return 1
    header "BBR + fq 网络加速"

    local current
    current="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    local current_qdisc
    current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    echo "  当前拥塞控制: $current"
    echo "  当前队列算法: $current_qdisc"
    echo ""

    if [ "$current" = "bbr" ]; then
        success "BBR 已启用"
        return 0
    fi

    # 检查内核是否支持 BBR
    if ! modprobe tcp_bbr 2>/dev/null && ! grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        warn "当前内核可能不支持 BBR，需要 Linux 4.9+"
        if ! confirm "继续尝试?" "n"; then return 1; fi
    fi

    if ! confirm "启用 BBR + fq?" "y"; then return 0; fi

    local conf
    if [ -d /etc/sysctl.d ]; then
        conf="/etc/sysctl.d/99-bbr.conf"
    else
        conf="/etc/sysctl.conf"
    fi

    step "写入配置"
    cat > "$conf" <<EOF
# BBR 网络加速
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_notsent_lowat = 16384
EOF

    step "加载 bbr 模块"
    modprobe tcp_bbr 2>/dev/null
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf 2>/dev/null

    step "应用参数"
    sysctl -p "$conf" 2>/dev/null || sysctl --system 2>/dev/null

    echo ""
    echo "  启用后: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    echo "  队列算法: $(sysctl -n net.core.default_qdisc 2>/dev/null)"
    success "BBR + fq 已启用"
}

# ---- 关闭不必要服务 ----
optimize_disable_services() {
    require_root || return 1
    header "关闭不必要的服务"
    [ "$INIT_SYSTEM" = "systemd" ] || { warn "仅支持 systemd"; return 1; }

    local candidates="avahi-daemon cups bluetooth ModemManager geoclue rtkit-daemon"
    local to_disable=()
    for svc in $candidates; do
        if systemctl is-active "$svc" &>/dev/null; then
            echo "  运行中: $svc"
            to_disable+=("$svc")
        fi
    done

    if [ ${#to_disable[@]} -eq 0 ]; then
        success "没有发现可关闭的常见服务"
        return 0
    fi

    echo ""
    if confirm "关闭以上 ${#to_disable[@]} 个服务?" "y"; then
        for svc in "${to_disable[@]}"; do
            systemctl stop "$svc" 2>/dev/null
            systemctl disable "$svc" 2>/dev/null
            done_msg "已停止并禁用: $svc"
        done
    fi
}

# ---- I/O 调度器 ----
optimize_io_scheduler() {
    require_root || return 1
    header "I/O 调度器优化"
    for disk in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
        [ -d "$disk" ] || continue
        local dev
        dev="$(basename "$disk")"
        if [ -f "$disk/queue/scheduler" ]; then
            local cur
            cur="$(cat "$disk/queue/scheduler")"
            echo "  $dev: $cur"
            # SSD 用 none/deadline，机械盘用 bfq/kyber
            if [[ "$dev" == nvme* ]] || [ -f "$disk/queue/rotational" ] && [ "$(cat "$disk/queue/rotational")" = "0" ]; then
                echo none > "$disk/queue/scheduler" 2>/dev/null && done_msg "$dev -> none (SSD)"
            else
                echo bfq > "$disk/queue/scheduler" 2>/dev/null || echo deadline > "$disk/queue/scheduler" 2>/dev/null
                done_msg "$dev -> bfq/deadline (HDD)"
            fi
        fi
    done
}

# ---- 一键优化 ----
optimize_all() {
    require_root || return 1
    header "一键性能优化"
    if ! confirm "将执行 sysctl 调优 + ulimit + 时间同步 + I/O 调度，确认?" "y"; then return 0; fi
    optimize_sysctl
    echo ""
    optimize_ulimit
    echo ""
    optimize_time
    echo ""
    optimize_io_scheduler
    echo ""
    success "全部优化完成，建议重启使部分参数生效"
}

optimize_menu() {
    while true; do
        header "性能优化"
        echo "  1) 内核参数优化 (sysctl)"
        echo "  2) 文件描述符限制"
        echo "  3) 时间同步配置"
        echo "  4) I/O 调度器优化"
        echo "  5) 关闭不必要服务"
        echo "  6) 清理系统缓存"
        echo "  7) BBR + fq 网络加速"
        echo "  8) 一键优化"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) optimize_sysctl; pause ;;
            2) optimize_ulimit; pause ;;
            3) optimize_time; pause ;;
            4) optimize_io_scheduler; pause ;;
            5) optimize_disable_services; pause ;;
            6) optimize_drop_caches; pause ;;
            7) optimize_bbr; pause ;;
            8) optimize_all; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    optimize_menu
fi
