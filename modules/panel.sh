#!/usr/bin/env bash
# ============================================================
#  panel.sh - 系统面板与邮件
#  宝塔面板 / Webmin / SMTP 邮件发送
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# ============================================================
#  宝塔面板
# ============================================================
panel_bt() {
    require_root || return 1
    header "安装宝塔面板"
    echo "  国内服务器常用的 Web 管理面板"
    if [ -f "/www/server/panel/install/install_soft.sh" ]; then
        success "宝塔面板已安装"
        /etc/init.d/bt default 2>/dev/null
        return 0
    fi
    echo ""
    echo "  1) 宝塔国际版 (aapanel，海外推荐)"
    echo "  2) 宝塔国内版 (bt.cn)"
    local opt
    opt="$(ask "选择" "1")"
    if [ "$opt" = "1" ]; then
        step "安装 aapanel"
        URL=https://www.aapanel.com/script/install_6.0_en.sh && if [ -f /usr/bin/curl ];then curl -ksSO "$URL" ;else wget --no-check-certificate -O install_6.0_en.sh "$URL";fi
        bash install_6.0_en.sh aapanel
    else
        step "安装宝塔面板"
        wget -O install.sh https://download.bt.cn/install/install_lts.sh
        echo y | bash install.sh ed8484bec
    fi
    success "宝塔面板安装完成"
    echo "  查看面板信息: /etc/init.d/bt default"
}

# ============================================================
#  Webmin
# ============================================================
panel_webmin() {
    require_root || return 1
    header "安装 Webmin"
    echo "  通用 Web 系统管理工具"
    if has_cmd webmin; then
        success "Webmin 已安装"
        echo "  访问: https://$(hostname -I 2>/dev/null|awk '{print $1}'):10000"
        return 0
    fi
    step "安装 Webmin"
    if [ "$PKG_MANAGER" = "apt" ]; then
        curl -fsSL https://www.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg 2>/dev/null
        echo "deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list
        apt-get update -qq && apt-get install -y webmin
    elif [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
        cat > /etc/yum.repos.d/webmin.repo <<EOF
[Webmin]
name=Webmin Distribution Neutral
baseurl=https://download.webmin.com/download/yum
enabled=1
gpgcheck=1
gpgkey=https://www.webmin.com/jcameron-key.asc
EOF
        $PKG_MANAGER install -y webmin
    else
        curl -fsSL "https://github.com/webmin/webmin/releases/latest/download/webmin-current.tar.gz" -o /tmp/webmin.tar.gz
        tar -xzf /tmp/webmin.tar.gz -C /opt
        cd /opt/webmin-* && ./setup.sh /usr/local/webmin
    fi
    success "Webmin 安装完成"
    echo "  访问: https://$(hostname -I 2>/dev/null|awk '{print $1}'):10000"
    echo "  使用系统 root 账号登录"
}

# ============================================================
#  SMTP 邮件发送配置
# ============================================================
panel_smtp() {
    header "配置 SMTP 邮件发送"
    echo "  配置服务器发送邮件（告警/通知用）"
    local smtp_host smtp_port smtp_user smtp_pass from_addr
    smtp_host="$(ask "SMTP服务器 (如 smtp.qq.com)" "smtp.qq.com")"
    smtp_port="$(ask "端口" "465")"
    smtp_user="$(ask "邮箱账号" "")"
    smtp_pass="$(ask "授权码/密码" "")"
    from_addr="$(ask "发件人显示" "$smtp_user")"
    [ -z "$smtp_user" ] && { warn "账号不能为空"; return 1; }

    step "安装 msmtp + mailutils"
    pkg_install msmtp mailutils 2>/dev/null || pkg_install msmtp bsd-mailx

    step "生成配置"
    cat > /etc/msmtprc <<EOF
account default
host $smtp_host
port $smtp_port
from $from_addr
user $smtp_user
password $smtp_pass
auth on
tls on
tls_starttls off
tls_certcheck off
logfile /var/log/msmtp.log
EOF
    chmod 600 /etc/msmtprc
    echo "set mta=/usr/bin/msmtp" > /etc/mail.rc 2>/dev/null

    success "SMTP 配置完成"
    echo "  配置文件: /etc/msmtprc"
    echo "  发送测试: echo '测试邮件' | mail -s '主题' 收件人邮箱"
    if confirm "发送测试邮件?" "n"; then
        local test_to
        test_to="$(ask "收件人邮箱" "")"
        [ -n "$test_to" ] && echo "来自 $(hostname) 的测试邮件 $(date)" | mail -s "服务器邮件测试" "$test_to" && success "测试邮件已发送"
    fi
}

# ============================================================
#  菜单
# ============================================================
panel_menu() {
    while true; do
        header "系统面板与邮件"
        echo "  1) 宝塔面板 (bt.cn/aapanel)"
        echo "  2) Webmin (通用系统管理)"
        echo "  3) SMTP 邮件发送配置"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) panel_bt; pause ;;
            2) panel_webmin; pause ;;
            3) panel_smtp; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    panel_menu
fi
