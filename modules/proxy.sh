#!/usr/bin/env bash
# ============================================================
#  proxy.sh - 网络代理与工具
#  Xray / 3X-UI / AdGuard Home / WireGuard
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# ============================================================
#  Xray
# ============================================================
proxy_xray() {
    require_root || return 1
    header "安装 Xray"
    echo "  主流代理核心，支持 VMess/VLESS/Trojan/Shadowsocks"
    echo ""
    if has_cmd xray; then
        warn "Xray 已安装: $(xray version 2>/dev/null | head -1)"
    fi
    echo "  1) 官方脚本安装"
    echo "  2) 安装并配置 VLESS+Reality"
    local choice
    choice="$(ask "选择" "1")"
    if ! has_cmd curl; then pkg_install curl; fi
    if [ "$choice" = "1" ]; then
        step "运行 Xray 官方安装脚本"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    else
        step "运行 3X-UI 安装脚本(含 Reality 配置)"
        bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    fi
    if has_cmd xray; then
        success "Xray 安装完成: $(xray version 2>/dev/null | head -1)"
        echo "  配置: /usr/local/etc/xray/config.json"
        echo "  管理: systemctl status xray"
    fi
}

# ============================================================
#  3X-UI
# ============================================================
proxy_3xui() {
    require_root || return 1
    header "安装 3X-UI"
    echo "  Xray Web 管理面板，支持多用户/流量统计/Reality"
    echo ""
    if ! has_cmd curl; then pkg_install curl; fi
    step "运行 3X-UI 官方安装脚本"
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    echo ""
    info "安装完成后执行 x-ui 进入管理菜单"
    info "面板默认端口: 2053 (安装时可修改)"
}

# ============================================================
#  AdGuard Home
# ============================================================
proxy_adguard() {
    require_root || return 1
    header "安装 AdGuard Home"
    echo "  全网广告过滤 + 私有 DNS 服务器"
    echo ""
    if ! has_cmd curl; then pkg_install curl; fi
    step "运行 AdGuard Home 官方安装脚本"
    curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
    if has_cmd AdGuardHome; then
        success "AdGuard Home 安装完成"
        echo "  管理面板: http://$(hostname -I 2>/dev/null | awk '{print $1}'):3000"
        echo "  DNS 端口: 53"
        echo "  管理: AdGuardHome -s status"
    fi
}

# ============================================================
#  WireGuard
# ============================================================
proxy_wireguard() {
    require_root || return 1
    header "安装 WireGuard VPN"
    echo "  轻量高速 VPN，比 OpenVPN 更快更简单"
    echo ""
    if ! has_cmd curl; then pkg_install curl; fi
    echo "  1) angristan/wireguard-install (交互式)"
    echo "  2) Nyr/wireguard-install (轻量)"
    local choice
    choice="$(ask "选择脚本" "1")"
    if [ "$choice" = "1" ]; then
        step "下载并运行 wireguard-install"
        curl -O https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh
        chmod +x wireguard-install.sh
        ./wireguard-install.sh
    else
        step "下载并运行 wg-install"
        curl -O https://raw.githubusercontent.com/Nyr/wireguard-install/master/wireguard-install.sh
        chmod +x wireguard-install.sh
        ./wireguard-install.sh
    fi
    success "WireGuard 安装完成"
    echo "  管理: ./wireguard-install.sh (添加/删除用户)"
    echo "  状态: wg show"
}

# ============================================================
#  菜单
# ============================================================
proxy_menu() {
    while true; do
        header "网络代理与工具"
        echo "  1) Xray (代理核心)"
        echo "  2) 3X-UI (Xray管理面板)"
        echo "  3) AdGuard Home (广告过滤+DNS)"
        echo "  4) WireGuard (VPN)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) proxy_xray; pause ;;
            2) proxy_3xui; pause ;;
            3) proxy_adguard; pause ;;
            4) proxy_wireguard; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    proxy_menu
fi
