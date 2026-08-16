#!/usr/bin/env bash
# ============================================================
#  swap.sh - Swap 交换分区管理
#  功能：查看、创建/扩容、删除、自动推荐
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SWAP_FILE_DEFAULT="/swapfile"

# ---- 查看当前 swap 状态 ----
swap_status() {
    header "Swap 状态"
    if [ -n "$(swapon --show=NAME,TYPE,SIZE,USED,PRIO 2>/dev/null)" ]; then
        swapon --show
    else
        warn "当前没有启用任何 Swap"
    fi
    echo ""
    echo "  内存总量: ${TOTAL_MEM_GB} GB"
    echo "  Swap 总量: $(free -h | awk '/^Swap:/ {print $2}')"
    echo "  Swap 已用: $(free -h | awk '/^Swap:/ {print $3}')"
    echo "  Swap 可用: $(free -h | awk '/^Swap:/ {print $4}')"
    echo ""
    echo "  swappiness: $(cat /proc/sys/vm/swappiness 2>/dev/null || echo 'N/A')"
}

# ---- 推荐 swap 大小 ----
_recommend_swap_size() {
    local mem="$TOTAL_MEM_GB"
    if [ "$mem" -le 2 ]; then
        echo $((mem * 2))
    elif [ "$mem" -le 8 ]; then
        echo "$mem"
    elif [ "$mem" -le 64 ]; then
        echo 8
    else
        echo 16
    fi
}

# ---- 创建/扩容 swap 文件 ----
swap_create() {
    require_root || return 1

    local recommended
    recommended="$(_recommend_swap_size)"

    header "创建 / 扩容 Swap"
    echo "  当前内存: ${TOTAL_MEM_GB} GB"
    echo "  推荐 Swap: ${recommended} GB"
    echo ""

    local size path
    size="$(ask "Swap 大小(GB)" "$recommended")"
    path="$(ask "Swap 文件路径" "$SWAP_FILE_DEFAULT")"

    # 校验数字
    if ! [[ "$size" =~ ^[0-9]+$ ]] || [ "$size" -lt 1 ]; then
        error "大小必须是正整数(GB)"
        return 1
    fi

    # 检查磁盘空间
    local free_gb
    free_gb="$(disk_free_gb /)"
    if [ "$(echo "$free_gb < $size" | bc -l 2>/dev/null)" = "1" ]; then
        error "根分区剩余空间不足: ${free_gb} GB < ${size} GB"
        return 1
    fi

    # 如果已存在同名 swap，先关闭
    if swapon --show | grep -q "^${path}"; then
        warn "检测到已有 swap 文件: $path，将先关闭并重建"
        swapoff "$path" 2>/dev/null
        rm -f "$path"
    elif [ -f "$path" ]; then
        warn "文件已存在但未启用，将覆盖: $path"
        rm -f "$path"
    fi

    step "创建 ${size}G swap 文件: $path"
    # 优先 fallocate（快），失败则用 dd
    if has_cmd fallocate; then
        fallocate -l "${size}G" "$path" || {
            warn "fallocate 失败，改用 dd..."
            dd if=/dev/zero of="$path" bs=1G count="$size" status=progress
        }
    else
        dd if=/dev/zero of="$path" bs=1G count="$size" status=progress
    fi

    step "设置权限 600"
    chmod 600 "$path"

    step "格式化为 swap"
    mkswap "$path"

    step "启用 swap"
    swapon "$path"

    # 写入 fstab（如不存在）
    if ! grep -q "^${path}[[:space:]]" /etc/fstab 2>/dev/null; then
        step "写入 /etc/fstab 实现开机自动挂载"
        echo "${path} none swap sw 0 0" >> /etc/fstab
    fi

    # 优化 swappiness
    local cur_swappiness
    cur_swappiness="$(cat /proc/sys/vm/swappiness 2>/dev/null || echo 60)"
    if [ "$cur_swappiness" -gt 30 ]; then
        if confirm "当前 swappiness=$cur_swappiness，建议调低到 10 以减少 SSD 写入，是否调整?" "y"; then
            sysctl vm.swappiness=10
            if [ -f /etc/sysctl.conf ]; then
                grep -q '^vm.swappiness' /etc/sysctl.conf \
                    && sed -i 's/^vm.swappiness.*/vm.swappiness=10/' /etc/sysctl.conf \
                    || echo 'vm.swappiness=10' >> /etc/sysctl.conf
            fi
            done_msg "swappiness 已设为 10"
        fi
    fi

    success "Swap 创建完成！"
    swap_status
}

# ---- 删除指定 swap ----
swap_remove() {
    require_root || return 1
    header "删除 Swap"

    local swaps
    swaps="$(swapon --show=NAME --noheadings 2>/dev/null)"
    if [ -z "$swaps" ]; then
        warn "当前没有启用的 Swap"
        return 0
    fi

    echo "  当前启用的 Swap:"
    echo "$swaps" | sed 's/^/    - /'
    echo ""

    local path
    path="$(ask "要删除的 swap 路径(输入 all 删除全部)" "")"
    [ -z "$path" ] && return 0

    if [ "$path" = "all" ]; then
        while read -r sp; do
            [ -z "$sp" ] && continue
            step "关闭并删除: $sp"
            swapoff "$sp" 2>/dev/null
            rm -f "$sp"
            sed -i "\|^${sp}[[:space:]]|d" /etc/fstab 2>/dev/null
        done <<< "$swaps"
    else
        if ! swapon --show | grep -q "^${path}"; then
            error "未找到该 swap: $path"
            return 1
        fi
        step "关闭: $path"
        swapoff "$path"
        step "删除文件"
        rm -f "$path"
        sed -i "\|^${path}[[:space:]]|d" /etc/fstab 2>/dev/null
    fi
    success "完成"
}

# ---- 调整 swappiness ----
swap_swappiness() {
    require_root || return 1
    local cur
    cur="$(cat /proc/sys/vm/swappiness 2>/dev/null || echo 60)"
    header "调整 swappiness"
    echo "  当前值: $cur (0-100，越小越倾向使用物理内存)"
    local val
    val="$(ask "设置为" "10")"
    if ! [[ "$val" =~ ^[0-9]+$ ]] || [ "$val" -gt 100 ]; then
        error "必须是 0-100 的整数"
        return 1
    fi
    sysctl vm.swappiness="$val"
    if [ -f /etc/sysctl.conf ]; then
        grep -q '^vm.swappiness' /etc/sysctl.conf \
            && sed -i "s/^vm.swappiness.*/vm.swappiness=${val}/" /etc/sysctl.conf \
            || echo "vm.swappiness=${val}" >> /etc/sysctl.conf
    fi
    success "swappiness 已设为 $val"
}

# ---- Zram 状态 ----
zram_status() {
    header "Zram 状态"
    if [ ! -d /sys/block/zram0 ]; then
        warn "未启用 Zram"
        return 0
    fi
    echo "  设备: /dev/zram0"
    echo "  磁盘大小: $(cat /sys/block/zram0/disksize 2>/dev/null | awk '{printf "%.1f MB", $1/1024/1024}')"
    echo "  压缩算法: $(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -o '\[[^]]*\]' | tr -d '[]')"
    echo "  已用数据: $(cat /sys/block/zram0/mm_stat 2>/dev/null | awk '{printf "%.1f MB", $1/1024/1024}')"
    echo "  压缩后大小: $(cat /sys/block/zram0/mm_stat 2>/dev/null | awk '{printf "%.1f MB", $2/1024/1024}')"
    echo "  压缩比: $(cat /sys/block/zram0/mm_stat 2>/dev/null | awk '{if($2>0) printf "%.2f:1", $1/$2; else print "N/A"}')"
    echo ""
    echo "  Swap 总览:"
    free -h | grep -E "Mem|Swap" | sed 's/^/  /'
}

# ---- 启用 Zram ----
zram_enable() {
    require_root || return 1
    header "启用 Zram (内存压缩交换)"

    if [ -d /sys/block/zram0 ]; then
        warn "Zram 已启用，先关闭再重新配置"
        zram_disable
    fi

    echo "  Zram 比传统 swap 文件更高效，适合小内存 VPS"
    echo ""

    local size algo
    size="$(ask "Zram 大小(MB，建议为内存的50%-100%)" "$((TOTAL_MEM_GB * 512))")"
    algo="$(ask "压缩算法 (zstd/lz4/lzo-rle)" "zstd")"

    # 加载模块
    step "加载 zram 模块"
    modprobe zram 2>/dev/null || { error "内核不支持 zram"; return 1; }

    step "配置 zram0: ${size}MB, 算法: $algo"
    echo "$algo" > /sys/block/zram0/comp_algorithm 2>/dev/null
    echo $((size * 1024 * 1024)) > /sys/block/zram0/disksize

    step "格式化为 swap 并启用"
    mkswap /dev/zram0
    swapon -p 100 /dev/zram0

    # 持久化配置（systemd 方式）
    step "写入开机自启配置"
    cat > /etc/systemd/system/zram.service <<EOF
[Unit]
Description=Zram Swap
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'modprobe zram && echo $algo > /sys/block/zram0/comp_algorithm && echo $((size * 1024 * 1024)) > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon -p 100 /dev/zram0'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 && echo 1 > /sys/block/zram0/reset'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable zram.service 2>/dev/null

    # 调低 swappiness 以配合 zram
    sysctl vm.swappiness=60 2>/dev/null

    success "Zram 已启用: ${size}MB ($algo)"
    zram_status
}

# ---- 禁用 Zram ----
zram_disable() {
    require_root || return 1
    if [ ! -d /sys/block/zram0 ]; then
        warn "Zram 未启用"
        return 0
    fi
    step "关闭 zram swap"
    swapoff /dev/zram0 2>/dev/null
    step "重置 zram 设备"
    echo 1 > /sys/block/zram0/reset 2>/dev/null
    step "禁用开机自启"
    systemctl disable zram.service 2>/dev/null
    rm -f /etc/systemd/system/zram.service
    systemctl daemon-reload 2>/dev/null
    success "Zram 已禁用"
}

# ---- 模块菜单 ----
swap_menu() {
    while true; do
        header "Swap / Zram 管理"
        echo "  1) 查看 Swap 状态"
        echo "  2) 创建 / 扩容 Swap 文件"
        echo "  3) 删除 Swap"
        echo "  4) 调整 swappiness"
        echo "  5) 查看 Zram 状态"
        echo "  6) 启用 Zram (内存压缩)"
        echo "  7) 禁用 Zram"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) swap_status; pause ;;
            2) swap_create; pause ;;
            3) swap_remove; pause ;;
            4) swap_swappiness; pause ;;
            5) zram_status; pause ;;
            6) zram_enable; pause ;;
            7) zram_disable; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

# 直接执行时进入菜单
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    swap_menu
fi
