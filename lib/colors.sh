#!/usr/bin/env bash
# ============================================================
#  colors.sh - 终端颜色与格式化输出
# ============================================================

# 检测是否支持彩色输出
if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null)" -ge 8 ] 2>/dev/null; then
    _COLOR_SUPPORT=1
else
    _COLOR_SUPPORT=0
fi

if [ "$_COLOR_SUPPORT" = "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[0;37m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'  # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE='' BOLD='' DIM='' NC=''
fi

# ---- 日志级别函数 ----
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
debug()   { [ "${DEBUG:-0}" = "1" ] && echo -e "${DIM}[DEBUG]${NC} $*"; }

# ---- 带颜色的标题/分隔线 ----
header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
}

section() {
    echo ""
    echo -e "${BOLD}${PURPLE}▶ $*${NC}"
}

# ---- 进度/状态 ----
step()   { echo -e "  ${CYAN}→${NC} $*"; }
done_msg() { echo -e "  ${GREEN}✓${NC} $*"; }
fail_msg() { echo -e "  ${RED}✗${NC} $*"; }

# ---- 交互式确认 ----
confirm() {
    local prompt="${1:-确认执行?}"
    local default="${2:-n}"
    local hint
    if [ "$default" = "y" ]; then hint="[Y/n]"
    else hint="[y/N]"; fi
    local ans
    read -r -p "$(echo -e "${YELLOW}?${NC} ${prompt} ${hint} ")" ans
    ans="${ans:-$default}"
    case "$ans" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# ---- 读取输入（带默认值） ----
ask() {
    local prompt="$1" default="${2:-}" var
    if [ -n "$default" ]; then
        read -r -p "$(echo -e "${CYAN}?${NC} ${prompt} [${default}]: ")" var
        echo "${var:-$default}"
    else
        read -r -p "$(echo -e "${CYAN}?${NC} ${prompt}: ")" var
        echo "$var"
    fi
}
