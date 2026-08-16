#!/usr/bin/env bash
# ============================================================
#  autoupdate.sh - 自动系统更新
#  功能：立即更新、定时自动更新、无人值守升级、自动重启配置
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

AUTOUP_SCRIPT="/usr/local/bin/system-autoupdate.sh"
AUTOUP_LOG="/var/log/system-autoupdate.log"
AUTOUP_CRON="/etc/cron.d/system-autoupdate"

# ---- 立即更新系统 ----
autoupdate_now() {
    require_root || return 1
    header "立即更新系统"
    echo "  包管理器: $PKG_MANAGER"
    echo ""
    if confirm "确认执行系统更新?" "y"; then
        pkg_update
        success "系统更新完成"
        echo ""
        # 检查是否需要重启
        if [ -f /var/run/reboot-required ]; then
            warn "更新后需要重启系统！"
            cat /var/run/reboot-required 2>/dev/null | sed 's/^/  /'
            if confirm "立即重启?" "n"; then
                reboot
            fi
        fi
    fi
}

# ---- 生成自动更新脚本 ----
_gen_autoup_script() {
    local auto_reboot="${1:-0}"
    cat > "$AUTOUP_SCRIPT" <<EOF
#!/bin/bash
# 自动系统更新脚本 - 由 server-toolkit 生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

LOG="$AUTOUP_LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始自动更新" >> "\$LOG"

case "$PKG_MANAGER" in
    apt)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >> "\$LOG" 2>&1
        apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >> "\$LOG" 2>&1
        apt-get autoremove -y >> "\$LOG" 2>&1
        apt-get autoclean >> "\$LOG" 2>&1
        ;;
    dnf|yum)
        dnf upgrade -y >> "\$LOG" 2>&1 || yum update -y >> "\$LOG" 2>&1
        ;;
    apk)
        apk update >> "\$LOG" 2>&1
        apk upgrade >> "\$LOG" 2>&1
        ;;
    pacman)
        pacman -Syu --noconfirm >> "\$LOG" 2>&1
        ;;
esac

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 更新完成" >> "\$LOG"

# 自动重启
if [ "$auto_reboot" = "1" ]; then
    if [ -f /var/run/reboot-required ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 需要重启，30秒后重启" >> "\$LOG"
        sleep 30
        reboot
    fi
fi
EOF
    chmod +x "$AUTOUP_SCRIPT"
}

# ---- 配置定时自动更新 ----
autoupdate_setup() {
    require_root || return 1
    header "配置定时自动更新"

    echo "  1) 每天凌晨 3:00 更新"
    echo "  2) 每周日凌晨 3:00 更新"
    echo "  3) 每周一/四凌晨 3:00 更新"
    echo "  0) 取消"
    local freq
    freq="$(ask "选择更新频率" "2")"

    local cron_expr=""
    case "$freq" in
        1) cron_expr="0 3 * * *" ;;
        2) cron_expr="0 3 * * 0" ;;
        3) cron_expr="0 3 * * 1,4" ;;
        0) return 0 ;;
        *) warn "无效选项"; return 1 ;;
    esac

    local auto_reboot=0
    if confirm "更新后如需重启是否自动重启?(建议关闭)" "n"; then
        auto_reboot=1
    fi

    step "生成更新脚本"
    _gen_autoup_script "$auto_reboot"

    step "配置定时任务"
    echo "$cron_expr root $AUTOUP_SCRIPT" > "$AUTOUP_CRON"
    chmod 644 "$AUTOUP_CRON"

    # 确保 cron 服务运行
    svc_enable cron 2>/dev/null || svc_enable crond 2>/dev/null
    svc_start cron 2>/dev/null || svc_start crond 2>/dev/null

    success "自动更新已配置"
    echo "  脚本: $AUTOUP_SCRIPT"
    echo "  日志: $AUTOUP_LOG"
    echo "  定时: $cron_expr"
    echo "  自动重启: $([ "$auto_reboot" = "1" ] && echo 开启 || echo 关闭)"
}

# ---- 查看自动更新状态 ----
autoupdate_status() {
    header "自动更新状态"
    if [ -f "$AUTOUP_CRON" ]; then
        echo "  定时任务: $(cat "$AUTOUP_CRON")"
    else
        warn "未配置自动更新"
    fi
    echo ""
    if [ -f "$AUTOUP_SCRIPT" ]; then
        echo "  更新脚本: 已存在"
    else
        echo "  更新脚本: 不存在"
    fi
    echo ""
    if [ -f "$AUTOUP_LOG" ]; then
        echo "  最近更新日志:"
        tail -10 "$AUTOUP_LOG" | sed 's/^/  /'
    else
        echo "  暂无更新日志"
    fi
}

# ---- 取消自动更新 ----
autoupdate_cancel() {
    require_root || return 1
    header "取消自动更新"
    if [ ! -f "$AUTOUP_CRON" ]; then
        warn "未配置自动更新"
        return 0
    fi
    if confirm "确认取消自动更新?" "y"; then
        rm -f "$AUTOUP_CRON" "$AUTOUP_SCRIPT"
        success "自动更新已取消"
    fi
}

# ---- Debian unattended-upgrades ----
autoupdate_unattended() {
    require_root || return 1
    [ "$OS_FAMILY" = "debian" ] || { warn "仅支持 Debian/Ubuntu"; return 1; }
    header "配置无人值守安全更新 (unattended-upgrades)"

    pkg_install unattended-upgrades apt-listchanges

    step "启用自动安全更新"
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    # 配置自动重启
    if confirm "需要重启时自动重启?" "n"; then
        local hour
        hour="$(ask "自动重启时间(小时, 0-23)" "3")"
        cat >> /etc/apt/apt.conf.d/50unattended-upgrades <<EOF

Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "$hour:00";
EOF
    fi

    success "无人值守安全更新已配置"
    echo "  仅自动安装安全更新，不会升级所有软件包"
}

# ---- 模块菜单 ----
autoupdate_menu() {
    while true; do
        header "自动系统更新"
        echo "  1) 立即更新系统"
        echo "  2) 配置定时自动更新"
        echo "  3) 查看自动更新状态"
        echo "  4) 取消自动更新"
        echo "  5) 无人值守安全更新 (Debian/Ubuntu)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) autoupdate_now; pause ;;
            2) autoupdate_setup; pause ;;
            3) autoupdate_status; pause ;;
            4) autoupdate_cancel; pause ;;
            5) autoupdate_unattended; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    autoupdate_menu
fi
