#!/usr/bin/env bash
# ============================================================
#  backup.sh - 备份与恢复
#  功能：目录备份、MySQL/PostgreSQL 备份、系统配置备份、
#        备份列表、恢复、自动清理
# ============================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

BACKUP_DIR="${TOOLKIT_ROOT}/backups"
RETENTION_DAYS=7

# ---- 通用：打包压缩目录 ----
_tar_backup() {
    local src="$1" dst="$2" label="${3:-backup}"
    [ -d "$src" ] || { error "源目录不存在: $src"; return 1; }
    mkdir -p "$dst"
    local ts name out
    ts="$(date +%Y%m%d_%H%M%S)"
    name="$(basename "$src")"
    out="${dst}/${label}_${name}_${ts}.tar.gz"
    step "打包: $src -> $out"
    tar -czf "$out" -C "$(dirname "$src")" "$(basename "$src")" 2>/dev/null
    if [ $? -eq 0 ] && [ -f "$out" ]; then
        local sz
        sz="$(du -h "$out" | awk '{print $1}')"
        done_msg "备份完成: $out ($sz)"
        echo "$out"
        return 0
    else
        fail_msg "备份失败"
        return 1
    fi
}

# ---- 目录备份 ----
backup_directory() {
    header "目录备份"
    local src dst
    src="$(ask "要备份的目录路径" "/etc")"
    dst="$(ask "备份保存目录" "$BACKUP_DIR")"
    _tar_backup "$src" "$dst" "dir"
}

# ---- MySQL/MariaDB 备份 ----
backup_mysql() {
    header "MySQL / MariaDB 备份"
    if ! has_cmd mysqldump; then
        warn "未找到 mysqldump，尝试自动安装..."
        if confirm "是否安装 mysql-client?" "y"; then
            pkg_install mysql-client 2>/dev/null || pkg_install mariadb-client 2>/dev/null
        fi
        has_cmd mysqldump || { error "安装失败，请手动安装"; return 1; }
    fi

    local host port user pass db dst
    host="$(ask "数据库主机" "127.0.0.1")"
    port="$(ask "端口" "3306")"
    user="$(ask "用户名" "root")"
    echo -n "  密码(输入不回显): "
    read -rs pass
    echo ""
    db="$(ask "数据库名(留空备份全部)" "")"
    dst="$(ask "备份保存目录" "$BACKUP_DIR")"

    mkdir -p "$dst"
    local ts out
    ts="$(date +%Y%m%d_%H%M%S)"
    if [ -n "$db" ]; then
        out="${dst}/mysql_${db}_${ts}.sql.gz"
        step "备份数据库: $db"
        MYSQL_PWD="$pass" mysqldump -h "$host" -P "$port" -u "$user" \
            --single-transaction --routines --triggers "$db" 2>/dev/null | gzip > "$out"
    else
        out="${dst}/mysql_all_${ts}.sql.gz"
        step "备份全部数据库"
        MYSQL_PWD="$pass" mysqldump -h "$host" -P "$port" -u "$user" \
            --single-transaction --routines --triggers --all-databases 2>/dev/null | gzip > "$out"
    fi

    if [ $? -eq 0 ] && [ -s "$out" ]; then
        local sz
        sz="$(du -h "$out" | awk '{print $1}')"
        done_msg "备份完成: $out ($sz)"
    else
        fail_msg "备份失败，请检查连接信息"
        rm -f "$out"
        return 1
    fi
}

# ---- PostgreSQL 备份 ----
backup_postgres() {
    header "PostgreSQL 备份"
    if ! has_cmd pg_dump; then
        warn "未找到 pg_dump，尝试自动安装..."
        if confirm "是否安装 postgresql-client?" "y"; then
            pkg_install postgresql-client 2>/dev/null
        fi
        has_cmd pg_dump || { error "安装失败"; return 1; }
    fi

    local host port user db dst
    host="$(ask "数据库主机" "127.0.0.1")"
    port="$(ask "端口" "5432")"
    user="$(ask "用户名" "postgres")"
    db="$(ask "数据库名(留空备份全部)" "")"
    dst="$(ask "备份保存目录" "$BACKUP_DIR")"

    mkdir -p "$dst"
    local ts out
    ts="$(date +%Y%m%d_%H%M%S)"
    export PGPASSWORD
    echo -n "  密码(输入不回显): "
    read -rs PGPASSWORD
    echo ""

    if [ -n "$db" ]; then
        out="${dst}/pg_${db}_${ts}.sql.gz"
        step "备份数据库: $db"
        pg_dump -h "$host" -p "$port" -U "$user" -d "$db" 2>/dev/null | gzip > "$out"
    else
        out="${dst}/pg_all_${ts}.sql.gz"
        step "备份全部数据库(pg_dumpall)"
        pg_dumpall -h "$host" -p "$port" -U "$user" 2>/dev/null | gzip > "$out"
    fi

    unset PGPASSWORD
    if [ $? -eq 0 ] && [ -s "$out" ]; then
        local sz
        sz="$(du -h "$out" | awk '{print $1}')"
        done_msg "备份完成: $out ($sz)"
    else
        fail_msg "备份失败"
        rm -f "$out"
        return 1
    fi
}

# ---- 系统关键配置一键备份 ----
backup_system_config() {
    header "系统配置备份"
    local dst
    dst="$(ask "备份保存目录" "$BACKUP_DIR")"
    mkdir -p "$dst"
    local ts out
    ts="$(date +%Y%m%d_%H%M%S)"
    out="${dst}/sysconfig_${ts}.tar.gz"

    # 收集常见关键配置（存在才打包）
    local items=()
    for p in /etc /home /root /var/spool/cron /usr/local/etc; do
        [ -e "$p" ] && items+=("$p")
    done

    # 已安装包列表
    local pkglist="/tmp/installed_pkgs_${ts}.txt"
    case "$PKG_MANAGER" in
        apt)    dpkg --get-selections > "$pkglist" 2>/dev/null ;;
        dnf|yum) rpm -qa > "$pkglist" 2>/dev/null ;;
        apk)    apk info > "$pkglist" 2>/dev/null ;;
        pacman) pacman -Q > "$pkglist" 2>/dev/null ;;
    esac
    [ -f "$pkglist" ] && items+=("$pkglist")

    step "打包系统配置..."
    tar -czf "$out" "${items[@]}" 2>/dev/null
    rm -f "$pkglist"

    if [ -f "$out" ]; then
        local sz
        sz="$(du -h "$out" | awk '{print $1}')"
        done_msg "系统配置备份完成: $out ($sz)"
    else
        fail_msg "备份失败"
    fi
}

# ---- 列出备份 ----
backup_list() {
    header "备份列表 ($BACKUP_DIR)"
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        warn "暂无备份文件"
        return 0
    fi
    printf "  %-45s %10s %s\n" "文件名" "大小" "修改时间"
    printf "  %s\n" "--------------------------------------------------------------"
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local name sz mt
        name="$(basename "$f")"
        sz="$(du -h "$f" | awk '{print $1}')"
        mt="$(date -d "@$(stat -c %Y "$f")" '+%Y-%m-%d %H:%M' 2>/dev/null)"
        printf "  %-45s %10s %s\n" "$name" "$sz" "$mt"
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
}

# ---- 恢复 tar.gz 备份 ----
backup_restore() {
    header "恢复备份"
    backup_list
    local file target
    file="$(ask "要恢复的备份文件(完整路径)" "")"
    [ -z "$file" ] && return 0
    [ -f "$file" ] || { error "文件不存在: $file"; return 1; }

    if [[ "$file" == *.tar.gz ]]; then
        target="$(ask "恢复到目标目录" "/tmp/restore")"
        mkdir -p "$target"
        step "解压到: $target"
        tar -xzf "$file" -C "$target"
        done_msg "恢复完成: $target"
    elif [[ "$file" == *.sql.gz ]]; then
        warn "SQL 备份需要手动导入，示例:"
        echo "    gunzip < $file | mysql -u 用户名 -p 数据库名"
        echo "    gunzip < $file | psql -U 用户名 -d 数据库名"
    else
        warn "未知格式，请手动处理: $file"
    fi
}

# ---- 清理过期备份 ----
backup_cleanup() {
    header "清理过期备份"
    local days
    days="$(ask "保留天数" "$RETENTION_DAYS")"
    local count=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        rm -f "$f"
        debug "删除: $f"
        count=$((count+1))
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -mtime +"$days" 2>/dev/null)
    success "已清理 $count 个超过 ${days} 天的备份"
}

# ---- 模块菜单 ----
backup_menu() {
    while true; do
        header "备份与恢复"
        echo "  1) 目录备份"
        echo "  2) MySQL / MariaDB 备份"
        echo "  3) PostgreSQL 备份"
        echo "  4) 系统配置一键备份"
        echo "  5) 查看备份列表"
        echo "  6) 恢复备份"
        echo "  7) 清理过期备份"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) backup_directory; pause ;;
            2) backup_mysql; pause ;;
            3) backup_postgres; pause ;;
            4) backup_system_config; pause ;;
            5) backup_list; pause ;;
            6) backup_restore; pause ;;
            7) backup_cleanup; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    backup_menu
fi
