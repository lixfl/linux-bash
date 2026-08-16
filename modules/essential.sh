#!/usr/bin/env bash
# ============================================================
#  essential.sh - 一键完善系统环境
#  安装精简版系统缺少的基础工具，按类别分组，支持全装/自选
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# ============================================================
#  工具包定义（按类别），每种包管理器对应不同包名
# ============================================================

# 类别: 基础工具
PKG_BASE=(
    "curl" "wget" "git" "vim" "nano" "htop" "jq" "tree" "rsync" "sudo"
    "less" "which" "file" "findutils" "coreutils" "diffutils" "patch"
)

# 类别: 网络工具
PKG_NETWORK=(
    "net-tools" "dnsutils" "iputils-ping" "traceroute" "nmap" "tcpdump"
    "iftop" "nethogs" "iproute2" "bind9-host" "whois" "mtr"
)

# 类别: 压缩工具
PKG_ARCHIVE=(
    "zip" "unzip" "tar" "gzip" "bzip2" "xz-utils" "p7zip-full" "zstd" "arj" "cabextract"
)

# 类别: 编译开发
PKG_BUILD=(
    "build-essential" "gcc" "g++" "make" "cmake" "pkg-config" "autoconf"
    "automake" "libtool" "flex" "bison" "git-lfs"
)

# 类别: 系统监控
PKG_MONITOR=(
    "sysstat" "iotop" "glances" "lshw" "lsb-release" "procps" "psmisc"
    "lsof" "strace" "ltrace" "dstat" "acct"
)

# 类别: 文件系统
PKG_FS=(
    "lvm2" "xfsprogs" "ntfs-3g" "dosfstools" "e2fsprogs" "parted"
    "gdisk" "cryptsetup" "sshfs" "cifs-utils" "nfs-common"
)

# 类别: 终端工具
PKG_TERMINAL=(
    "tmux" "screen" "zsh" "bash-completion" "command-not-found"
    "neofetch" "bat" "fzf" "ripgrep" "fd-find"
)

# 类别: Python
PKG_PYTHON=(
    "python3" "python3-pip" "python3-venv" "python3-dev" "python3-setuptools"
    "python3-wheel" "python3-requests" "python3-yaml"
)

# 类别: 安全工具
PKG_SECURITY=(
    "ufw" "fail2ban" "openssl" "ca-certificates" "gnupg" "gnupg-agent"
    "dirmngr" "apt-transport-https" "software-properties-common" "cron" "logrotate"
)

# 类别: 数据库客户端
PKG_DBCLIENT=(
    "mysql-client" "postgresql-client" "redis-tools" "sqlite3"
)

# ============================================================
#  包名映射（不同发行版包名不同）
# ============================================================
_map_pkg() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        dnf|yum)
            case "$pkg" in
                dnsutils) echo "bind-utils" ;;
                iputils-ping) echo "iputils" ;;
                build-essential) echo "gcc gcc-c++ make" ;;
                python3-pip) echo "python3-pip" ;;
                python3-venv) echo "" ;;
                net-tools) echo "net-tools" ;;
                apt-transport-https) echo "" ;;
                software-properties-common) echo "" ;;
                nfs-common) echo "nfs-utils" ;;
                mysql-client) echo "mysql" ;;
                postgresql-client) echo "postgresql" ;;
                redis-tools) echo "redis" ;;
                p7zip-full) echo "p7zip p7zip-plugins" ;;
                bat) echo "bat" ;;
                fd-find) echo "fd-find" ;;
                command-not-found) echo "" ;;
                *) echo "$pkg" ;;
            esac
            ;;
        apk)
            case "$pkg" in
                build-essential) echo "build-base" ;;
                dnsutils) echo "bind-tools" ;;
                python3-pip) echo "py3-pip" ;;
                python3-venv) echo "" ;;
                net-tools) echo "net-tools" ;;
                apt-transport-https) echo "" ;;
                software-properties-common) echo "" ;;
                nfs-common) echo "nfs-utils" ;;
                p7zip-full) echo "p7zip" ;;
                mysql-client) echo "mariadb-client" ;;
                postgresql-client) echo "postgresql-client" ;;
                redis-tools) echo "redis" ;;
                glances) echo "glances" ;;
                bat) echo "bat" ;;
                fd-find) echo "fd" ;;
                command-not-found) echo "" ;;
                *) echo "$pkg" ;;
            esac
            ;;
        pacman)
            case "$pkg" in
                build-essential) echo "base-devel" ;;
                dnsutils) echo "bind" ;;
                python3-pip) echo "python-pip" ;;
                python3-venv) echo "" ;;
                net-tools) echo "net-tools" ;;
                apt-transport-https) echo "" ;;
                software-properties-common) echo "" ;;
                nfs-common) echo "nfs-utils" ;;
                mysql-client) echo "mariadb-clients" ;;
                postgresql-client) echo "postgresql" ;;
                redis-tools) echo "redis" ;;
                p7zip-full) echo "p7zip" ;;
                glances) echo "glances" ;;
                bat) echo "bat" ;;
                fd-find) echo "fd" ;;
                command-not-found) echo "pkgfile" ;;
                *) echo "$pkg" ;;
            esac
            ;;
        *)
            echo "$pkg"
            ;;
    esac
}

# ============================================================
#  安装一个类别的所有包
# ============================================================
_install_category() {
    local cat_name="$1"
    shift
    local pkgs=("$@")
    local to_install=()

    section "检查 [$cat_name] 类别"
    for pkg in "${pkgs[@]}"; do
        local mapped
        mapped="$(_map_pkg "$pkg")"
        [ -z "$mapped" ] && continue
        for p in $mapped; do
            # 检查是否已安装
            if _is_installed "$p"; then
                debug "  已安装: $p"
            else
                to_install+=("$p")
            fi
        done
    done

    if [ ${#to_install[@]} -eq 0 ]; then
        done_msg "[$cat_name] 全部已安装"
        return 0
    fi

    echo "  待安装 (${#to_install[@]}): ${to_install[*]}"
    echo ""
    pkg_install "${to_install[@]}" && done_msg "[$cat_name] 安装完成" || fail_msg "[$cat_name] 部分安装失败"
}

# 检查包是否已安装
_is_installed() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        apt) dpkg -s "$pkg" &>/dev/null ;;
        dnf|yum) rpm -q "$pkg" &>/dev/null ;;
        apk) apk info -e "$pkg" &>/dev/null ;;
        pacman) pacman -Q "$pkg" &>/dev/null ;;
        *) return 1 ;;
    esac
}

# ============================================================
#  主功能：一键全装
# ============================================================
essential_all() {
    require_root || return 1
    header "一键完善系统环境"
    echo "  当前系统: $OS_PRETTY"
    echo "  包管理器: $PKG_MANAGER"
    echo ""
    echo "  将安装以下 9 个类别的工具:"
    echo "    1. 基础工具 (curl/wget/git/vim/htop/jq/tree...)"
    echo "    2. 网络工具 (net-tools/dnsutils/nmap/tcpdump...)"
    echo "    3. 压缩工具 (zip/unzip/xz/p7zip/zstd...)"
    echo "    4. 编译开发 (build-essential/gcc/cmake...)"
    echo "    5. 系统监控 (sysstat/iotop/lsof/strace...)"
    echo "    6. 文件系统 (lvm2/xfsprogs/ntfs-3g/parted...)"
    echo "    7. 终端工具 (tmux/zsh/bash-completion...)"
    echo "    8. Python 环境 (python3/pip/venv...)"
    echo "    9. 安全与系统 (ufw/fail2ban/cron/logrotate...)"
    echo "   10. 数据库客户端 (mysql/postgres/redis/sqlite)"
    echo ""

    if ! confirm "确认一键安装全部?" "y"; then
        warn "已取消，可选择分类安装"
        return 0
    fi

    echo ""
    step "更新软件源..."
    case "$PKG_MANAGER" in
        apt) apt-get update -qq ;;
        dnf|yum) dnf makecache 2>/dev/null || yum makecache ;;
        apk) apk update ;;
        pacman) pacman -Syy --noconfirm ;;
    esac

    _install_category "基础工具" "${PKG_BASE[@]}"
    _install_category "网络工具" "${PKG_NETWORK[@]}"
    _install_category "压缩工具" "${PKG_ARCHIVE[@]}"
    _install_category "编译开发" "${PKG_BUILD[@]}"
    _install_category "系统监控" "${PKG_MONITOR[@]}"
    _install_category "文件系统" "${PKG_FS[@]}"
    _install_category "终端工具" "${PKG_TERMINAL[@]}"
    _install_category "Python环境" "${PKG_PYTHON[@]}"
    _install_category "安全系统" "${PKG_SECURITY[@]}"
    _install_category "数据库客户端" "${PKG_DBCLIENT[@]}"

    echo ""
    success "系统环境完善完成！"
    echo ""
    echo "  安装的关键命令验证:"
    for cmd in curl wget git vim htop jq tree gcc make python3 tmux zip unzip; do
        if has_cmd "$cmd"; then
            printf "    %-12s ✓\n" "$cmd"
        else
            printf "    %-12s ✗\n" "$cmd"
        fi
    done
}

# ============================================================
#  分类选择安装
# ============================================================
essential_select() {
    require_root || return 1
    while true; do
        header "分类安装基础工具"
        echo "  1) 基础工具 (curl/wget/git/vim/htop/jq/tree/rsync...)"
        echo "  2) 网络工具 (net-tools/dnsutils/nmap/tcpdump/iftop...)"
        echo "  3) 压缩工具 (zip/unzip/xz/p7zip/zstd...)"
        echo "  4) 编译开发 (build-essential/gcc/cmake/autoconf...)"
        echo "  5) 系统监控 (sysstat/iotop/lsof/strace/glances...)"
        echo "  6) 文件系统 (lvm2/xfsprogs/ntfs-3g/parted...)"
        echo "  7) 终端工具 (tmux/zsh/bash-completion/neofetch...)"
        echo "  8) Python 环境 (python3/pip/venv...)"
        echo "  9) 安全与系统 (ufw/fail2ban/cron/logrotate...)"
        echo " 10) 数据库客户端 (mysql/postgres/redis/sqlite)"
        echo "  0) 返回"
        echo ""
        local choice
        choice="$(ask "选择类别(可输入多个，空格分隔)" "")"
        [ -z "$choice" ] && continue
        [ "$choice" = "0" ] && break

        step "更新软件源..."
        case "$PKG_MANAGER" in
            apt) apt-get update -qq ;;
            dnf|yum) dnf makecache 2>/dev/null || yum makecache ;;
            apk) apk update ;;
            pacman) pacman -Syy --noconfirm ;;
        esac

        for c in $choice; do
            case "$c" in
                1) _install_category "基础工具" "${PKG_BASE[@]}" ;;
                2) _install_category "网络工具" "${PKG_NETWORK[@]}" ;;
                3) _install_category "压缩工具" "${PKG_ARCHIVE[@]}" ;;
                4) _install_category "编译开发" "${PKG_BUILD[@]}" ;;
                5) _install_category "系统监控" "${PKG_MONITOR[@]}" ;;
                6) _install_category "文件系统" "${PKG_FS[@]}" ;;
                7) _install_category "终端工具" "${PKG_TERMINAL[@]}" ;;
                8) _install_category "Python环境" "${PKG_PYTHON[@]}" ;;
                9) _install_category "安全系统" "${PKG_SECURITY[@]}" ;;
                10) _install_category "数据库客户端" "${PKG_DBCLIENT[@]}" ;;
                *) warn "无效类别: $c" ;;
            esac
            echo ""
        done
        pause
    done
}

# ============================================================
#  检测缺失的常用命令
# ============================================================
essential_check() {
    header "常用命令检测"
    local cmds=(
        curl wget git vim htop jq tree rsync sudo zip unzip tar gzip
        gcc make cmake python3 pip3 tmux screen zsh nmap tcpdump
        traceroute dig iftop iotop lsof strace parted lvm2
    )
    local missing=()
    printf "  %-12s %s\n" "命令" "状态"
    printf "  %s\n" "----------------------------------------"
    for cmd in "${cmds[@]}"; do
        if has_cmd "$cmd"; then
            printf "  %-12s %s\n" "$cmd" "✓ 已安装"
        else
            printf "  %-12s %s\n" "$cmd" "✗ 缺失"
            missing+=("$cmd")
        fi
    done
    echo ""
    if [ ${#missing[@]} -gt 0 ]; then
        warn "缺失 ${#missing[@]} 个命令: ${missing[*]}"
        echo "  建议运行 [1] 一键完善 或 [2] 分类安装"
    else
        success "所有常用命令均已安装"
    fi
}

# ============================================================
#  新系统初始化（创建目录、基础配置）
# ============================================================
essential_init_config() {
    header "基础配置初始化"

    # 创建常用目录
    step "创建常用目录"
    mkdir -p "$HOME/bin" "$HOME/.local/bin" "$HOME/projects" "$HOME/backup" "$HOME/logs"
    done_msg "目录: ~/bin ~/.local/bin ~/projects ~/backup ~/logs"

    # 配置 vim 基础
    if [ ! -f "$HOME/.vimrc" ]; then
        step "生成 .vimrc 基础配置"
        cat > "$HOME/.vimrc" <<'EOF'
" 基础配置
syntax on
set number
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set hlsearch
set incsearch
set ignorecase
set smartcase
set encoding=utf-8
set fileencodings=utf-8,gbk,gb2312
set laststatus=2
set ruler
set cursorline
set wildmenu
set backspace=indent,eol,start
EOF
        done_msg "已生成 ~/.vimrc"
    else
        done_msg "~/.vimrc 已存在，跳过"
    fi

    # 配置 .bashrc 别名
    if ! grep -q "# === server-toolkit 别名 ===" "$HOME/.bashrc" 2>/dev/null; then
        step "添加 bash 常用别名"
        cat >> "$HOME/.bashrc" <<'EOF'

# === server-toolkit 别名 ===
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias df='df -hT'
alias du='du -h'
alias free='free -h'
alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias hist='history | grep'
alias ports='ss -tlnp'
alias myip='curl -s ifconfig.me'
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
EOF
        done_msg "已添加别名到 ~/.bashrc"
    fi

    # 配置 git
    if has_cmd git && [ -z "$(git config --global user.name 2>/dev/null)" ]; then
        echo ""
        warn "Git 未配置用户信息"
        local gname gemail
        gname="$(ask "Git 用户名(留空跳过)" "")"
        if [ -n "$gname" ]; then
            gemail="$(ask "Git 邮箱" "")"
            git config --global user.name "$gname"
            git config --global user.email "$gemail"
            git config --global init.defaultBranch main
            git config --global core.editor vim
            done_msg "Git 已配置"
        fi
    fi

    # 配置时区
    if has_cmd timedatectl && [ "$(timedatectl 2>/dev/null | grep 'Time zone' | awk '{print $3}')" != "Asia/Shanghai" ]; then
        if confirm "时区非 Asia/Shanghai，是否设置?" "y"; then
            timedatectl set-timezone Asia/Shanghai
            done_msg "时区已设置为 Asia/Shanghai"
        fi
    fi

    echo ""
    success "基础配置初始化完成，执行 source ~/.bashrc 生效"
}

# ============================================================
#  模块菜单
# ============================================================
essential_menu() {
    while true; do
        header "一键完善系统环境"
        echo "  1) 一键安装全部基础工具 (推荐)"
        echo "  2) 分类选择安装"
        echo "  3) 检测缺失的常用命令"
        echo "  4) 基础配置初始化 (目录/vim/bash别名/git)"
        echo "  5) 一键完善 (工具+配置)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) essential_all; pause ;;
            2) essential_select ;;
            3) essential_check; pause ;;
            4) essential_init_config; pause ;;
            5)
                essential_all
                echo ""
                essential_init_config
                pause
                ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    essential_menu
fi
