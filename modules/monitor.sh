#!/usr/bin/env bash
# ============================================================
#  monitor.sh - 系统监控
#  功能：资源概览、实时监控、进程/端口 TOP、告警检测、报告
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

LOG_DIR="${TOOLKIT_ROOT}/logs"

# ---- CPU 使用率 ----
_cpu_usage() {
    # 读取 /proc/stat 两次计算
    local cpu1=($(awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8}' /proc/stat))
    sleep 1
    local cpu2=($(awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8}' /proc/stat))
    local idle1=$((cpu1[3]+cpu1[4]))
    local idle2=$((cpu2[3]+cpu2[4]))
    local total1=0 total2=0
    for v in "${cpu1[@]}"; do total1=$((total1+v)); done
    for v in "${cpu2[@]}"; do total2=$((total2+v)); done
    local total_diff=$((total2-total1))
    local idle_diff=$((idle2-idle1))
    if [ "$total_diff" -gt 0 ]; then
        awk "BEGIN {printf \"%.1f\", (1 - $idle_diff/$total_diff) * 100}"
    else
        echo "0.0"
    fi
}

# ---- 内存使用率 ----
_mem_usage() {
    free | awk '/^Mem:/ {printf "%.1f", $3/$2*100}'
}

# ---- 磁盘使用率（根分区） ----
_disk_usage() {
    df -P / | awk 'NR==2 {print $5}' | tr -d '%'
}

# ---- 各分区使用率 ----
_disk_all() {
    df -hP -x tmpfs -x devtmpfs -x overlay 2>/dev/null | awk 'NR==1 || NR>1 {print}'
}

# ---- 网络流量（简单版） ----
_net_traffic() {
    local iface
    iface="$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')"
    [ -z "$iface" ] && iface="$(ls /sys/class/net | grep -v lo | head -1)"
    [ -z "$iface" ] && { echo "  无可用网卡"; return; }
    local rx1 tx1 rx2 tx2
    rx1="$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null)"
    tx1="$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null)"
    sleep 1
    rx2="$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null)"
    tx2="$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null)"
    local rx_s=$(( (rx2-rx1)/1024 ))
    local tx_s=$(( (tx2-tx1)/1024 ))
    echo "  网卡: $iface"
    echo "  下载: ${rx_s} KB/s"
    echo "  上传: ${tx_s} KB/s"
}

# ---- 资源概览 ----
monitor_overview() {
    header "系统资源概览"
    local cpu mem disk load uptime
    cpu="$(_cpu_usage)"
    mem="$(_mem_usage)"
    disk="$(_disk_usage)"
    load="$(cat /proc/loadavg | awk '{print $1, $2, $3}')"
    uptime="$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"

    printf "  %-16s %s\n" "主机名:" "$(hostname)"
    printf "  %-16s %s\n" "运行时间:" "$uptime"
    printf "  %-16s %s\n" "负载(1/5/15m):" "$load"
    printf "  %-16s %s%%\n" "CPU 使用率:" "$cpu"
    printf "  %-16s %s%%\n" "内存使用率:" "$mem"
    printf "  %-16s %s%%\n" "根分区使用率:" "$disk"
    echo ""
    section "内存详情"
    free -h
    echo ""
    section "磁盘分区"
    _disk_all
    echo ""
    section "网络流量(1秒采样)"
    _net_traffic
}

# ---- 进程 TOP ----
monitor_top_processes() {
    header "进程 TOP 10 (按 CPU)"
    ps aux --sort=-%cpu 2>/dev/null | head -11 | awk '{printf "  %-10s %-8s %-6s %-6s %s\n", $1, $2, $3"%", $4"%", $11}'
    echo ""
    header "进程 TOP 10 (按内存)"
    ps aux --sort=-%mem 2>/dev/null | head -11 | awk '{printf "  %-10s %-8s %-6s %-6s %s\n", $1, $2, $3"%", $4"%", $11}'
}

# ---- 监听端口 ----
monitor_ports() {
    header "监听端口"
    if has_cmd ss; then
        ss -tlnp 2>/dev/null | awk 'NR==1 || NR>1 {print}' | head -30
    elif has_cmd netstat; then
        netstat -tlnp 2>/dev/null | head -30
    else
        warn "未找到 ss/netstat，尝试安装 iproute2..."
        pkg_install iproute2 2>/dev/null && ss -tlnp | head -30
    fi
}

# ---- 实时监控（类 top，每 2 秒刷新） ----
monitor_realtime() {
    header "实时监控 (Ctrl+C 退出)"
    if has_cmd top; then
        if confirm "使用系统 top 命令?" "y"; then
            top
            return 0
        fi
    fi
    # 简易版
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== 实时监控 ===  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
        echo ""
        echo "  CPU: $(_cpu_usage)%   内存: $(_mem_usage)%   磁盘: $(_disk_usage)%"
        echo "  负载: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
        echo ""
        echo "  --- TOP 5 CPU ---"
        ps aux --sort=-%cpu 2>/dev/null | head -6 | awk '{printf "  %-8s %-5s%% %s\n", $2, $3, $11}'
        sleep 2
    done
}

# ---- 资源告警检测 ----
monitor_alert() {
    header "资源告警检测"
    local cpu mem disk issues=0

    cpu="$(_cpu_usage)"
    mem="$(_mem_usage)"
    disk="$(_disk_usage)"

    if [ "$(echo "$cpu > 80" | bc -l 2>/dev/null)" = "1" ]; then
        warn "CPU 使用率过高: ${cpu}% (>80%)"
        issues=$((issues+1))
    else
        done_msg "CPU 正常: ${cpu}%"
    fi

    if [ "$(echo "$mem > 85" | bc -l 2>/dev/null)" = "1" ]; then
        warn "内存使用率过高: ${mem}% (>85%)"
        issues=$((issues+1))
    else
        done_msg "内存正常: ${mem}%"
    fi

    if [ "$disk" -gt 90 ]; then
        warn "根分区使用率过高: ${disk}% (>90%)"
        issues=$((issues+1))
    else
        done_msg "磁盘正常: ${disk}%"
    fi

    # 检查 OOM
    if dmesg 2>/dev/null | grep -qi "out of memory"; then
        warn "检测到 OOM 记录！"
        issues=$((issues+1))
    fi

    # 检查只读文件系统
    if grep -q " ro," /proc/mounts 2>/dev/null; then
        # 排除正常的只读挂载如 /sys /proc
        if grep -vE "(proc|sysfs|tmpfs|devtmpfs|cgroup|securityfs|pstore|bpf|tracefs|configfs|fusectl|debugfs|hugetlbfs|mqueue|selinux)" /proc/mounts | grep -q " ro,"; then
            warn "检测到只读挂载的文件系统！"
            issues=$((issues+1))
        fi
    fi

    echo ""
    if [ "$issues" -eq 0 ]; then
        success "未发现异常"
    else
        error "共发现 $issues 个告警项"
    fi
}

# ---- 生成监控报告 ----
monitor_report() {
    header "生成监控报告"
    mkdir -p "$LOG_DIR"
    local report="${LOG_DIR}/monitor_report_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "========================================"
        echo "  服务器监控报告"
        echo "  生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================"
        echo ""
        echo "## 系统信息"
        echo "主机名: $(hostname)"
        echo "系统: $OS_PRETTY"
        echo "内核: $(uname -r)"
        echo "架构: $ARCH"
        echo "运行时间: $(uptime -p 2>/dev/null || uptime)"
        echo ""
        echo "## 资源使用"
        echo "CPU 使用率: $(_cpu_usage)%"
        echo "内存使用率: $(_mem_usage)%"
        echo ""
        free -h
        echo ""
        echo "## 磁盘使用"
        df -hP -x tmpfs -x devtmpfs 2>/dev/null
        echo ""
        echo "## 负载"
        cat /proc/loadavg
        echo ""
        echo "## TOP 10 进程(CPU)"
        ps aux --sort=-%cpu 2>/dev/null | head -11
        echo ""
        echo "## 监听端口"
        ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
        echo ""
        echo "## 最近登录"
        last -n 10 2>/dev/null
        echo ""
        echo "## 失败登录尝试"
        if [ -f /var/log/auth.log ]; then
            grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo "0"
        elif [ -f /var/log/secure ]; then
            grep -c "Failed password" /var/log/secure 2>/dev/null || echo "0"
        else
            echo "N/A"
        fi
    } > "$report"

    success "报告已生成: $report"
    echo ""
    if confirm "是否立即查看?" "y"; then
        less "$report"
    fi
}

# ---- 模块菜单 ----

# ============================================================
#  告警通知推送
# ============================================================
monitor_notify() {
    header "告警通知配置"
    echo "  支持 Bark / Telegram / 钉钉 / 企业微信"
    echo ""
    local conf="$HOME/.server-toolkit/notify.conf"
    mkdir -p "$(dirname "$conf")"
    echo "  1) 配置 Bark (iOS)"
    echo "  2) 配置 Telegram Bot"
    echo "  3) 配置钉钉机器人"
    echo "  4) 配置企业微信"
    echo "  5) 发送测试消息"
    echo "  0) 返回"
    local opt
    opt="$(ask "选择" "1")"
    case "$opt" in
        1)
            local bark_key
            bark_key="$(ask "Bark Key (https://api.day.app/KEY)" "")"
            [ -n "$bark_key" ] && echo "BARK_URL=https://api.day.app/$bark_key" > "$conf" && success "Bark 已配置"
            ;;
        2)
            local tg_token tg_chat
            tg_token="$(ask "Bot Token" "")"
            tg_chat="$(ask "Chat ID" "")"
            [ -n "$tg_token" ] && echo "TG_TOKEN=$tg_token" > "$conf" && echo "TG_CHAT=$tg_chat" >> "$conf" && success "Telegram 已配置"
            ;;
        3)
            local dd_webhook
            dd_webhook="$(ask "钉钉 Webhook URL" "")"
            [ -n "$dd_webhook" ] && echo "DD_WEBHOOK=$dd_webhook" > "$conf" && success "钉钉已配置"
            ;;
        4)
            local wx_webhook
            wx_webhook="$(ask "企微 Webhook URL" "")"
            [ -n "$wx_webhook" ] && echo "WX_WEBHOOK=$wx_webhook" > "$conf" && success "企微已配置"
            ;;
        5)
            [ -f "$conf" ] || { warn "未配置通知渠道"; return 1; }
            source "$conf"
            local msg="服务器告警测试 - $(hostname) - $(date '+%Y-%m-%d %H:%M:%S')"
            [ -n "${BARK_URL:-}" ] && curl -s "$BARK_URL/$msg" >/dev/null && success "Bark 已发送"
            [ -n "${TG_TOKEN:-}" ] && curl -s "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d "chat_id=${TG_CHAT}&text=$msg" >/dev/null && success "Telegram 已发送"
            [ -n "${DD_WEBHOOK:-}" ] && curl -s "$DD_WEBHOOK" -H "Content-Type: application/json" -d "{"msgtype":"text","text":{"content":"$msg"}}" >/dev/null && success "钉钉已发送"
            [ -n "${WX_WEBHOOK:-}" ] && curl -s "$WX_WEBHOOK" -H "Content-Type: application/json" -d "{"msgtype":"text","text":{"content":"$msg"}}" >/dev/null && success "企微已发送"
            ;;
        0) return 0 ;;
        *) warn "无效选项" ;;
    esac
}


# ============================================================
#  性能跑分
# ============================================================
monitor_benchmark() {
    header "性能跑分测试"
    echo "  1) UnixBench (综合性能)"
    echo "  2) Geekbench 6 (CPU/内存)"
    echo "  3) fio (磁盘IO)"
    echo "  4) iperf3 (网络带宽, 需服务端)"
    echo "  0) 返回"
    local opt
    opt="$(ask "选择" "1")"
    case "$opt" in
        1)
            step "安装并运行 UnixBench (约10-20分钟)"
            pkg_install make gcc libx11-dev libgl1-mesa-dev libxext-dev 2>/dev/null
            cd /tmp && curl -fsSL https://github.com/kdlucas/byte-unixbench/archive/refs/heads/master.tar.gz -o unixbench.tar.gz
            tar -xzf unixbench.tar.gz && cd byte-unixbench-master/UnixBench && make && ./Run
            ;;
        2)
            step "下载并运行 Geekbench 6"
            cd /tmp && curl -fsSL https://cdn.geekbench.com/Geekbench-6.2.1-Linux.tar.gz -o geekbench.tar.gz
            tar -xzf geekbench.tar.gz && cd Geekbench-*-Linux && ./geekbench6
            ;;
        3)
            if ! has_cmd fio; then pkg_install fio; fi
            step "运行 fio 磁盘测试 (读写各1G)"
            fio --name=randwrite --ioengine=libaio --iodepth=32 --rw=randwrite --bs=4k --direct=1 --size=1G --numjobs=1 --runtime=30 --group_reporting
            fio --name=randread --ioengine=libaio --iodepth=32 --rw=randread --bs=4k --direct=1 --size=1G --numjobs=1 --runtime=30 --group_reporting
            ;;
        4)
            if ! has_cmd iperf3; then pkg_install iperf3; fi
            local server
            server="$(ask "服务端IP" "")"
            [ -n "$server" ] && iperf3 -c "$server" -t 10
            ;;
        0) return 0 ;;
        *) warn "无效选项" ;;
    esac
}

monitor_menu() {
    while true; do
        header "系统监控"
        echo "  1) 资源概览"
        echo "  2) 实时监控"
        echo "  3) 进程 TOP"
        echo "  4) 监听端口"
        echo "  5) 资源告警检测"
        echo "  6) 生成监控报告"
        echo "  7) 告警通知配置 (Bark/TG/钉钉/企微)"
        echo "  8) 性能跑分 (UnixBench/Geekbench/fio/iperf3)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) monitor_overview; pause ;;
            2) monitor_realtime ;;
            3) monitor_top_processes; pause ;;
            4) monitor_ports; pause ;;
            5) monitor_alert; pause ;;
            6) monitor_report; pause ;;
            7) monitor_notify; pause ;;
            8) monitor_benchmark; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    monitor_menu
fi
