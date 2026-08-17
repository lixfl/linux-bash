#!/usr/bin/env bash
# ============================================================
#  media.sh - 媒体自动化 (*arr 全家桶)
#  Sonarr / Radarr / Lidarr / Readarr / Prowlarr / Bazarr / Overseerr / Komga
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
MEDIA_BASE="${HOME}/media"

# 通用 Docker 运行函数
_run_arr() {
    local name=$1 port=$2 image=$3 extra=${4:-}
    mkdir -p "$MEDIA_BASE/$name/config" "$MEDIA_BASE/$name/data"
    docker run -d --name "$name" -p "${port}:${port}" \
        -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai \
        -v "$MEDIA_BASE/$name/config:/config" \
        -v "$MEDIA_BASE/data:/data" \
        $extra --restart=always "$image"
    sleep 3
    success "$name 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

media_sonarr() { header "安装 Sonarr (电视剧)"; _ensure_docker || return 1; local port; port="$(ask "端口" "8989")"; _run_arr sonarr "$port" lscr.io/linuxserver/sonarr:latest; }
media_radarr() { header "安装 Radarr (电影)"; _ensure_docker || return 1; local port; port="$(ask "端口" "7878")"; _run_arr radarr "$port" lscr.io/linuxserver/radarr:latest; }
media_lidarr() { header "安装 Lidarr (音乐)"; _ensure_docker || return 1; local port; port="$(ask "端口" "8686")"; _run_arr lidarr "$port" lscr.io/linuxserver/lidarr:latest; }
media_readarr() { header "安装 Readarr (电子书)"; _ensure_docker || return 1; local port; port="$(ask "端口" "8787")"; _run_arr readarr "$port" lscr.io/linuxserver/readarr:develop; }
media_prowlarr() { header "安装 Prowlarr (索引器)"; _ensure_docker || return 1; local port; port="$(ask "端口" "9696")"; _run_arr prowlarr "$port" lscr.io/linuxserver/prowlarr:latest; }
media_bazarr() { header "安装 Bazarr (字幕)"; _ensure_docker || return 1; local port; port="$(ask "端口" "6767")"; _run_arr bazarr "$port" lscr.io/linuxserver/bazarr:latest; }

# ============================================================
#  Overseerr
# ============================================================
media_overseerr() {
    header "安装 Overseerr"
    echo "  媒体请求管理（用户申请下载）"
    _ensure_docker || return 1
    mkdir -p "$MEDIA_BASE/overseerr/config"
    local port
    port="$(ask "端口" "5055")"
    docker run -d --name overseerr -p "${port}:5055" \
        -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai \
        -v "$MEDIA_BASE/overseerr/config:/app/config" \
        --restart=always lscr.io/linuxserver/overseerr:latest
    sleep 5
    success "Overseerr 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  Komga
# ============================================================
media_komga() {
    header "安装 Komga"
    echo "  漫画/电子书管理"
    _ensure_docker || return 1
    mkdir -p "$MEDIA_BASE/komga/config" "$MEDIA_BASE/komga/data"
    local port
    port="$(ask "端口" "8080")"
    docker run -d --name komga -p "${port}:8080" \
        -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai \
        -v "$MEDIA_BASE/komga/config:/config" \
        -v "$MEDIA_BASE/komga/data:/data" \
        --restart=always gotson/komga:latest
    sleep 5
    success "Komga 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  默认账号: admin@example.org / admin"
}

# ============================================================
#  一键全套
# ============================================================
media_all() {
    header "一键安装媒体自动化全家桶"
    echo "  Prowlarr + Sonarr + Radarr + Lidarr + Readarr + Bazarr + Overseerr"
    _ensure_docker || return 1
    if ! confirm "将安装7个容器，继续?" "y"; then return 0; fi
    media_prowlarr
    media_sonarr
    media_radarr
    media_lidarr
    media_readarr
    media_bazarr
    media_overseerr
    success "全家桶安装完成"
    echo "  数据目录: $MEDIA_BASE/data"
    echo "  需在各服务中互相关联(Prowlarr->Sonarr/Radarr等)"
}

# ============================================================
#  菜单
# ============================================================
media_menu() {
    while true; do
        header "媒体自动化 (*arr 全家桶)"
        echo "  1) Prowlarr    (索引器统一管理)"
        echo "  2) Sonarr      (电视剧自动下载)"
        echo "  3) Radarr      (电影自动下载)"
        echo "  4) Lidarr      (音乐自动下载)"
        echo "  5) Readarr     (电子书自动下载)"
        echo "  6) Bazarr      (字幕自动下载)"
        echo "  7) Overseerr   (媒体请求管理)"
        echo "  8) Komga       (漫画/电子书管理)"
        echo "  9) 一键安装全家桶"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) media_prowlarr; pause ;;
            2) media_sonarr; pause ;;
            3) media_radarr; pause ;;
            4) media_lidarr; pause ;;
            5) media_readarr; pause ;;
            6) media_bazarr; pause ;;
            7) media_overseerr; pause ;;
            8) media_komga; pause ;;
            9) media_all; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    media_menu
fi
