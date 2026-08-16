#!/usr/bin/env bash
# ============================================================
#  cleanup.sh - 系统清理
#  功能：包缓存、日志、临时文件、旧内核、Docker 清理、大文件查找
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# ---- 包管理器缓存清理 ----
cleanup_pkg_cache() {
    header "清理包管理器缓存"
    case "$PKG_MANAGER" in
        apt)
            step "apt clean"
            apt-get clean
            step "apt autoremove"
            apt-get autoremove -y
            ;;
        dnf|yum)
            step "清理缓存"
            dnf clean all 2>/dev/null || yum clean all
            ;;
        apk)
            step "apk cache clean"
            apk cache clean 2>/dev/null
            rm -rf /var/cache/apk/*
            ;;
        pacman)
            step "清理未安装包缓存"
            pacman -Sc --noconfirm 2>/dev/null
            ;;
        zypper)
            zypper clean 2>/dev/null
            ;;
    esac
    success "包缓存清理完成"
}

# ---- 日志清理 ----
cleanup_logs() {
    header "清理系统日志"
    local freed=0

    # journalctl 日志
    if has_cmd journalctl; then
        local before
        before="$(du -sh /var/log/journal 2>/dev/null | awk '{print $1}')"
        step "清理 journal 日志(保留最近 7 天)"
        journalctl --vacuum-time=7d 2>/dev/null
        journalctl --vacuum-size=100M 2>/dev/null
    fi

    # 旧的 .gz / .1 日志
    step "清理轮转日志(*.gz, *.1, *.old)"
    find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" -o -name "*.xz" \) -delete 2>/dev/null

    # 清空大日志文件（不删除，保留 inode）
    step "清空大于 100M 的日志文件"
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local sz
        sz="$(du -m "$f" | awk '{print $1}')"
        echo "  清空: $f (${sz}M)"
        : > "$f"
    done < <(find /var/log -type f -size +100M 2>/dev/null)

    # /tmp 旧文件
    step "清理 /tmp 超过 7 天的文件"
    find /tmp -type f -atime +7 -delete 2>/dev/null
    find /tmp -type d -empty -delete 2>/dev/null

    success "日志清理完成"
}

# ---- 旧内核清理 ----
cleanup_old_kernels() {
    require_root || return 1
    header "清理旧内核"
    local current
    current="$(uname -r)"
    echo "  当前内核: $current"
    echo ""

    case "$PKG_MANAGER" in
        apt)
            local old_kernels
            old_kernels="$(dpkg -l 'linux-image-*' 2>/dev/null | grep '^ii' | awk '{print $2}' | grep -v "$current" | grep -v 'linux-image-generic\|linux-image-amd64\|linux-image-virtual')"
            if [ -z "$old_kernels" ]; then
                success "没有可清理的旧内核"
                return 0
            fi
            echo "  待清理:"
            echo "$old_kernels" | sed 's/^/    - /'
            if confirm "确认删除?" "y"; then
                apt-get remove --purge -y $old_kernels
                apt-get autoremove -y
                update-grub 2>/dev/null
                success "旧内核清理完成"
            fi
            ;;
        dnf|yum)
            step "使用 package-cleanup"
            if has_cmd package-cleanup; then
                package-cleanup --oldkernels --count=2 -y
            else
                dnf remove --oldinstallonly --setopt installonly_limit=2 -y 2>/dev/null
            fi
            success "旧内核清理完成"
            ;;
        *)
            warn "当前包管理器暂不支持自动清理旧内核"
            ;;
    esac
}

# ---- 大文件查找 ----
cleanup_find_large() {
    header "查找大文件"
    local path size
    path="$(ask "搜索路径" "/")"
    size="$(ask "最小大小(MB)" "100")"
    echo ""
    echo "  正在搜索大于 ${size}M 的文件(可能较慢)..."
    find "$path" -xdev -type f -size +"${size}M" -exec du -h {} + 2>/dev/null | sort -rh | head -20 | sed 's/^/  /'
}

# ---- Docker 清理 ----
cleanup_docker() {
    header "Docker 清理"
    if ! has_cmd docker; then
        warn "未安装 Docker"
        return 0
    fi
    if ! docker info &>/dev/null; then
        error "Docker 服务未运行或无权限"
        return 1
    fi

    echo "  1) 清理未使用的镜像/容器/卷"
    echo "  2) 清理所有停止的容器"
    echo "  3) 清理悬空镜像(dangling)"
    echo "  4) 清理构建缓存"
    echo "  5) 查看 Docker 磁盘占用"
    local opt
    opt="$(ask "请选择" "1")"
    case "$opt" in
        1) docker system prune -a --volumes -f ;;
        2) docker container prune -f ;;
        3) docker image prune -f ;;
        4) docker builder prune -f ;;
        5) docker system df ;;
    esac
    success "完成"
}

# ---- 用户缓存清理 ----
cleanup_user_cache() {
    header "清理用户缓存"
    local dirs=(
        "$HOME/.cache"
        "$HOME/.npm/_cacache"
        "$HOME/.gradle/caches"
        "$HOME/.m2/repository"
        "$HOME/.local/share/Trash"
    )
    local total=0
    for d in "${dirs[@]}"; do
        if [ -d "$d" ]; then
            local sz
            sz="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
            echo "  $d ($sz)"
        fi
    done
    echo ""
    if confirm "清理以上缓存目录?" "n"; then
        for d in "${dirs[@]}"; do
            [ -d "$d" ] && rm -rf "$d"/* 2>/dev/null && done_msg "已清理: $d"
        done
        success "用户缓存清理完成"
    fi
}

# ---- 一键清理 ----
cleanup_all() {
    header "一键系统清理"
    if ! confirm "将清理包缓存、日志、临时文件，确认?" "y"; then return 0; fi
    cleanup_pkg_cache
    echo ""
    cleanup_logs
    echo ""
    success "一键清理完成"
    echo ""
    echo "  清理后磁盘使用:"
    df -h / | sed 's/^/  /'
}

cleanup_menu() {
    while true; do
        header "系统清理"
        echo "  1) 清理包管理器缓存"
        echo "  2) 清理系统日志"
        echo "  3) 清理旧内核"
        echo "  4) 清理用户缓存"
        echo "  5) Docker 清理"
        echo "  6) 查找大文件"
        echo "  7) 一键清理"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) cleanup_pkg_cache; pause ;;
            2) cleanup_logs; pause ;;
            3) cleanup_old_kernels; pause ;;
            4) cleanup_user_cache; pause ;;
            5) cleanup_docker; pause ;;
            6) cleanup_find_large; pause ;;
            7) cleanup_all; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    cleanup_menu
fi
