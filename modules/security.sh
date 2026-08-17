#!/usr/bin/env bash
# ============================================================
#  security.sh - 安全加固
#  功能：SSH 加固、防火墙、fail2ban、密码策略、安全审计
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SSH_CONFIG="/etc/ssh/sshd_config"

# ---- SSH 安全加固 ----
security_ssh() {
    require_root || return 1
    header "SSH 安全加固"

    [ -f "$SSH_CONFIG" ] || { error "未找到 sshd 配置: $SSH_CONFIG"; return 1; }
    safe_backup_file "$SSH_CONFIG"

    local port permit_root pwd_auth
    port="$(ask "SSH 端口" "22")"
    permit_root="$(ask "禁止 root 登录? (y/n)" "y")"
    pwd_auth="$(ask "禁止密码登录(仅密钥)? (y/n)" "n")"

    if [ "$pwd_auth" = "y" ]; then
        warn "将禁用密码登录，请确保已配置 SSH 密钥，否则会被锁在外面！"
        if ! confirm "确认继续?" "n"; then return 1; fi
    fi

    step "修改 sshd_config"
    # 清理旧配置
    sed -i '/^#\?Port /d; /^#\?PermitRootLogin /d; /^#\?PasswordAuthentication /d; /^#\?PubkeyAuthentication /d; /^#\?MaxAuthTries /d; /^#\?ClientAliveInterval /d; /^#\?ClientAliveCountMax /d; /^#\?X11Forwarding /d' "$SSH_CONFIG"

    cat >> "$SSH_CONFIG" <<EOF

# === 安全加固 $(date +%Y-%m-%d) ===
Port $port
PermitRootLogin $([ "$permit_root" = "y" ] && echo no || echo yes)
PasswordAuthentication $([ "$pwd_auth" = "y" ] && echo no || echo yes)
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
EOF

    step "验证配置语法"
    if sshd -t 2>/dev/null; then
        done_msg "配置语法正确"
        svc_restart sshd 2>/dev/null || svc_restart ssh 2>/dev/null
        success "SSH 加固完成，新端口: $port"
        warn "请新开一个 SSH 连接验证后再关闭当前会话！"
    else
        error "配置语法错误，已保留备份，请手动检查"
        return 1
    fi
}

# ---- 防火墙配置 ----
security_firewall() {
    require_root || return 1
    header "防火墙配置"

    # 检测可用防火墙
    if has_cmd ufw; then
        _fw_ufw
    elif has_cmd firewall-cmd; then
        _fw_firewalld
    elif has_cmd iptables; then
        _fw_iptables
    else
        warn "未找到防火墙工具，尝试安装 ufw..."
        pkg_install ufw && _fw_ufw
    fi
}

_fw_ufw() {
    echo "  使用 ufw"
    echo ""
    echo "  1) 查看状态"
    echo "  2) 启用防火墙(默认拒绝)"
    echo "  3) 开放端口"
    echo "  4) 关闭端口"
    echo "  5) 禁用防火墙"
    local opt
    opt="$(ask "请选择" "1")"
    case "$opt" in
        1) ufw status verbose ;;
        2)
            local ssh_port
            ssh_port="$(ask "先放行 SSH 端口" "22")"
            ufw allow "$ssh_port/tcp"
            ufw --force enable
            success "防火墙已启用，SSH 端口 $ssh_port 已放行"
            ;;
        3)
            local p
            p="$(ask "要开放的端口(如 80,443 或 8080/tcp)" "")"
            [ -n "$p" ] && ufw allow "$p" && success "已放行: $p"
            ;;
        4)
            local p
            p="$(ask "要关闭的端口" "")"
            [ -n "$p" ] && ufw delete allow "$p" && success "已关闭: $p"
            ;;
        5) ufw disable; warn "防火墙已禁用" ;;
    esac
}

_fw_firewalld() {
    echo "  使用 firewalld"
    echo ""
    echo "  1) 查看状态"
    echo "  2) 开放端口"
    echo "  3) 关闭端口"
    echo "  4) 列出开放端口"
    local opt
    opt="$(ask "请选择" "1")"
    case "$opt" in
        1) firewall-cmd --state; firewall-cmd --list-all ;;
        2)
            local p
            p="$(ask "要开放的端口(如 80/tcp)" "")"
            [ -n "$p" ] && firewall-cmd --permanent --add-port="$p" && firewall-cmd --reload && success "已放行: $p"
            ;;
        3)
            local p
            p="$(ask "要关闭的端口" "")"
            [ -n "$p" ] && firewall-cmd --permanent --remove-port="$p" && firewall-cmd --reload && success "已关闭: $p"
            ;;
        4) firewall-cmd --list-ports ;;
    esac
}

_fw_iptables() {
    echo "  使用 iptables"
    echo ""
    echo "  1) 查看规则"
    echo "  2) 开放端口"
    echo "  3) 丢弃指定端口"
    local opt
    opt="$(ask "请选择" "1")"
    case "$opt" in
        1) iptables -L -n --line-numbers ;;
        2)
            local p
            p="$(ask "要开放的端口" "")"
            [ -n "$p" ] && iptables -A INPUT -p tcp --dport "$p" -j ACCEPT && success "已放行 TCP $p"
            ;;
        3)
            local p
            p="$(ask "要丢弃的端口" "")"
            [ -n "$p" ] && iptables -A INPUT -p tcp --dport "$p" -j DROP && success "已丢弃 TCP $p"
            ;;
    esac
}

# ---- fail2ban 安装配置 ----
security_fail2ban() {
    require_root || return 1
    header "Fail2ban 防爆破"

    if ! has_cmd fail2ban-client; then
        step "安装 fail2ban"
        pkg_install fail2ban || { error "安装失败"; return 1; }
    fi

    local jail="/etc/fail2ban/jail.local"
    safe_backup_file "$jail" 2>/dev/null

    local maxretry bantime findtime
    maxretry="$(ask "最大尝试次数" "5")"
    bantime="$(ask "封禁时长(秒)" "3600")"
    findtime="$(ask "检测窗口(秒)" "600")"

    cat > "$jail" <<EOF
[DEFAULT]
bantime = $bantime
findtime = $findtime
maxretry = $maxretry
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = $maxretry
EOF

    svc_enable fail2ban 2>/dev/null
    svc_restart fail2ban 2>/dev/null
    sleep 1
    success "fail2ban 已配置并启动"
    fail2ban-client status sshd 2>/dev/null | sed 's/^/  /'
}

# ---- 密码策略 ----
security_password_policy() {
    require_root || return 1
    header "密码策略加固"

    if [ "$OS_FAMILY" = "debian" ]; then
        pkg_install libpam-pwquality 2>/dev/null
        local conf="/etc/security/pwquality.conf"
        safe_backup_file "$conf" 2>/dev/null
        cat > "$conf" <<EOF
minlen = 12
minclass = 3
maxrepeat = 3
ucredit = -1
lcredit = -1
dcredit = -1
ocredit = -1
EOF
        done_msg "密码策略已设置: 最小12位，需包含大小写数字特殊字符"
    elif [ "$OS_FAMILY" = "rhel" ]; then
        pkg_install libpwquality 2>/dev/null
        authconfig --passminlen=12 --passminclass=3 --update 2>/dev/null
        done_msg "密码策略已更新"
    else
        warn "当前系统家族 $OS_FAMILY 暂不支持自动配置"
    fi

    # 设置密码过期策略
    local login_defs="/etc/login.defs"
    if [ -f "$login_defs" ]; then
        sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' "$login_defs"
        sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' "$login_defs"
        sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' "$login_defs"
        done_msg "密码有效期: 90天，提前7天提醒"
    fi
}

# ---- 安全审计 ----
security_audit() {
    header "安全审计"
    local issues=0

    section "用户检查"
    # UID 0 的非 root 用户
    local uid0
    uid0="$(awk -F: '$3==0 && $1!="root" {print $1}' /etc/passwd)"
    if [ -n "$uid0" ]; then
        warn "发现 UID=0 的非 root 用户: $uid0"
        issues=$((issues+1))
    else
        done_msg "无异常 UID=0 用户"
    fi

    # 空密码用户
    local empty_pw
    empty_pw="$(awk -F: '($2=="") {print $1}' /etc/shadow 2>/dev/null)"
    if [ -n "$empty_pw" ]; then
        warn "发现空密码用户: $empty_pw"
        issues=$((issues+1))
    else
        done_msg "无空密码用户"
    fi

    section "SSH 配置检查"
    if grep -qi "^PermitRootLogin yes" "$SSH_CONFIG" 2>/dev/null; then
        warn "SSH 允许 root 直接登录"
        issues=$((issues+1))
    else
        done_msg "SSH root 登录已禁用或未显式开启"
    fi
    if grep -qi "^PasswordAuthentication yes" "$SSH_CONFIG" 2>/dev/null; then
        warn "SSH 允许密码登录(建议改用密钥)"
        issues=$((issues+1))
    else
        done_msg "SSH 密码登录已禁用"
    fi

    section "危险 SUID 文件"
    local suid_files
    suid_files="$(find / -perm -4000 -type f 2>/dev/null | head -10)"
    if [ -n "$suid_files" ]; then
        echo "$suid_files" | sed 's/^/  /'
        warn "以上为 SUID 文件，请确认是否都为预期"
    fi

    section "最近失败登录"
    local failed
    if [ -f /var/log/auth.log ]; then
        failed="$(grep -c 'Failed password' /var/log/auth.log 2>/dev/null)"
    elif [ -f /var/log/secure ]; then
        failed="$(grep -c 'Failed password' /var/log/secure 2>/dev/null)"
    else
        failed="N/A"
    fi
    echo "  失败登录次数: $failed"

    echo ""
    if [ "$issues" -eq 0 ]; then
        success "未发现明显安全问题"
    else
        error "共发现 $issues 个安全风险项"
    fi
}

# ---- 一键安全加固 ----
security_auto_harden() {
    require_root || return 1
    header "一键安全加固"
    warn "将执行以下操作:"
    echo "  1. SSH 加固(改端口、禁root、限制尝试次数)"
    echo "  2. 安装并配置 fail2ban"
    echo "  3. 设置密码策略"
    echo "  4. 配置防火墙(放行 SSH)"
    echo ""
    if ! confirm "确认执行?" "n"; then return 0; fi

    security_ssh
    echo ""
    security_fail2ban
    echo ""
    security_password_policy
    echo ""
    security_firewall
    echo ""
    success "一键加固完成，建议运行安全审计确认"
}


# ============================================================
#  SSH 密钥管理
# ============================================================
security_ssh_key() {
    header "SSH 密钥管理"
    echo "  1) 生成 SSH 密钥对"
    echo "  2) 查看公钥"
    echo "  3) 禁用密码登录 (仅密钥)"
    echo "  4) 启用密码登录"
    echo "  0) 返回"
    local opt
    opt="$(ask "选择" "1")"
    case "$opt" in
        1)
            local key_type key_name
            key_type="$(ask "密钥类型 (ed25519/rsa)" "ed25519")"
            key_name="$(ask "密钥文件名" "id_${key_type}")"
            ssh-keygen -t "$key_type" -f "$HOME/.ssh/$key_name" -N ""
            success "密钥已生成: $HOME/.ssh/$key_name"
            echo "  公钥: $(cat $HOME/.ssh/${key_name}.pub)"
            ;;
        2)
            echo "  公钥列表:"
            ls -1 "$HOME/.ssh/"*.pub 2>/dev/null | while read f; do
                echo "  --- $(basename $f) ---"
                cat "$f"
            done
            ;;
        3)
            require_root || return 1
            warn "将禁用 SSH 密码登录，确保已配置密钥并测试通过！"
            confirm "确认禁用密码登录?" "n" || return 0
            sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
            sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
            svc_restart sshd 2>/dev/null || svc_restart ssh 2>/dev/null
            success "已禁用密码登录，仅允许密钥登录"
            ;;
        4)
            require_root || return 1
            sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
            svc_restart sshd 2>/dev/null || svc_restart ssh 2>/dev/null
            success "已启用密码登录"
            ;;
        0) return 0 ;;
        *) warn "无效选项" ;;
    esac
}

security_menu() {
    while true; do
        header "安全加固"
        echo "  1) SSH 安全加固"
        echo "  2) 防火墙配置"
        echo "  3) Fail2ban 防爆破"
        echo "  4) 密码策略"
        echo "  5) 安全审计"
        echo "  6) 一键安全加固"
        echo "  7) SSH 密钥管理"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) security_ssh; pause ;;
            2) security_firewall; pause ;;
            3) security_fail2ban; pause ;;
            4) security_password_policy; pause ;;
            5) security_audit; pause ;;
            6) security_auto_harden; pause ;;
            7) security_ssh_key; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    security_menu
fi
