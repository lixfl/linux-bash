#!/usr/bin/env bash
# ============================================================
#  Server Toolkit - Linux 服务器运维脚本集
#  自动识别服务器环境，提供 swap、备份、监控、安全、优化等功能
#
#  用法:
#    ./main.sh              # 交互式菜单
#    ./main.sh info         # 直接进入系统信息模块
#    ./main.sh swap status  # 直接执行 swap 状态查看
#    ./main.sh --help       # 帮助
# ============================================================

set -u

# 脚本根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

TOOLKIT_VERSION="1.0.0"

# ---- 模块列表 ----
MODULES=(
    "info:系统信息"
    "mirror:软件源换源"
    "essential:环境完善"
    "swap:Swap/Zram管理"
    "backup:备份与恢复"
    "monitor:系统监控"
    "terminal:终端美化"
    "devtools:开发工具"
    "autoupdate:自动更新"
    "security:安全加固"
    "optimize:性能优化"
    "cleanup:系统清理"
    "network:网络诊断"
    "docker:Docker管理"
    "yunzai:Yunzai机器人"
    "botframework:机器人框架"
    "aiagent:AI Agent"
    "reinstall:一键DD重装系统"
)

# ---- 帮助 ----
show_help() {
    cat <<EOF
${BOLD}Server Toolkit v${TOOLKIT_VERSION}${NC} - Linux 服务器运维脚本集

${BOLD}用法:${NC}
  $(basename "$0") [模块] [子命令]

${BOLD}可用模块:${NC}
EOF
    for m in "${MODULES[@]}"; do
        local name="${m%%:*}" desc="${m##*:}"
        printf "  %-12s %s\n" "$name" "$desc"
    done
    cat <<EOF

${BOLD}示例:${NC}
  $(basename "$0")                    # 交互式菜单
  $(basename "$0") info               # 系统信息模块
  $(basename "$0") swap status        # 查看 swap 状态
  $(basename "$0") monitor overview   # 资源概览
  $(basename "$0") --help             # 显示帮助

${BOLD}提示:${NC}
  - 大部分操作需要 root 权限，建议使用 sudo 运行
  - 所有修改操作前会自动备份原文件
  - 支持 Debian/Ubuntu/CentOS/RHEL/Alpine/Arch 等发行版
EOF
}

# ---- 横幅 ----
show_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "   ____                  _            ____          _   _     _   "
    echo "  / ___|  ___ _ ____   _(_) ___ ___  |  _ \ ___   | | | |___| |_ "
    echo "  \___ \ / _ \ '__\ \ / / |/ __/ _ \ | |_) / _ \  | | | / __| __|"
    echo "   ___) |  __/ |   \ V /| | (_|  __/ |  _ < (_) | | |_| \__ \ |_ "
    echo "  |____/ \___|_|    \_/ |_|\___\___| |_| \_\___/   \___/|___/\__|"
    echo -e "${NC}"
    echo -e "  ${DIM}v${TOOLKIT_VERSION}  |  自动识别系统  |  模块化设计  |  安全可靠${NC}"
}

# ---- 主菜单 ----
main_menu() {
    while true; do
        clear
        show_banner
        print_system_summary

        echo -e "${BOLD}${PURPLE}─────────────────────────────────────────────${NC}"
        echo -e "${BOLD}  功能菜单${NC}"
        echo -e "${BOLD}${PURPLE}─────────────────────────────────────────────${NC}"
        local i=1
        for m in "${MODULES[@]}"; do
            local name="${m%%:*}" desc="${m##*:}"
            printf "  %2d) %-12s %s\n" "$i" "$name" "$desc"
            i=$((i+1))
        done
        echo "   0) 退出"
        echo ""

        local choice
        choice="$(ask "请选择功能" "")"
        [ -z "$choice" ] && continue

        if [ "$choice" = "0" ]; then
            echo ""
            info "再见！"
            exit 0
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#MODULES[@]}" ]; then
            local idx=$((choice-1))
            local mod="${MODULES[$idx]%%:*}"
            run_module "$mod"
        else
            warn "无效选项，请重新选择"
            sleep 1
        fi
    done
}

# ---- 运行模块 ----
run_module() {
    local mod="$1"
    local script="$SCRIPT_DIR/modules/${mod}.sh"
    if [ ! -f "$script" ]; then
        error "模块不存在: $mod"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$script"
    # 调用模块的菜单函数
    local menu_func="${mod}_menu"
    if declare -f "$menu_func" &>/dev/null; then
        "$menu_func"
    else
        error "模块 $mod 缺少 ${menu_func} 函数"
    fi
}

# ---- 直接执行子命令 ----
run_direct() {
    local mod="$1"
    shift
    local script="$SCRIPT_DIR/modules/${mod}.sh"
    if [ ! -f "$script" ]; then
        error "未知模块: $mod"
        show_help
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$script"
    if [ $# -gt 0 ]; then
        local func="${mod}_$1"
        shift
        if declare -f "$func" &>/dev/null; then
            "$func" "$@"
        else
            error "未知子命令: $func"
            echo "可用子命令:"
            declare -F | grep "^declare -f ${mod}_" | sed 's/declare -f /  /'
            exit 1
        fi
    else
        local menu_func="${mod}_menu"
        "$menu_func"
    fi
}

# ============================================================
#  入口
# ============================================================
main() {
    # 初始化检测
    detect_all

    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            echo "Server Toolkit v${TOOLKIT_VERSION}"
            exit 0
            ;;
        "")
            main_menu
            ;;
        *)
            run_direct "$@"
            ;;
    esac
}

main "$@"
