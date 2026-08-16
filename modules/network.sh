#!/usr/bin/env bash
# ============================================================
#  network.sh - 网络诊断与管理
#  功能：连通性测试、DNS 诊断、端口检测、流量统计、速度测试
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# ---- 网络连通性测试 ----
network_ping_test() {
    header "网络连通性测试"
    local targets=("223.5.5.5" "114.114.114.114" "8.8.8.8" "baidu.com" "google.com")
    for t in "${targets[@]}"; do
        if ping -c 2 -W 2 "$t" &>/dev/null; then
            local avg
            avg="$(ping -c 3 -W 2 "$t" 2>/dev/null | awk -F'/' '/rtt/ {print $5}')"
            done_msg "$t 可达 (${avg}ms)"
        else
            fail_msg "$t 不可达"
        fi
    done
}

# ---- DNS 诊断 ----
network_dns() {
    header "DNS 诊断"
    echo "  当前 DNS 配置:"
    grep -E "^nameserver" /etc/resolv.conf 2>/dev/null | sed 's/^/    /'
    echo ""
    local domains=("baidu.com" "github.com" "google.com")
    for d in "${domains[@]}"; do
        if has_cmd dig; then
            local ip t
            ip="$(dig +short "$d" 2>/dev/null | head -1)"
            t="$(dig "$d" 2>/dev/null | awk '/Query time/ {print $4}')"
            [ -n "$ip" ] && done_msg "$d -> $ip (${t}ms)" || fail_msg "$d 解析失败"
        elif has_cmd nslookup; then
            nslookup "$d" 2>/dev/null | grep -A1 "Name:" | sed 's/^/  /'
        else
            getent hosts "$d" &>/dev/null && done_msg "$d 可解析" || fail_msg "$d 解析失败"
        fi
    done
    echo ""
    if confirm "DNS 解析慢，是否更换为阿里 DNS (223.5.5.5)?" "n"; then
        require_root || return 1
        safe_backup_file /etc/resolv.conf
        cat > /etc/resolv.conf <<EOF
nameserver 223.5.5.5
nameserver 223.6.6.6
nameserver 114.114.114.114
EOF
        success "DNS 已更新"
    fi
}

# ---- 端口检测 ----
network_port_check() {
    header "端口检测"
    local host port
    host="$(ask "目标主机" "127.0.0.1")"
    port="$(ask "目标端口(可多个，空格分隔)" "22 80 443 3306 6379")"
    echo ""
    for p in $port; do
        if timeout 3 bash -c "echo >/dev/tcp/$host/$p" 2>/dev/null; then
            done_msg "$host:$p 开放"
        else
            fail_msg "$host:$p 关闭或被过滤"
        fi
    done
}

# ---- 网络接口流量统计 ----
network_traffic() {
    header "网络接口流量统计"
    printf "  %-12s %12s %12s %12s %12s\n" "接口" "接收(KB)" "发送(KB)" "接收包" "发送包"
    printf "  %s\n" "----------------------------------------------------------------"
    while IFS=: read -r iface stats; do
        iface="$(echo "$iface" | xargs)"
        [ "$iface" = "lo" ] && continue
        local rx_bytes rx_packets tx_bytes tx_packets
        rx_bytes="$(echo "$stats" | awk '{print $1}')"
        rx_packets="$(echo "$stats" | awk '{print $3}')"
        tx_bytes="$(echo "$stats" | awk '{print $9}')"
        tx_packets="$(echo "$stats" | awk '{print $11}')"
        printf "  %-12s %12s %12s %12s %12s\n" "$iface" \
            "$((rx_bytes/1024))" "$((tx_bytes/1024))" "$rx_packets" "$tx_packets"
    done < <(grep -E '^[[:space:]]*(eth|ens|enp|wlan|wlx|bond|br|docker|veth)' /proc/net/dev 2>/dev/null)
}

# ---- 路由追踪 ----
network_traceroute() {
    header "路由追踪"
    local target
    target="$(ask "目标地址" "baidu.com")"
    if has_cmd traceroute; then
        traceroute "$target"
    elif has_cmd tracepath; then
        tracepath "$target"
    else
        warn "未安装 traceroute，尝试安装..."
        pkg_install traceroute 2>/dev/null && traceroute "$target"
    fi
}

# ---- 网速测试 ----
network_speedtest() {
    header "网速测试"
    if has_cmd speedtest; then
        speedtest
    elif has_cmd curl; then
        step "通过下载测试(使用 Cloudflare 测速文件)..."
        local url="https://speed.cloudflare.com/__down?bytes=100000000"
        local result
        result="$(curl -o /dev/null -s -w "下载速度: %{speed_download} bytes/s\n总耗时: %{time_total}s\n下载量: %{size_download} bytes\n" "$url" 2>/dev/null)"
        echo "$result" | sed 's/^/  /'
        local speed
        speed="$(echo "$result" | grep '下载速度' | awk '{print $2}')"
        if [ -n "$speed" ]; then
            echo ""
            echo "  下载速度: $(awk "BEGIN {printf \"%.2f MB/s\", $speed/1024/1024}")"
        fi
    else
        warn "需要 curl 或 speedtest-cli"
    fi
}

# ---- TCP 连接状态统计 ----
network_connections() {
    header "TCP 连接状态统计"
    if has_cmd ss; then
        ss -ant 2>/dev/null | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn | \
            awk '{printf "  %-15s %s\n", $2, $1}'
    else
        netstat -ant 2>/dev/null | awk 'NR>2 {print $6}' | sort | uniq -c | sort -rn | \
            awk '{printf "  %-15s %s\n", $2, $1}'
    fi
    echo ""
    section "连接数最多的远程 IP TOP 10"
    if has_cmd ss; then
        ss -ant 2>/dev/null | awk 'NR>1 {print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
    fi
}

network_menu() {
    while true; do
        header "网络诊断"
        echo "  1) 连通性测试 (ping)"
        echo "  2) DNS 诊断"
        echo "  3) 端口检测"
        echo "  4) 接口流量统计"
        echo "  5) TCP 连接统计"
        echo "  6) 路由追踪"
        echo "  7) 网速测试"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) network_ping_test; pause ;;
            2) network_dns; pause ;;
            3) network_port_check; pause ;;
            4) network_traffic; pause ;;
            5) network_connections; pause ;;
            6) network_traceroute; pause ;;
            7) network_speedtest; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    network_menu
fi
