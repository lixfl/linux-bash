#!/usr/bin/env bash
# ============================================================
#  terminal.sh - 终端美化与环境配置
#  功能：Zsh + Oh My Zsh + Powerlevel10k、插件、动态MOTD、中文Locale
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# ---- 安装 Zsh + Oh My Zsh + Powerlevel10k ----
terminal_zsh() {
    header "安装 Zsh + Oh My Zsh + Powerlevel10k"

    # 安装 zsh
    if ! has_cmd zsh; then
        step "安装 zsh"
        pkg_install zsh || { error "zsh 安装失败"; return 1; }
    else
        done_msg "zsh 已安装: $(zsh --version)"
    fi

    # 安装 git（OMZ 需要）
    has_cmd git || pkg_install git

    # 安装 Oh My Zsh
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        step "安装 Oh My Zsh"
        # 非交互式安装
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>/dev/null
        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            # 国内镜像备选
            warn "GitHub 安装失败，尝试 Gitee 镜像..."
            git clone https://gitee.com/mirrors/oh-my-zsh.git "$HOME/.oh-my-zsh" 2>/dev/null
            cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
        fi
    else
        done_msg "Oh My Zsh 已安装"
    fi

    # 安装 Powerlevel10k 主题
    local p10k_dir="$ZSH_CUSTOM/themes/powerlevel10k"
    if [ ! -d "$p10k_dir" ]; then
        step "安装 Powerlevel10k 主题"
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir" 2>/dev/null || \
        git clone --depth=1 https://gitee.com/romkatv/powerlevel10k.git "$p10k_dir" 2>/dev/null
    fi

    # 安装插件
    step "安装 zsh 插件"
    local plugins_dir="$ZSH_CUSTOM/plugins"
    mkdir -p "$plugins_dir"
    [ ! -d "$plugins_dir/zsh-autosuggestions" ] && \
        git clone https://github.com/zsh-users/zsh-autosuggestions "$plugins_dir/zsh-autosuggestions" 2>/dev/null
    [ ! -d "$plugins_dir/zsh-syntax-highlighting" ] && \
        git clone https://github.com/zsh-users/zsh-syntax-highlighting "$plugins_dir/zsh-syntax-highlighting" 2>/dev/null
    [ ! -d "$plugins_dir/zsh-completions" ] && \
        git clone https://github.com/zsh-users/zsh-completions "$plugins_dir/zsh-completions" 2>/dev/null

    # 配置 .zshrc
    step "配置 .zshrc"
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] && cp "$zshrc" "${zshrc}.bak.$(date +%Y%m%d_%H%M%S)"

    # 修改主题
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$zshrc"
    # 修改插件
    sed -i 's/^plugins=(.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)/' "$zshrc"

    # 添加常用别名和配置
    cat >> "$zshrc" <<'EOF'

# === 自定义配置 ===
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias hist='history | grep'

# 自动补全大小写不敏感
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# 历史记录
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY
EOF

    # 生成 p10k 配置（简洁版）
    cat > "$HOME/.p10k.zsh" <<'EOF'
# Powerlevel10k 简洁配置
typeset -g POWERLEVEL9K_MODE='nerdfont-complete'
typeset -g POWERLEVEL9K_PROMPT_ON_NEWLINE=true
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon dir vcs status)
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(background_jobs time)
typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
EOF

    # 设置默认 shell
    if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(which zsh)" ]; then
        if confirm "将 zsh 设为默认 shell?" "y"; then
            chsh -s "$(which zsh)" "$USER" 2>/dev/null && done_msg "默认 shell 已改为 zsh，重新登录生效"
        fi
    fi

    success "Zsh 环境配置完成！重新登录或执行 zsh 生效"
    warn "建议安装 Nerd Font 字体以正常显示 Powerlevel10k 图标"
}

# ---- 动态 MOTD ----
terminal_motd() {
    require_root || return 1
    header "动态 MOTD (登录欢迎信息)"

    local motd_dir="/etc/update-motd.d"
    mkdir -p "$motd_dir"

    # 禁用静态 motd
    [ -f /etc/motd ] && mv /etc/motd /etc/motd.bak 2>/dev/null

    # 10-系统信息
    cat > "$motd_dir/10-sysinfo" <<'EOF'
#!/bin/bash
echo "  系统: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "  内核: $(uname -r) | 架构: $(uname -m)"
echo "  运行: $(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
echo "  负载: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
echo "  CPU: $(nproc) 核 | 内存: $(free -h | awk '/^Mem:/ {print $2}')"
echo "  磁盘: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
echo "  IP: $(hostname -I 2>/dev/null | awk '{print $1}')"
EOF
    chmod +x "$motd_dir/10-sysinfo"

    # 20-服务状态
    cat > "$motd_dir/20-services" <<'EOF'
#!/bin/bash
echo ""
echo "  服务状态:"
for svc in ssh docker nginx mysql redis; do
    if systemctl is-active "$svc" &>/dev/null; then
        echo "    ✓ $svc 运行中"
    fi
done
EOF
    chmod +x "$motd_dir/20-services"

    # 00-头部 banner
    cat > "$motd_dir/00-header" <<'EOF'
#!/bin/bash
echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║   $(hostname) | $(date '+%Y-%m-%d %H:%M')   ║"
echo "  ╚══════════════════════════════════════╝"
echo ""
EOF
    chmod +x "$motd_dir/00-header"

    # 确保 PAM 调用 motd
    if [ -f /etc/pam.d/sshd ]; then
        grep -q 'pam_motd.so' /etc/pam.d/sshd || \
            sed -i '/session.*pam_loginuid/a session    optional     pam_motd.so motd=/run/motd.dynamic' /etc/pam.d/sshd 2>/dev/null
    fi

    success "动态 MOTD 已配置，下次登录生效"
    echo ""
    echo "  预览:"
    run-parts "$motd_dir" 2>/dev/null | sed 's/^/  /'
}

# ---- 中文 Locale ----
terminal_locale() {
    require_root || return 1
    header "中文 Locale 配置"

    if [ "$OS_FAMILY" = "debian" ]; then
        pkg_install locales
        sed -i 's/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
        locale-gen
        update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
    elif [ "$OS_FAMILY" = "rhel" ]; then
        pkg_install glibc-langpack-zh 2>/dev/null
        localectl set-locale LANG=zh_CN.UTF-8 2>/dev/null
    fi

    echo "  当前 LANG: ${LANG:-N/A}"
    echo "  可用中文 locale:"
    locale -a 2>/dev/null | grep -i zh_CN | sed 's/^/    /'
    success "中文 locale 配置完成，重新登录生效"
}

# ---- 一键终端美化 ----
terminal_all() {
    terminal_zsh
    echo ""
    terminal_motd
    echo ""
    if confirm "配置中文 locale?" "y"; then
        terminal_locale
    fi
    success "终端美化全部完成！"
}

# ---- 模块菜单 ----
terminal_menu() {
    while true; do
        header "终端美化与环境"
        echo "  1) 安装 Zsh + Oh My Zsh + Powerlevel10k"
        echo "  2) 配置动态 MOTD"
        echo "  3) 中文 Locale 配置"
        echo "  4) 一键全部配置"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) terminal_zsh; pause ;;
            2) terminal_motd; pause ;;
            3) terminal_locale; pause ;;
            4) terminal_all; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    terminal_menu
fi
