#!/usr/bin/env bash
# ============================================================
#  common.sh - 公共函数库：自动识别服务器环境
#  本脚本被其他模块 source，不可直接执行
# ============================================================

# 脚本根目录（被 source 时也能正确定位）
_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载颜色库
# shellcheck source=colors.sh
source "$_COMMON_DIR/colors.sh"

# ============================================================
#  全局变量（自动检测后填充）—— 使用条件赋值，避免被重复 source 时清空
# ============================================================
: "${OS_NAME:=}"          # 发行版名: ubuntu/debian/centos/rhel/rocky/alma/alpine/arch/kali ...
: "${OS_VERSION:=}"       # 版本号
: "${OS_FAMILY:=}"        # 家族: debian/rhel/alpine/arch/suse
: "${OS_PRETTY:=}"        # 友好名称
: "${ARCH:=}"             # 架构: x86_64/aarch64/armv7l ...
: "${PKG_MANAGER:=}"      # 包管理器: apt/yum/dnf/apk/pacman/zypper
: "${INIT_SYSTEM:=}"      # 初始化: systemd/sysvinit/openrc
: "${VIRT_TYPE:=}"        # 虚拟化: kvm/xen/vmware/lxc/docker/openvz/none(物理机)
: "${CLOUD_PROVIDER:=}"   # 云厂商: aws/aliyun/tencent/azure/gcp/unknown/none
: "${TOTAL_MEM_GB:=0}"    # 总内存 GB
: "${CPU_CORES:=0}"       # CPU 核心数
: "${ROOT_PARTITION:=}"   # 根分区设备
: "${DISK_TOTAL_GB:=0}"   # 根分区总容量 GB
: "${IS_ROOT:=0}"         # 是否 root
: "${HOST_IP:=}"          # 主网卡 IP
: "${TOOLKIT_ROOT:=$(cd "$_COMMON_DIR/.." && pwd)}"

# ============================================================
#  权限检测
# ============================================================
check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        IS_ROOT=1
        return 0
    else
        IS_ROOT=0
        return 1
    fi
}

require_root() {
    if ! check_root; then
        error "此操作需要 root 权限，请使用 sudo 或切换到 root 用户"
        return 1
    fi
    return 0
}

# ============================================================
#  发行版检测
# ============================================================
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_NAME="${ID,,}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_PRETTY="${PRETTY_NAME:-$OS_NAME $OS_VERSION}"
        case "$OS_NAME" in
            ubuntu|debian|kali|linuxmint|pop|elementary|raspbian)
                OS_FAMILY="debian" ;;
            centos|rhel|rocky|almalinux|ol|amzn|fedora|scientific)
                OS_FAMILY="rhel" ;;
            alpine)
                OS_FAMILY="alpine" ;;
            arch|manjaro|endeavouros)
                OS_FAMILY="arch" ;;
            opensuse*|sles)
                OS_FAMILY="suse" ;;
            *)
                OS_FAMILY="unknown" ;;
        esac
    elif [ -f /etc/redhat-release ]; then
        OS_FAMILY="rhel"
        OS_NAME="centos"
        OS_PRETTY="$(cat /etc/redhat-release)"
    elif [ -f /etc/debian_version ]; then
        OS_FAMILY="debian"
        OS_NAME="debian"
        OS_VERSION="$(cat /etc/debian_version)"
        OS_PRETTY="Debian $OS_VERSION"
    else
        OS_NAME="unknown"
        OS_FAMILY="unknown"
        OS_PRETTY="Unknown Linux"
    fi
}

# ============================================================
#  包管理器检测
# ============================================================
detect_pkg_manager() {
    case "$OS_FAMILY" in
        debian)
            command -v apt &>/dev/null && PKG_MANAGER="apt" ;;
        rhel)
            if command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
            elif command -v yum &>/dev/null; then
                PKG_MANAGER="yum"
            fi
            ;;
        alpine)
            command -v apk &>/dev/null && PKG_MANAGER="apk" ;;
        arch)
            command -v pacman &>/dev/null && PKG_MANAGER="pacman" ;;
        suse)
            command -v zypper &>/dev/null && PKG_MANAGER="zypper" ;;
    esac
}

# ============================================================
#  架构检测
# ============================================================
detect_arch() {
    ARCH="$(uname -m)"
}

# ============================================================
#  初始化系统检测
# ============================================================
detect_init() {
    if [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif command -v systemctl &>/dev/null && pidof systemd &>/dev/null; then
        INIT_SYSTEM="systemd"
    elif [ -f /sbin/openrc ] || [ -d /etc/runlevels ]; then
        INIT_SYSTEM="openrc"
    else
        INIT_SYSTEM="sysvinit"
    fi
}

# ============================================================
#  虚拟化/容器检测
# ============================================================
detect_virt() {
    if command -v systemd-detect-virt &>/dev/null; then
        VIRT_TYPE="$(systemd-detect-virt 2>/dev/null)"
    elif [ -f /.dockerenv ]; then
        VIRT_TYPE="docker"
    elif [ -f /proc/1/cgroup ] && grep -qi docker /proc/1/cgroup 2>/dev/null; then
        VIRT_TYPE="docker"
    else
        # 退化检测
        if [ -f /sys/class/dmi/id/product_name ]; then
            local pn
            pn="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
            case "$pn" in
                *VMware*)  VIRT_TYPE="vmware" ;;
                *VirtualBox*) VIRT_TYPE="virtualbox" ;;
                *KVM*)     VIRT_TYPE="kvm" ;;
                *Xen*)     VIRT_TYPE="xen" ;;
                *)         VIRT_TYPE="none" ;;
            esac
        else
            VIRT_TYPE="unknown"
        fi
    fi
    [ -z "$VIRT_TYPE" ] && VIRT_TYPE="none"
}

# ============================================================
#  云厂商检测（通过 metadata 或 MAC/DMI）
# ============================================================
detect_cloud() {
    # 先通过 DMI 产品名快速判断
    if [ -f /sys/class/dmi/id/sys_vendor ]; then
        local vendor
        vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)"
        case "$vendor" in
            *Amazon*)   CLOUD_PROVIDER="aws" ;;
            *Alibaba*)  CLOUD_PROVIDER="aliyun" ;;
            *Tencent*)  CLOUD_PROVIDER="tencent" ;;
            *Microsoft*) CLOUD_PROVIDER="azure" ;;
            *Google*)   CLOUD_PROVIDER="gcp" ;;
            *Huawei*)   CLOUD_PROVIDER="huawei" ;;
        esac
    fi
    # 再通过 metadata 接口确认（超时短，避免拖慢）
    if [ -z "$CLOUD_PROVIDER" ] || [ "$CLOUD_PROVIDER" = "unknown" ]; then
        if command -v curl &>/dev/null; then
            if curl -s --max-time 1 http://100.100.100.200/latest/meta-data/ &>/dev/null; then
                CLOUD_PROVIDER="aliyun"
            elif curl -s --max-time 1 http://metadata.tencentyun.com/latest/meta-data/ &>/dev/null; then
                CLOUD_PROVIDER="tencent"
            elif curl -s --max-time 1 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/ &>/dev/null; then
                CLOUD_PROVIDER="gcp"
            fi
        fi
    fi
    [ -z "$CLOUD_PROVIDER" ] && CLOUD_PROVIDER="none"
}

# ============================================================
#  硬件信息检测
# ============================================================
detect_hardware() {
    # 内存
    if [ -f /proc/meminfo ]; then
        local mem_kb
        mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
        TOTAL_MEM_GB="$(( (mem_kb + 1048575) / 1048576 ))"
    fi
    # CPU
    if command -v nproc &>/dev/null; then
        CPU_CORES="$(nproc)"
    else
        CPU_CORES="$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)"
    fi
    # 根分区
    ROOT_PARTITION="$(df -P / | awk 'NR==2 {print $1}')"
    DISK_TOTAL_GB="$(df -P / | awk 'NR==2 {printf "%.0f", $2/1024/1024}')"
    # 主 IP
    HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [ -z "$HOST_IP" ] && HOST_IP="$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -1)"
}

# ============================================================
#  总入口：执行全部检测
# ============================================================
detect_all() {
    check_root || true
    detect_os
    detect_pkg_manager
    detect_arch
    detect_init
    detect_virt
    detect_cloud
    detect_hardware
}

# ============================================================
#  打印系统信息摘要
# ============================================================
print_system_summary() {
    header "服务器环境识别结果"
    printf "  %-18s %s\n" "操作系统:"   "$OS_PRETTY"
    printf "  %-18s %s\n" "系统家族:"   "$OS_FAMILY"
    printf "  %-18s %s\n" "包管理器:"   "$PKG_MANAGER"
    printf "  %-18s %s\n" "系统架构:"   "$ARCH"
    printf "  %-18s %s\n" "初始化系统:" "$INIT_SYSTEM"
    printf "  %-18s %s\n" "虚拟化:"     "$VIRT_TYPE"
    printf "  %-18s %s\n" "云平台:"     "$CLOUD_PROVIDER"
    printf "  %-18s %s\n" "CPU 核心:"   "$CPU_CORES"
    printf "  %-18s %s\n" "内存:"       "${TOTAL_MEM_GB} GB"
    printf "  %-18s %s\n" "根分区:"     "$ROOT_PARTITION (${DISK_TOTAL_GB} GB)"
    printf "  %-18s %s\n" "主机 IP:"    "${HOST_IP:-未获取}"
    printf "  %-18s %s\n" "当前用户:"   "$(whoami) $([ "$IS_ROOT" = "1" ] && echo '(root)' || echo '(非root)')"
    echo ""
}

# ============================================================
#  通用包管理封装（自动适配）
# ============================================================
pkg_install() {
    local pkgs=("$@")
    [ ${#pkgs[@]} -eq 0 ] && return 1
    case "$PKG_MANAGER" in
        apt)    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}" ;;
        dnf)    dnf install -y "${pkgs[@]}" ;;
        yum)    yum install -y "${pkgs[@]}" ;;
        apk)    apk add --no-cache "${pkgs[@]}" ;;
        pacman) pacman -S --noconfirm "${pkgs[@]}" ;;
        zypper) zypper install -y "${pkgs[@]}" ;;
        *)
            error "不支持的包管理器: $PKG_MANAGER"
            return 1 ;;
    esac
}

pkg_update() {
    case "$PKG_MANAGER" in
        apt)    apt-get update -qq && apt-get upgrade -y ;;
        dnf)    dnf upgrade -y ;;
        yum)    yum update -y ;;
        apk)    apk update && apk upgrade ;;
        pacman) pacman -Syu --noconfirm ;;
        zypper) zypper update -y ;;
        *) error "不支持的包管理器: $PKG_MANAGER"; return 1 ;;
    esac
}

pkg_remove() {
    local pkgs=("$@")
    case "$PKG_MANAGER" in
        apt)    apt-get remove -y --purge "${pkgs[@]}" ;;
        dnf|yum) dnf remove -y "${pkgs[@]}" 2>/dev/null || yum remove -y "${pkgs[@]}" ;;
        apk)    apk del "${pkgs[@]}" ;;
        pacman) pacman -Rns --noconfirm "${pkgs[@]}" ;;
        zypper) zypper remove -y "${pkgs[@]}" ;;
    esac
}

# ============================================================
#  服务管理封装（自动适配 init 系统）
# ============================================================
svc_enable() {
    local svc="$1"
    case "$INIT_SYSTEM" in
        systemd) systemctl enable "$svc" ;;
        openrc)  rc-update add "$svc" default ;;
        sysvinit) update-rc.d "$svc" defaults 2>/dev/null || chkconfig "$svc" on 2>/dev/null ;;
    esac
}

svc_start() {
    local svc="$1"
    case "$INIT_SYSTEM" in
        systemd) systemctl start "$svc" ;;
        openrc)  rc-service "$svc" start ;;
        sysvinit) service "$svc" start ;;
    esac
}

svc_restart() {
    local svc="$1"
    case "$INIT_SYSTEM" in
        systemd) systemctl restart "$svc" ;;
        openrc)  rc-service "$svc" restart ;;
        sysvinit) service "$svc" restart ;;
    esac
}

svc_status() {
    local svc="$1"
    case "$INIT_SYSTEM" in
        systemd) systemctl is-active "$svc" &>/dev/null ;;
        openrc)  rc-service "$svc" status &>/dev/null ;;
        sysvinit) service "$svc" status &>/dev/null ;;
    esac
}

# ============================================================
#  工具函数
# ============================================================

# 安全备份文件（自动加时间戳）
safe_backup_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    local bak="${file}.bak.$(date +%Y%m%d_%H%M%S)"
    cp -a "$file" "$bak"
    debug "已备份: $file -> $bak"
    echo "$bak"
}

# 检查命令是否存在
has_cmd() { command -v "$1" &>/dev/null; }

# 带重试的命令
retry_cmd() {
    local max="${1:-3}" delay="${2:-2}"
    shift 2
    local i=0
    while [ $i -lt "$max" ]; do
        if "$@"; then return 0; fi
        i=$((i+1))
        warn "第 $i 次失败，${delay}s 后重试..."
        sleep "$delay"
    done
    return 1
}

# 磁盘剩余空间（GB，指定路径）
disk_free_gb() {
    local path="${1:-/}"
    df -P "$path" | awk 'NR==2 {printf "%.1f", $4/1024/1024}'
}

# 日志记录到文件
log_to_file() {
    local logfile="$1"; shift
    mkdir -p "$(dirname "$logfile")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$logfile"
}

# 按回车继续
pause() {
    read -r -p "$(echo -e "${DIM}按回车键继续...${NC}")" _
}
