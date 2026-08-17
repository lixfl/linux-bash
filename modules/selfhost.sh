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
#  16. Immich
# ============================================================
selfhost_immich() {
    header "安装 Immich"
    echo "  自建 Google Photos 替代，手机自动备份+AI识别"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/immich"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "2283")"
    step "下载 docker-compose"
    curl -fsSL https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml -o docker-compose.yml
    curl -fsSL https://github.com/immich-app/immich/releases/latest/download/example.env -o .env
    sed -i "s/^UPLOAD_LOCATION=.*/UPLOAD_LOCATION=.\/upload/" .env
    sed -i "s/2283:2283/${port}:2283/" docker-compose.yml
    step "启动 Immich (约6个容器)"
    docker compose up -d
    sleep 10
    success "Immich 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  首次访问注册管理员账号"
}

# ============================================================
#  17. PhotoPrism
# ============================================================
selfhost_photoprism() {
    header "安装 PhotoPrism"
    echo "  自建照片管理，AI标签/人脸识别/地理定位"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/photoprism"
    mkdir -p "$dir/photos" "$dir/storage" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "2342")"
    step "启动 PhotoPrism"
    docker run -d --name photoprism -p "${port}:2342"         -e PHOTOPRISM_ADMIN_PASSWORD=admin123         -e PHOTOPRISM_SITE_URL="http://localhost:${port}/"         -e TZ=Asia/Shanghai         -v "$dir/photos:/photoprism/originals"         -v "$dir/storage:/photoprism/storage"         --restart=always photoprism/photoprism:latest
    sleep 10
    success "PhotoPrism 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  账号: admin / admin123"
}

# ============================================================
#  18. Calibre-Web
# ============================================================
selfhost_calibre() {
    header "安装 Calibre-Web"
    echo "  电子书库管理，支持 Kindle 推送"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/calibre/books" "$SELFHOST_BASE/calibre/config"
    local port
    port="$(ask "Web端口" "8083")"
    docker run -d --name calibre-web -p "${port}:8083"         -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/calibre/books:/books"         -v "$SELFHOST_BASE/calibre/config:/config"         --restart=always lscr.io/linuxserver/calibre-web:latest
    sleep 5
    success "Calibre-Web 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  默认账号: admin / admin123"
}

# ============================================================
#  19. yt-dlp
# ============================================================
selfhost_ytdlp() {
    header "安装 yt-dlp"
    echo "  视频下载工具（YouTube/B站/抖音等1000+网站）"
    if has_cmd yt-dlp; then
        success "yt-dlp 已安装: $(yt-dlp --version)"
        return 0
    fi
    step "安装 yt-dlp"
    curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
    chmod +x /usr/local/bin/yt-dlp
    pkg_install ffmpeg 2>/dev/null
    success "yt-dlp 安装完成: $(yt-dlp --version)"
    echo "  下载视频: yt-dlp '视频URL'"
    echo "  列格式: yt-dlp -F 'URL'"
    echo "  下载音频: yt-dlp -x --audio-format mp3 'URL'"
}

# ============================================================
#  20. Palworld
# ============================================================
selfhost_palworld() {
    header "安装 Palworld 服务器"
    echo "  幻兽帕鲁专用服务器"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/palworld"
    local port query_port
    port="$(ask "游戏端口" "8211")"
    query_port="$(ask "查询端口" "27015")"
    step "启动 Palworld 服务器"
    docker run -d --name palworld         -p "${port}:8211/udp" -p "${query_port}:27015/udp"         -e TZ=Asia/Shanghai         -e SERVER_PASSWORD=palworld123         -e ADMIN_PASSWORD=admin123         -v "$SELFHOST_BASE/palworld:/palworld"         --restart=always thijsvanloef/palworld-server-docker:latest
    sleep 10
    success "Palworld 服务器启动中"
    echo "  游戏端口: ${port} (UDP)"
    echo "  服务器密码: palworld123"
    echo "  日志: docker logs -f palworld"
}

# ============================================================
#  21. SteamCMD
# ============================================================
selfhost_steamcmd() {
    header "安装 SteamCMD"
    echo "  Steam 游戏服务器通用管理工具"
    if has_cmd steamcmd; then
        success "SteamCMD 已安装"
        return 0
    fi
    step "安装 SteamCMD"
    if [ "$PKG_MANAGER" = "apt" ]; then
        echo "deb http://archive.ubuntu.com/ubuntu/ jammy multiverse" >> /etc/apt/sources.list
        dpkg --add-architecture i386
        apt-get update -qq
        echo "steamcmd steamcmd/license note" | debconf-set-selections
        apt-get install -y steamcmd
        ln -sf /usr/games/steamcmd /usr/local/bin/steamcmd
    else
        mkdir -p /opt/steamcmd && cd /opt/steamcmd
        curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz
        ln -sf /opt/steamcmd/steamcmd.sh /usr/local/bin/steamcmd
    fi
    success "SteamCMD 安装完成"
    echo "  安装游戏服: steamcmd +login anonymous +app_update <APPID> validate +quit"
    echo "  常用APPID: CS2=730, Valheim=896660, 方舟=2430930"
}

# ============================================================
#  22. Terraria
# ============================================================
selfhost_terraria() {
    header "安装 Terraria 服务器"
    echo "  泰拉瑞亚专用服务器"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/terraria"
    local port
    port="$(ask "游戏端口" "7777")"
    docker run -d --name terraria -p "${port}:7777"         -e TZ=Asia/Shanghai -e WORLD_FILENAME=world.wld         -v "$SELFHOST_BASE/terraria:/root/.local/share/Terraria"         --restart=always ryshe/terraria:latest
    sleep 5
    success "Terraria 服务器启动中"
    echo "  端口: ${port}"
    echo "  日志: docker logs -f terraria"
}

# ============================================================
#  23. Home Assistant
# ============================================================
selfhost_homeassistant() {
    header "安装 Home Assistant"
    echo "  智能家居中枢，接入各种智能设备"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/homeassistant"
    local port
    port="$(ask "Web端口" "8123")"
    step "启动 Home Assistant"
    docker run -d --name homeassistant         --privileged --net=host         -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/homeassistant:/config"         --restart=always ghcr.io/home-assistant/home-assistant:stable
    sleep 10
    success "Home Assistant 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  使用 host 网络模式以发现本地设备"
}


# ============================================================
#  24. NocoDB
# ============================================================
selfhost_nocodb() {
    header "安装 NocoDB"
    echo "  Airtable 开源替代，把数据库变成电子表格"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/nocodb"
    local port
    port="$(ask "Web端口" "8080")"
    docker run -d --name nocodb -p "${port}:8080"         -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/nocodb:/usr/app/data"         --restart=always nocodb/nocodb:latest
    sleep 5
    success "NocoDB 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  25. Appsmith
# ============================================================
selfhost_appsmith() {
    header "安装 Appsmith"
    echo "  低代码搭建内部管理后台/CRUD应用"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/appsmith"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8080")"
    step "下载 compose 并启动"
    curl -fsSL https://raw.githubusercontent.com/appsmithorg/appsmith/release/deploy/docker/docker-compose.yml -o docker-compose.yml 2>/dev/null || {
        cat > docker-compose.yml <<EOF
version: '3.8'
services:
  appsmith:
    image: appsmith/appsmith-ce
    container_name: appsmith
    ports:
      - "${port}:80"
      - "443:443"
    volumes:
      - ./stacks:/appsmith-stacks
    restart: always
EOF
    }
    sed -i "s/80:80/${port}:80/" docker-compose.yml 2>/dev/null
    docker compose up -d
    sleep 10
    success "Appsmith 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  26. ToolJet
# ============================================================
selfhost_tooljet() {
    header "安装 ToolJet"
    echo "  低代码平台，连接数据库/API快速搭应用"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/tooljet"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8082")"
    step "克隆并启动"
    git clone --depth 1 https://github.com/ToolJet/ToolJet.git . 2>/dev/null || true
    [ -f deploy/docker/.env.example ] && cp deploy/docker/.env.example deploy/docker/.env 2>/dev/null
    cd deploy/docker 2>/dev/null || cd .
    docker compose up -d 2>/dev/null || {
        warn "compose 启动失败，使用单容器版"
        docker run -d --name tooljet -p "${port}:3000"             -e TOOLJET_HOST=http://localhost:${port}             -e SECRET_KEY_BASE=$(openssl rand -hex 32)             -e LOCKBOX_MASTER_KEY=$(openssl rand -hex 32)             --restart=always tooljet/try:latest
    }
    sleep 8
    success "ToolJet 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  27. Plane
# ============================================================
selfhost_plane() {
    header "安装 Plane"
    echo "  开源项目管理（Jira/Linear 替代）"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/plane"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8084")"
    step "下载 compose"
    curl -fsSL https://raw.githubusercontent.com/makeplane/plane/master/deploy/selfhost/docker-compose.yml -o docker-compose.yml 2>/dev/null
    curl -fsSL https://raw.githubusercontent.com/makeplane/plane/master/deploy/selfhost/.env -o .env 2>/dev/null
    [ -f .env ] && sed -i "s/^WEB_URL=.*/WEB_URL=http:\/\/localhost:${port}/" .env
    docker compose up -d 2>/dev/null || {
        warn "compose 启动失败，Plane 依赖较多建议手动配置"
        return 1
    }
    sleep 15
    success "Plane 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  28. Leantime
# ============================================================
selfhost_leantime() {
    header "安装 Leantime"
    echo "  轻量项目管理，适合小团队"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/leantime"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8085")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  leantime:
    image: leantime/leantime:latest
    container_name: leantime
    ports:
      - "${port}:8080"
    environment:
      - LEAN_DB_HOST=mysql
      - LEAN_DB_USER=leantime
      - LEAN_DB_PASSWORD=leantime123
      - LEAN_DB_DATABASE=leantime
    depends_on:
      - mysql
    restart: always
  mysql:
    image: mysql:8
    environment:
      - MYSQL_ROOT_PASSWORD=root123
      - MYSQL_DATABASE=leantime
      - MYSQL_USER=leantime
      - MYSQL_PASSWORD=leantime123
    volumes:
      - ./db:/var/lib/mysql
    restart: always
EOF
    docker compose up -d
    sleep 8
    success "Leantime 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  默认账号: admin@leantime.com / admin123"
}

# ============================================================
#  29. OnlyOffice
# ============================================================
selfhost_onlyoffice() {
    header "安装 OnlyOffice"
    echo "  在线文档编辑，可对接 Nextcloud"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/onlyoffice"
    local port
    port="$(ask "Web端口" "8086")"
    docker run -d --name onlyoffice -p "${port}:80"         -e TZ=Asia/Shanghai -e JWT_ENABLED=false         -v "$SELFHOST_BASE/onlyoffice:/var/www/onlyoffice/Data"         --restart=always onlyoffice/documentserver
    sleep 10
    success "OnlyOffice 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  在 Nextcloud 中安装 OnlyOffice 插件并填入此地址"
}

# ============================================================
#  30. Etherpad
# ============================================================
selfhost_etherpad() {
    header "安装 Etherpad"
    echo "  实时协作文档"
    _ensure_docker || return 1
    local port
    port="$(ask "Web端口" "9001")"
    docker run -d --name etherpad -p "${port}:9001"         -e TZ=Asia/Shanghai         --restart=always etherpad/etherpad:latest
    sleep 5
    success "Etherpad 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  31. Umami
# ============================================================
selfhost_umami() {
    header "安装 Umami"
    echo "  隐私友好的网站统计（GA 替代，轻量）"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/umami"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "3000")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  umami:
    image: ghcr.io/umami-software/umami:postgresql-latest
    container_name: umami
    ports:
      - "${port}:3000"
    environment:
      - DATABASE_URL=postgresql://umami:umami123@db:5432/umami
      - DATABASE_TYPE=postgresql
      - APP_SECRET=$(openssl rand -hex 32)
    depends_on:
      - db
    restart: always
  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=umami
      - POSTGRES_USER=umami
      - POSTGRES_PASSWORD=umami123
    volumes:
      - ./db:/var/lib/postgresql/data
    restart: always
EOF
    docker compose up -d
    sleep 8
    success "Umami 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  默认账号: admin / umami"
}

# ============================================================
#  32. Plausible
# ============================================================
selfhost_plausible() {
    header "安装 Plausible"
    echo "  轻量隐私统计，无 Cookie"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/plausible"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8087")"
    step "克隆配置"
    git clone --depth 1 https://github.com/plausible/hosting . 2>/dev/null || true
    [ -f plausible-conf.env ] || cat > plausible-conf.env <<EOF
BASE_URL=http://localhost:${port}
SECRET_KEY_BASE=$(openssl rand -hex 64)
ADMIN_USER_EMAIL=admin@example.com
ADMIN_USER_NAME=admin
ADMIN_USER_PWD=admin123
EOF
    sed -i "s/80:8000/${port}:8000/" docker-compose.yml 2>/dev/null
    docker compose up -d 2>/dev/null || warn "compose 启动失败，请检查配置"
    sleep 10
    success "Plausible 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  33. Matomo
# ============================================================
selfhost_matomo() {
    header "安装 Matomo"
    echo "  功能最全的开源 GA 替代"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/matomo"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8088")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  matomo:
    image: matomo:latest
    container_name: matomo
    ports:
      - "${port}:80"
    volumes:
      - ./matomo:/var/www/html
    depends_on:
      - db
    restart: always
  db:
    image: mariadb:10.6
    environment:
      - MYSQL_ROOT_PASSWORD=root123
      - MYSQL_DATABASE=matomo
      - MYSQL_USER=matomo
      - MYSQL_PASSWORD=matomo123
    volumes:
      - ./db:/var/lib/mysql
    restart: always
EOF
    docker compose up -d
    sleep 8
    success "Matomo 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  数据库: matomo / matomo123 @ db:3306"
}

# ============================================================
#  34. It-tools
# ============================================================
selfhost_ittools() {
    header "安装 It-tools"
    echo "  开发者在线工具箱（加密/转换/格式化等100+工具）"
    _ensure_docker || return 1
    local port
    port="$(ask "Web端口" "8089")"
    docker run -d --name it-tools -p "${port}:80"         --restart=always corentinth/it-tools:latest
    sleep 3
    success "It-tools 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  35. Stirling-PDF
# ============================================================
selfhost_stirlingpdf() {
    header "安装 Stirling-PDF"
    echo "  PDF 全能工具（拆分/合并/转换/OCR）"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/stirlingpdf"
    local port
    port="$(ask "Web端口" "8090")"
    docker run -d --name stirling-pdf -p "${port}:8080"         -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/stirlingpdf:/usr/share/tessdata"         --restart=always frooodle/s-pdf:latest
    sleep 5
    success "Stirling-PDF 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  36. Dashy
# ============================================================
selfhost_dashy() {
    header "安装 Dashy"
    echo "  自建应用导航页/仪表盘"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/dashy"
    local port
    port="$(ask "Web端口" "8091")"
    docker run -d --name dashy -p "${port}:80"         -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/dashy/conf.yml:/app/public/conf.yml"         --restart=always lissy93/dashy:latest
    sleep 3
    success "Dashy 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  37. Gotify
# ============================================================
selfhost_gotify() {
    header "安装 Gotify"
    echo "  自建消息推送服务（手机收通知）"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/gotify"
    local port
    port="$(ask "Web端口" "8092")"
    docker run -d --name gotify -p "${port}:80"         -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/gotify:/app/data"         --restart=always gotify/server
    sleep 3
    success "Gotify 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  默认账号: admin / admin"
}

# ============================================================
#  38. Ntfy
# ============================================================
selfhost_ntfy() {
    header "安装 Ntfy"
    echo "  自建通知推送（HTTP PUT 即推送，极简）"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/ntfy/cache" "$SELFHOST_BASE/ntfy/config"
    local port
    port="$(ask "Web端口" "8093")"
    docker run -d --name ntfy -p "${port}:80"         -v "$SELFHOST_BASE/ntfy/cache:/var/cache/ntfy"         -v "$SELFHOST_BASE/ntfy/config:/etc/ntfy"         --restart=always binwiederhier/ntfy serve
    sleep 3
    success "Ntfy 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  推送: curl -d '消息' http://localhost:${port}/主题名"
}

# ============================================================
#  39. Shlink
# ============================================================
selfhost_shlink() {
    header "安装 Shlink"
    echo "  自建短链接服务，带访问统计"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/shlink"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8094")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  shlink:
    image: shlinkio/shlink:stable
    container_name: shlink
    ports:
      - "${port}:8080"
    environment:
      - DEFAULT_DOMAIN=localhost:${port}
      - IS_HTTPS_ENABLED=false
      - DB_DRIVER=sqlite
    volumes:
      - ./data:/etc/shlink/data
    restart: always
EOF
    docker compose up -d
    sleep 5
    success "Shlink 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  生成API Key: docker exec shlink shlink api-key:generate"
}

# ============================================================
#  40. Firefly III
# ============================================================
selfhost_firefly() {
    header "安装 Firefly III"
    echo "  个人财务管理（记账/预算/报表）"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/firefly"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8095")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  firefly:
    image: fireflyiii/core:latest
    container_name: firefly
    ports:
      - "${port}:8080"
    environment:
      - DB_CONNECTION=mysql
      - DB_HOST=db
      - DB_PORT=3306
      - DB_DATABASE=firefly
      - DB_USERNAME=firefly
      - DB_PASSWORD=firefly123
      - APP_KEY=$(openssl rand -hex 16)
      - TZ=Asia/Shanghai
    volumes:
      - ./upload:/var/www/html/storage/upload
    depends_on:
      - db
    restart: always
  db:
    image: mariadb:10.6
    environment:
      - MYSQL_ROOT_PASSWORD=root123
      - MYSQL_DATABASE=firefly
      - MYSQL_USER=firefly
      - MYSQL_PASSWORD=firefly123
    volumes:
      - ./db:/var/lib/mysql
    restart: always
EOF
    docker compose up -d
    sleep 10
    success "Firefly III 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  41. Actual Budget
# ============================================================
selfhost_actual() {
    header "安装 Actual Budget"
    echo "  现代个人预算工具（YNAB 替代）"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/actual"
    local port
    port="$(ask "Web端口" "5006")"
    docker run -d --name actual-budget -p "${port}:5006"         -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/actual:/data"         --restart=always actualbudget/actual-server:latest
    sleep 5
    success "Actual Budget 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  42. Mealie
# ============================================================
selfhost_mealie() {
    header "安装 Mealie"
    echo "  食谱管理 + 购物清单 + 餐计划"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/mealie"
    local port
    port="$(ask "Web端口" "9925")"
    docker run -d --name mealie -p "${port}:9000"         -e TZ=Asia/Shanghai         -e PUID=1000 -e PGID=1000         -v "$SELFHOST_BASE/mealie:/app/data"         --restart=always hkotel/mealie:latest
    sleep 8
    success "Mealie 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  默认账号: changeme@example.com / MyPassword"
}

# ============================================================
#  43. Zigbee2MQTT
# ============================================================
selfhost_zigbee2mqtt() {
    header "安装 Zigbee2MQTT"
    echo "  Zigbee 设备接入 Home Assistant（需 Zigbee 适配器）"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/zigbee2mqtt"
    local port device
    port="$(ask "Web端口" "8080")"
    device="$(ask "Zigbee适配器设备路径" "/dev/ttyUSB0")"
    docker run -d --name zigbee2mqtt         -p "${port}:8080"         -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/zigbee2mqtt:/app/data"         --device="$device"         --restart=always koenkk/zigbee2mqtt
    sleep 5
    success "Zigbee2MQTT 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    warn "需配置 MQTT 服务器地址，编辑 data/configuration.yaml"
}

# ============================================================
#  44. ESPHome
# ============================================================
selfhost_esphome() {
    header "安装 ESPHome"
    echo "  ESP8266/ESP32 智能家居固件管理"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/esphome"
    local port
    port="$(ask "Web端口" "6052")"
    docker run -d --name esphome -p "${port}:6052"         -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/esphome:/config"         --restart=always ghcr.io/esphome/esphome
    sleep 5
    success "ESPHome 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  45. Audiobookshelf
# ============================================================
selfhost_audiobookshelf() {
    header "安装 Audiobookshelf"
    echo "  有声书 + 播客管理"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/audiobookshelf/audiobooks" "$SELFHOST_BASE/audiobookshelf/podcasts" "$SELFHOST_BASE/audiobookshelf/config" "$SELFHOST_BASE/audiobookshelf/metadata"
    local port
    port="$(ask "Web端口" "13378")"
    docker run -d --name audiobookshelf -p "${port}:80"         -e TZ=Asia/Shanghai         -v "$SELFHOST_BASE/audiobookshelf/audiobooks:/audiobooks"         -v "$SELFHOST_BASE/audiobookshelf/podcasts:/podcasts"         -v "$SELFHOST_BASE/audiobookshelf/config:/config"         -v "$SELFHOST_BASE/audiobookshelf/metadata:/metadata"         --restart=always advplyr/audiobookshelf
    sleep 5
    success "Audiobookshelf 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  46. Owncast
# ============================================================
selfhost_owncast() {
    header "安装 Owncast"
    echo "  自建直播平台（Twitch 替代）"
    _ensure_docker || return 1
    mkdir -p "$SELFHOST_BASE/owncast"
    local port rtmp_port
    port="$(ask "Web端口" "8096")"
    rtmp_port="$(ask "RTMP端口" "1935")"
    docker run -d --name owncast         -p "${port}:8080" -p "${rtmp_port}:1935"         -v "$SELFHOST_BASE/owncast:/app/data"         --restart=always gabekangas/owncast:latest
    sleep 5
    success "Owncast 部署完成"
    echo "  观看: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  推流: rtmp://$(hostname -I 2>/dev/null|awk '{print $1}'):${rtmp_port}/live"
    echo "  流密钥: abc123 (管理后台可改)"
}

# ============================================================
#  47. Jitsi
# ============================================================
selfhost_jitsi() {
    header "安装 Jitsi"
    echo "  自建视频会议"
    _ensure_docker || return 1
    local dir="$SELFHOST_BASE/jitsi"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8097")"
    step "下载 Jitsi Docker 配置"
    git clone --depth 1 https://github.com/jitsi/docker-jitsi-meet.git . 2>/dev/null || true
    [ -f .env ] || cp env.example .env 2>/dev/null
    [ -f .env ] && {
        sed -i "s/^HTTP_PORT=.*/HTTP_PORT=${port}/" .env
        sed -i "s/^PUBLIC_URL=.*/PUBLIC_URL=http:\/\/localhost:${port}/" .env
        ./gen-passwords.sh 2>/dev/null
    }
    docker compose up -d 2>/dev/null || warn "compose 启动失败，Jitsi 依赖较多建议手动配置"
    sleep 10
    success "Jitsi 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  状态查看
# ============================================================
selfhost_status() {
    header "自建服务状态"
    echo ""
    if has_cmd docker; then
        section "Docker 容器"
        for c in alist filebrowser vaultwarden jellyfin memos gitea qbittorrent aria2 navidrome nextcloud freshrss hoppscotch outline linkding minecraft immich photoprism calibre-web palworld terraria homeassistant nocodb appsmith tooljet plane leantime onlyoffice etherpad umami plausible matomo it-tools stirling-pdf dashy gotify ntfy shlink firefly actual-budget mealie zigbee2mqtt esphome audiobookshelf owncast jitsi; do
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
        echo " 16) Immich       (照片备份AI识别)"
        echo " 17) PhotoPrism   (照片管理)"
        echo " 18) Calibre-Web  (电子书库)"
        echo " 19) yt-dlp       (视频下载)"
        echo " 20) Palworld     (幻兽帕鲁)"
        echo " 21) SteamCMD     (Steam游戏服)"
        echo " 22) Terraria     (泰拉瑞亚)"
        echo " 23) HomeAssistant(智能家居)"
        echo " 24) NocoDB       (无代码数据库)"
        echo " 25) Appsmith     (低代码后台)"
        echo " 26) ToolJet      (低代码平台)"
        echo " 27) Plane        (项目管理)"
        echo " 28) Leantime     (轻量项目管理)"
        echo " 29) OnlyOffice   (在线文档)"
        echo " 30) Etherpad     (实时协作)"
        echo " 31) Umami        (网站统计)"
        echo " 32) Plausible    (隐私统计)"
        echo " 33) Matomo       (网站分析)"
        echo " 34) It-tools     (开发者工具箱)"
        echo " 35) Stirling-PDF (PDF工具)"
        echo " 36) Dashy        (导航页)"
        echo " 37) Gotify       (消息推送)"
        echo " 38) Ntfy         (通知推送)"
        echo " 39) Shlink       (短链接)"
        echo " 40) Firefly III  (财务管理)"
        echo " 41) ActualBudget (预算工具)"
        echo " 42) Mealie       (食谱管理)"
        echo " 43) Zigbee2MQTT  (Zigbee)"
        echo " 44) ESPHome      (ESP固件)"
        echo " 45) Audiobookshelf(有声书)"
        echo " 46) Owncast      (直播)"
        echo " 47) Jitsi        (视频会议)"
        echo " 48) 查看已安装状态"
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
            16) selfhost_immich; pause ;;
            17) selfhost_photoprism; pause ;;
            18) selfhost_calibre; pause ;;
            19) selfhost_ytdlp; pause ;;
            20) selfhost_palworld; pause ;;
            21) selfhost_steamcmd; pause ;;
            22) selfhost_terraria; pause ;;
            23) selfhost_homeassistant; pause ;;
            24) selfhost_nocodb; pause ;;
            25) selfhost_appsmith; pause ;;
            26) selfhost_tooljet; pause ;;
            27) selfhost_plane; pause ;;
            28) selfhost_leantime; pause ;;
            29) selfhost_onlyoffice; pause ;;
            30) selfhost_etherpad; pause ;;
            31) selfhost_umami; pause ;;
            32) selfhost_plausible; pause ;;
            33) selfhost_matomo; pause ;;
            34) selfhost_ittools; pause ;;
            35) selfhost_stirlingpdf; pause ;;
            36) selfhost_dashy; pause ;;
            37) selfhost_gotify; pause ;;
            38) selfhost_ntfy; pause ;;
            39) selfhost_shlink; pause ;;
            40) selfhost_firefly; pause ;;
            41) selfhost_actual; pause ;;
            42) selfhost_mealie; pause ;;
            43) selfhost_zigbee2mqtt; pause ;;
            44) selfhost_esphome; pause ;;
            45) selfhost_audiobookshelf; pause ;;
            46) selfhost_owncast; pause ;;
            47) selfhost_jitsi; pause ;;
            48) selfhost_status; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    selfhost_menu
fi
