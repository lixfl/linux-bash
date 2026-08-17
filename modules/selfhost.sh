#!/usr/bin/env bash
# ============================================================
#  selfhost.sh - 自建服务一键部署
#  Alist / FileBrowser / Vaultwarden / Jellyfin / Memos / Gitea
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

SELFHOST_BASE="${HOME}/selfhost"

# ============================================================
#  1. Alist
# ============================================================
selfhost_alist() {
    header "安装 Alist"
    echo "  网盘聚合，支持阿里云盘/百度云/OneDrive/Google Drive 等统一挂载"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/alist"
    local port
    port="$(ask "Web端口" "5244")"
    step "启动 Alist"
    docker run -d \
        --name alist \
        -p "${port}:5244" \
        -e TZ=Asia/Shanghai \
        -v "$SELFHOST_BASE/alist:/opt/alist/data" \
        --restart=always \
        xhofe/alist:latest
    sleep 3
    success "Alist 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  查看管理员密码: docker exec -it alist ./alist admin"
}

# ============================================================
#  2. FileBrowser
# ============================================================
selfhost_filebrowser() {
    header "安装 FileBrowser"
    echo "  轻量文件管理器 Web UI，支持上传/下载/分享/编辑"
    _ensure_docker || return 1
    local dir
    dir="$(ask "管理的根目录" "$HOME")"
    local port
    port="$(ask "Web端口" "8080")"
    step "启动 FileBrowser"
    docker run -d \
        --name filebrowser \
        -p "${port}:80" \
        -e TZ=Asia/Shanghai \
        -v "$dir:/srv" \
        -v "$SELFHOST_BASE/filebrowser/database.db:/database.db" \
        -v "$SELFHOST_BASE/filebrowser/config.json:/config.json" \
        --restart=always \
        filebrowser/filebrowser:latest
    sleep 3
    success "FileBrowser 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  默认账号: admin / admin"
}

# ============================================================
#  3. Vaultwarden
# ============================================================
selfhost_vaultwarden() {
    header "安装 Vaultwarden"
    echo "  自建密码管理器（Bitwarden 兼容），轻量安全"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/vaultwarden"
    local port
    port="$(ask "Web端口" "8080")"
    step "启动 Vaultwarden"
    docker run -d \
        --name vaultwarden \
        -p "${port}:80" \
        -e TZ=Asia/Shanghai \
        -e SIGNUPS_ALLOWED=true \
        -v "$SELFHOST_BASE/vaultwarden:/data" \
        --restart=always \
        vaultwarden/server:latest
    sleep 3
    success "Vaultwarden 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  建议配合 Nginx Proxy Manager 使用 HTTPS"
}

# ============================================================
#  4. Jellyfin
# ============================================================
selfhost_jellyfin() {
    header "安装 Jellyfin"
    echo "  自建媒体服务器，管理电影/电视剧/音乐，支持多端播放"
    _ensure_docker || return 1
    local media_dir
    media_dir="$(ask "媒体文件目录" "$HOME/media")"
    mkdir -p "$media_dir" "$SELFHOST_BASE/jellyfin/config" "$SELFHOST_BASE/jellyfin/cache"
    local port
    port="$(ask "Web端口" "8096")"
    step "启动 Jellyfin"
    docker run -d \
        --name jellyfin \
        -p "${port}:8096" \
        -e TZ=Asia/Shanghai \
        -v "$SELFHOST_BASE/jellyfin/config:/config" \
        -v "$SELFHOST_BASE/jellyfin/cache:/cache" \
        -v "$media_dir:/media" \
        --restart=always \
        jellyfin/jellyfin:latest
    sleep 5
    success "Jellyfin 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  媒体目录: $media_dir (容器内 /media)"
}

# ============================================================
#  5. Memos
# ============================================================
selfhost_memos() {
    header "安装 Memos"
    echo "  轻量备忘录/微博客，支持 Markdown、标签、API、分享"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/memos"
    local port
    port="$(ask "Web端口" "5230")"
    step "启动 Memos"
    docker run -d \
        --name memos \
        -p "${port}:5230" \
        -e TZ=Asia/Shanghai \
        -v "$SELFHOST_BASE/memos:/var/opt/memos" \
        --restart=always \
        neosmemo/memos:latest
    sleep 3
    success "Memos 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  首次注册的账号为管理员"
}

# ============================================================
#  6. Gitea
# ============================================================
selfhost_gitea() {
    header "安装 Gitea"
    echo "  自建 Git 服务（GitHub 轻量替代），支持 Issues/PR/CI"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/gitea"
    mkdir -p "$dir" && cd "$dir" || return 1
    local web_port ssh_port
    web_port="$(ask "Web端口" "3000")"
    ssh_port="$(ask "SSH端口" "2222")"
    step "生成 Docker Compose"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    ports:
      - "${web_port}:3000"
      - "${ssh_port}:22"
    volumes:
      - ./data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    environment:
      - TZ=Asia/Shanghai
      - USER_UID=1000
      - USER_GID=1000
    restart: always
EOF
    step "启动 Gitea"
    docker compose up -d
    sleep 5
    success "Gitea 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${web_port}"
    echo "  SSH 克隆端口: ${ssh_port}"
    echo "  首次访问完成初始化设置"
}


# ============================================================
#  7. qBittorrent
# ============================================================
selfhost_qbittorrent() {
    header "安装 qBittorrent"
    echo "  BT 下载器，Web UI 管理"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/qbittorrent/config" "$SELFHOST_BASE/qbittorrent/downloads"
    local port
    port="$(ask "WebUI端口" "8080")"
    step "启动 qBittorrent"
    docker run -d \
        --name qbittorrent \
        -p "${port}:8080" \
        -p 6881:6881 -p 6881:6881/udp \
        -e TZ=Asia/Shanghai \
        -e WEBUI_PORT=8080 \
        -v "$SELFHOST_BASE/qbittorrent/config:/config" \
        -v "$SELFHOST_BASE/qbittorrent/downloads:/downloads" \
        --restart=always \
        lscr.io/linuxserver/qbittorrent:latest
    sleep 3
    success "qBittorrent 部署完成"
    echo "  WebUI: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  默认账号: admin / adminadmin"
    echo "  下载目录: $SELFHOST_BASE/qbittorrent/downloads"
}

# ============================================================
#  8. Aria2
# ============================================================
selfhost_aria2() {
    header "安装 Aria2"
    echo "  多协议下载器 (HTTP/FTP/BT/磁力)，含 Web UI"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/aria2/config" "$SELFHOST_BASE/aria2/downloads"
    local port rpc_port
    port="$(ask "WebUI端口" "6880")"
    rpc_port="$(ask "RPC端口" "6800")"
    step "启动 Aria2 + AriaNg WebUI"
    docker run -d \
        --name aria2 \
        -p "${port}:80" -p "${rpc_port}:6800" \
        -e TZ=Asia/Shanghai \
        -e RPC_SECRET=aria2123 \
        -v "$SELFHOST_BASE/aria2/config:/config" \
        -v "$SELFHOST_BASE/aria2/downloads:/downloads" \
        --restart=always \
        p3terx/aria2-pro
    sleep 3
    success "Aria2 部署完成"
    echo "  WebUI: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  RPC 密钥: aria2123"
    echo "  下载目录: $SELFHOST_BASE/aria2/downloads"
}

# ============================================================
#  9. Navidrome
# ============================================================
selfhost_navidrome() {
    header "安装 Navidrome"
    echo "  自建音乐流媒体服务器 (Subsonic 兼容)"
    _ensure_docker || return 1
    local music_dir
    music_dir="$(ask "音乐目录" "$HOME/music")"
    mkdir -p "$music_dir" "$SELFHOST_BASE/navidrome/data"
    local port
    port="$(ask "Web端口" "4533")"
    step "启动 Navidrome"
    docker run -d \
        --name navidrome \
        -p "${port}:4533" \
        -e TZ=Asia/Shanghai \
        -e ND_MUSICFOLDER=/music \
        -v "$SELFHOST_BASE/navidrome/data:/data" \
        -v "$music_dir:/music" \
        --restart=always \
        deluan/navidrome:latest
    sleep 3
    success "Navidrome 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  音乐目录: $music_dir"
    echo "  首次访问创建管理员账号"
}


# ============================================================
#  10. Nextcloud
# ============================================================
selfhost_nextcloud() {
    header "安装 Nextcloud"
    echo "  自建网盘/协作平台，支持日历/通讯录/OnlyOffice"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/nextcloud"
    mkdir -p "$dir/html" "$dir/db" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8080")"
    step "生成 Docker Compose"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud
    ports:
      - "${port}:80"
    volumes:
      - ./html:/var/www/html
    environment:
      - MYSQL_HOST=db
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=nextcloud123
    depends_on:
      - db
    restart: always
  db:
    image: mariadb:10.6
    container_name: nextcloud-db
    environment:
      - MYSQL_ROOT_PASSWORD=root123
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=nextcloud123
    volumes:
      - ./db:/var/lib/mysql
    restart: always
EOF
    docker compose up -d
    sleep 5
    success "Nextcloud 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  11. FreshRSS
# ============================================================
selfhost_freshrss() {
    header "安装 FreshRSS"
    echo "  轻量 RSS 订阅阅读器"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/freshrss"
    local port
    port="$(ask "Web端口" "8080")"
    docker run -d --name freshrss -p "${port}:80" -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/freshrss:/var/www/FreshRSS/data"         --restart=always freshrss/freshrss
    sleep 3
    success "FreshRSS 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  12. Hoppscotch
# ============================================================
selfhost_hoppscotch() {
    header "安装 Hoppscotch"
    echo "  开源 API 测试工具（Postman 替代）"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/hoppscotch"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "3000")"
    step "克隆并启动"
    git clone --depth 1 https://github.com/hoppscotch/hoppscotch.git . 2>/dev/null || true
    docker compose up -d 2>/dev/null || {
        warn "compose 启动失败，使用单容器版"
        docker run -d --name hoppscotch -p "${port}:3000" --restart=always hoppscotch/hoppscotch:latest
    }
    sleep 5
    success "Hoppscotch 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  13. Outline
# ============================================================
selfhost_outline() {
    header "安装 Outline"
    echo "  团队知识库/文档（Notion 替代）"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/outline"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "3000")"
    step "生成 Docker Compose"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  outline:
    image: outlinewiki/outline:latest
    container_name: outline
    ports:
      - "${port}:3000"
    env_file: .env
    depends_on:
      - postgres
      - redis
    restart: always
  postgres:
    image: postgres:15
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=outline
      - POSTGRES_PASSWORD=outline123
      - POSTGRES_DB=outline
    restart: always
  redis:
    image: redis:alpine
    restart: always
EOF
    cat > .env <<EOF
NODE_ENV=production
SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || echo outline-secret-key)
UTILS_SECRET=$(openssl rand -hex 32 2>/dev/null || echo outline-utils-key)
DATABASE_URL=postgres://outline:outline123@postgres:5432/outline
REDIS_URL=redis://redis:6379
URL=http://localhost:${port}
EOF
    docker compose up -d
    sleep 5
    success "Outline 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    warn "需配置 SLACK/OIDC 登录才能使用，详见 .env"
}

# ============================================================
#  14. Linkding
# ============================================================
selfhost_linkding() {
    header "安装 Linkding"
    echo "  轻量书签管理"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/linkding"
    local port
    port="$(ask "Web端口" "9090")"
    docker run -d --name linkding -p "${port}:9090" -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/linkding:/etc/linkding/data"         --restart=always sissbruecker/linkding:latest
    sleep 3
    success "Linkding 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  15. Minecraft 服务器
# ============================================================
selfhost_minecraft() {
    header "安装 Minecraft 服务器"
    echo "  一键开 MC 服，支持 Java 版"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/minecraft"
    local port version memory
    port="$(ask "游戏端口" "25565")"
    version="$(ask "版本 (latest/1.20.4等)" "latest")"
    memory="$(ask "最大内存" "4G")"
    step "启动 Minecraft 服务器"
    docker run -d --name minecraft -p "${port}:25565"         -e EULA=TRUE -e VERSION="$version" -e MEMORY="$memory"         -v "$SELFHOST_BASE/minecraft:/data"         --restart=always itzg/minecraft-server
    sleep 10
    success "Minecraft 服务器启动中"
    echo "  地址: $(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  版本: $version, 内存: $memory"
    echo "  日志: docker logs -f minecraft"
}

# ============================================================
#  状态查看
# ============================================================
selfhost_status() {
    header "自建服务状态"
    echo ""
    if has_cmd docker; then
        section "Docker 容器"
        for c in alist filebrowser vaultwarden jellyfin memos gitea qbittorrent aria2 navidrome nextcloud freshrss hoppscotch outline linkding minecraft; do
            docker inspect "$c" &>/dev/null && {
                local status
                status="$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)"
                echo "  ✓ $c: $status"
            }
        done
    fi
    echo ""
    section "安装目录"
    [ -d "$SELFHOST_BASE" ] && ls -1 "$SELFHOST_BASE" | sed 's/^/  • /' || echo "  暂无"
}

# ============================================================
#  菜单
# ============================================================
selfhost_menu() {
    while true; do
        header "自建服务一键部署"
        echo "  自动配置 Docker 环境，数据统一存放在 ~/selfhost/"
        echo ""
        echo "  1) Alist        (网盘聚合)"
        echo "  2) FileBrowser  (文件管理器WebUI)"
        echo "  3) Vaultwarden  (密码管理器)"
        echo "  4) Jellyfin     (媒体服务器)"
        echo "  5) Memos        (备忘录/微博客)"
        echo "  6) Gitea        (自建Git服务)"
        echo "  7) qBittorrent  (BT下载器)"
        echo "  8) Aria2        (多协议下载器)"
        echo "  9) Navidrome    (音乐流媒体)"
        echo " 10) Nextcloud    (网盘/协作)"
        echo " 11) FreshRSS     (RSS阅读器)"
        echo " 12) Hoppscotch   (API测试)"
        echo " 13) Outline      (知识库/文档)"
        echo " 14) Linkding     (书签管理)"
        echo " 15) Minecraft    (游戏服务器)"
        echo " 16) 查看已安装状态"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "选择要部署的服务" "")"
        case "$choice" in
            1) selfhost_alist; pause ;;
            2) selfhost_filebrowser; pause ;;
            3) selfhost_vaultwarden; pause ;;
            4) selfhost_jellyfin; pause ;;
            5) selfhost_memos; pause ;;
            6) selfhost_gitea; pause ;;
            7) selfhost_qbittorrent; pause ;;
            8) selfhost_aria2; pause ;;
            9) selfhost_navidrome; pause ;;
            10) selfhost_nextcloud; pause ;;
            11) selfhost_freshrss; pause ;;
            12) selfhost_hoppscotch; pause ;;
            13) selfhost_outline; pause ;;
            14) selfhost_linkding; pause ;;
            15) selfhost_minecraft; pause ;;
            16) selfhost_status; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    selfhost_menu
fi
