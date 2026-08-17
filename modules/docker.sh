#!/usr/bin/env bash
# ============================================================
#  docker.sh - Docker 管理
#  安装直接调用 linuxmirrors.cn 官方脚本
# ============================================================
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

DOCKER_SCRIPT_URL="https://linuxmirrors.cn/docker.sh"

# ---- 检查 Docker ----
_check_docker() {
    if ! has_cmd docker; then
        error "未安装 Docker"
        return 1
    fi
    if ! docker info &>/dev/null; then
        error "Docker 服务未运行或当前用户无权限"
        return 1
    fi
    return 0
}

# ---- 安装 Docker ----
docker_install() {
    require_root || return 1
    header "安装 Docker (linuxmirrors.cn)"
    if has_cmd docker; then
        warn "Docker 已安装: $(docker --version)"
        if ! confirm "是否重新安装?" "n"; then
            return 0
        fi
        pkg_remove docker docker-engine docker.io containerd runc 2>/dev/null
    fi
    echo "  当前系统: $OS_PRETTY"
    echo ""
    if ! has_cmd curl; then
        step "安装 curl"
        pkg_install curl
    fi
    info "即将运行 linuxmirrors.cn 官方 Docker 安装脚本"
    echo "  脚本会自动识别系统并配置国内镜像源，按提示操作即可"
    echo ""
    if ! confirm "继续?" "y"; then return 0; fi
    step "下载并执行 Docker 安装脚本"
    bash <(curl -sSL "$DOCKER_SCRIPT_URL")

    svc_enable docker 2>/dev/null
    svc_start docker 2>/dev/null
    sleep 2
    if has_cmd docker; then
        success "Docker 安装完成: $(docker --version)"
        if confirm "将当前用户加入 docker 组(免 sudo)?" "y"; then
            local user="${SUDO_USER:-$USER}"
            usermod -aG docker "$user"
            done_msg "已将 $user 加入 docker 组，重新登录后生效"
        fi
    else
        error "Docker 安装失败，请检查网络或手动安装"
    fi
}

# ---- 容器管理 ----
docker_containers() {
    _check_docker || return 1
    while true; do
        header "容器管理"
        echo "  1) 列出所有容器"
        echo "  2) 启动容器"
        echo "  3) 停止容器"
        echo "  4) 重启容器"
        echo "  5) 删除容器"
        echo "  6) 进入容器"
        echo "  7) 查看容器日志"
        echo "  0) 返回"
        echo ""
        local opt
        opt="$(ask "请选择" "1")"
        case "$opt" in
            1) docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}" ;;
            2)
                local name
                name="$(ask "容器名/ID" "")"
                [ -n "$name" ] && docker start "$name" && success "已启动: $name"
                ;;
            3)
                local name
                name="$(ask "容器名/ID" "")"
                [ -n "$name" ] && docker stop "$name" && success "已停止: $name"
                ;;
            4)
                local name
                name="$(ask "容器名/ID" "")"
                [ -n "$name" ] && docker restart "$name" && success "已重启: $name"
                ;;
            5)
                local name
                name="$(ask "容器名/ID" "")"
                [ -n "$name" ] && docker rm -f "$name" && success "已删除: $name"
                ;;
            6)
                local name
                name="$(ask "容器名/ID" "")"
                [ -n "$name" ] && docker exec -it "$name" /bin/bash 2>/dev/null || docker exec -it "$name" /bin/sh
                ;;
            7)
                local name lines
                name="$(ask "容器名/ID" "")"
                lines="$(ask "行数" "100")"
                [ -n "$name" ] && docker logs -f --tail "$lines" "$name"
                ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
        [ "$opt" != "0" ] && pause
    done
}

# ---- 镜像管理 ----
docker_images() {
    _check_docker || return 1
    while true; do
        header "镜像管理"
        echo "  1) 列出镜像"
        echo "  2) 拉取镜像"
        echo "  3) 删除镜像"
        echo "  4) 清理悬空镜像"
        echo "  0) 返回"
        echo ""
        local opt
        opt="$(ask "请选择" "1")"
        case "$opt" in
            1) docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" ;;
            2)
                local img
                img="$(ask "镜像名 (如 nginx:latest)" "")"
                [ -n "$img" ] && docker pull "$img"
                ;;
            3)
                local img
                img="$(ask "镜像名/ID" "")"
                [ -n "$img" ] && docker rmi "$img"
                ;;
            4) docker image prune -f; success "已清理" ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
        [ "$opt" != "0" ] && pause
    done
}

# ---- Docker 资源统计 ----
docker_stats() {
    _check_docker || return 1
    header "Docker 资源统计"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
}

# ---- Docker Compose 管理 ----
docker_compose() {
    _check_docker || return 1
    header "Docker Compose 管理"
    local dir
    dir="$(ask "compose 文件所在目录" "$(pwd)")"
    [ -d "$dir" ] || { error "目录不存在"; return 1; }
    cd "$dir" || return 1
    local compose_cmd
    if docker compose version &>/dev/null; then
        compose_cmd="docker compose"
    elif has_cmd docker-compose; then
        compose_cmd="docker-compose"
    else
        error "未找到 docker compose"
        return 1
    fi
    echo "  使用: $compose_cmd"
    echo ""
    echo "  1) 启动 (up -d)"
    echo "  2) 停止 (down)"
    echo "  3) 重启"
    echo "  4) 查看日志"
    echo "  5) 查看状态"
    echo "  6) 拉取最新镜像并重建"
    local opt
    opt="$(ask "请选择" "5")"
    case "$opt" in
        1) $compose_cmd up -d ;;
        2) $compose_cmd down ;;
        3) $compose_cmd restart ;;
        4) $compose_cmd logs -f --tail=100 ;;
        5) $compose_cmd ps ;;
        6) $compose_cmd pull && $compose_cmd up -d --build ;;
    esac
}

# ---- 快速运行常用服务 ----
docker_quick_run() {
    _check_docker || return 1
    header "快速运行常用服务"
    echo "  1) Nginx"
    echo "  2) MySQL 8"
    echo "  3) Redis"
    echo "  4) PostgreSQL"
    echo "  5) MongoDB"
    local opt name port
    opt="$(ask "选择服务" "1")"
    name="$(ask "容器名" "myapp")"
    port="$(ask "映射端口" "")"
    case "$opt" in
        1)
            [ -z "$port" ] && port=80
            docker run -d --name "$name" -p "${port}:80" --restart unless-stopped nginx:alpine
            ;;
        2)
            [ -z "$port" ] && port=3306
            local pwd
            pwd="$(ask "root 密码" "root123456")"
            docker run -d --name "$name" -p "${port}:3306" -e MYSQL_ROOT_PASSWORD="$pwd" --restart unless-stopped mysql:8
            ;;
        3)
            [ -z "$port" ] && port=6379
            docker run -d --name "$name" -p "${port}:6379" --restart unless-stopped redis:alpine
            ;;
        4)
            [ -z "$port" ] && port=5432
            local pwd
            pwd="$(ask "postgres 密码" "postgres")"
            docker run -d --name "$name" -p "${port}:5432" -e POSTGRES_PASSWORD="$pwd" --restart unless-stopped postgres:alpine
            ;;
        5)
            [ -z "$port" ] && port=27017
            docker run -d --name "$name" -p "${port}:27017" --restart unless-stopped mongo:latest
            ;;
        *) warn "无效选项"; return 1 ;;
    esac
    success "服务已启动: $name"
}

docker_menu() {
    while true; do
        header "Docker 管理"
        echo "  1) 安装 Docker (linuxmirrors.cn 官方脚本)"
        echo "  2) 容器管理"
        echo "  3) 镜像管理"
        echo "  4) Compose 管理"
        echo "  5) 资源统计"
        echo "  6) 快速运行常用服务"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) docker_install; pause ;;
            2) docker_containers ;;
            3) docker_images ;;
            4) docker_compose; pause ;;
            5) docker_stats; pause ;;
            6) docker_quick_run; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    docker_menu
fi
