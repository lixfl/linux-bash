#!/usr/bin/env bash
# ============================================================
#  chat.sh - 即时通讯 / 团队协作 / 语音
#  Mattermost / Rocket.Chat / Zulip / Matrix / Mumble
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
CHAT_BASE="${HOME}/chat"

# ============================================================
#  Mattermost
# ============================================================
chat_mattermost() {
    header "安装 Mattermost"
    echo "  开源 Slack 替代，团队聊天"
    _ensure_docker || return 1
    local dir="$CHAT_BASE/mattermost"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8065")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  mattermost:
    image: mattermost/mattermost-preview:latest
    container_name: mattermost
    ports:
      - "${port}:8065"
    environment:
      - TZ=Asia/Shanghai
    restart: always
EOF
    docker compose up -d
    sleep 10
    success "Mattermost 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  首次访问创建团队和管理员"
}

# ============================================================
#  Rocket.Chat
# ============================================================
chat_rocketchat() {
    header "安装 Rocket.Chat"
    echo "  开源聊天平台，支持音视频/Omnichannel"
    _ensure_docker || return 1
    local dir="$CHAT_BASE/rocketchat"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "3000")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  rocketchat:
    image: rocket.chat:latest
    container_name: rocketchat
    ports:
      - "${port}:3000"
    environment:
      - MONGO_URL=mongodb://mongo:27017/rocketchat
      - MONGO_OPLOG_URL=mongodb://mongo:27017/local
      - TZ=Asia/Shanghai
    depends_on:
      - mongo
    restart: always
  mongo:
    image: mongo:4.4
    command: mongod --oplogSize 128 --replSet rs01
    volumes:
      - ./db:/data/db
    restart: always
EOF
    docker compose up -d
    sleep 15
    success "Rocket.Chat 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  首次访问创建管理员"
}

# ============================================================
#  Zulip
# ============================================================
chat_zulip() {
    header "安装 Zulip"
    echo "  话题式聊天，适合技术团队"
    _ensure_docker || return 1
    local dir="$CHAT_BASE/zulip"
    if [ -d "$dir" ]; then
        warn "Zulip 已存在: $dir"
        return 0
    fi
    mkdir -p "$dir" && cd "$dir" || return 1
    step "克隆 Zulip Docker"
    git clone --depth 1 https://github.com/zulip/docker-zulip.git . 2>/dev/null
    local port
    port="$(ask "Web端口" "8080")"
    [ -f docker-compose.yml ] && sed -i "s/\"80:80\"/\"${port}:80\"/" docker-compose.yml 2>/dev/null
    docker compose up -d 2>/dev/null || warn "启动失败，Zulip 依赖较多建议手动配置"
    sleep 20
    success "Zulip 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  Matrix / Synapse
# ============================================================
chat_matrix() {
    header "安装 Matrix (Synapse)"
    echo "  去中心化通信协议服务端"
    _ensure_docker || return 1
    local dir="$CHAT_BASE/matrix"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "端口" "8008")"
    step "生成配置"
    docker run -it --rm -v "$dir:/data" -e SYNAPSE_SERVER_NAME=localhost -e SYNAPSE_REPORT_STATS=no matrixdotorg/synapse:latest generate 2>/dev/null
    docker run -d --name synapse -p "${port}:8008" \
        -e TZ=Asia/Shanghai \
        -v "$dir:/data" \
        --restart=always matrixdotorg/synapse:latest
    sleep 8
    success "Matrix Synapse 部署完成: http://localhost:${port}"
    echo "  创建用户: docker exec -it synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml"
    echo "  推荐客户端: Element (https://element.io)"
}

# ============================================================
#  Mumble
# ============================================================
chat_mumble() {
    header "安装 Mumble"
    echo "  低延迟语音服务器（游戏开黑）"
    _ensure_docker || return 1
    mkdir -p "$CHAT_BASE/mumble"
    local port
    port="$(ask "端口" "64738")"
    docker run -d --name mumble -p "${port}:64738" -p "${port}:64738/udp" \
        -e TZ=Asia/Shanghai \
        -e MUMBLE_SUPERUSER_PASSWORD=admin123 \
        -v "$CHAT_BASE/mumble:/data" \
        --restart=always phlak/mumble
    sleep 3
    success "Mumble 部署完成"
    echo "  地址: $(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  超级用户密码: admin123"
}

# ============================================================
#  菜单
# ============================================================
chat_menu() {
    while true; do
        header "即时通讯 / 团队协作 / 语音"
        echo "  1) Mattermost  (Slack替代)"
        echo "  2) Rocket.Chat (聊天+音视频)"
        echo "  3) Zulip       (话题式聊天)"
        echo "  4) Matrix      (去中心化通信)"
        echo "  5) Mumble      (低延迟语音)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) chat_mattermost; pause ;;
            2) chat_rocketchat; pause ;;
            3) chat_zulip; pause ;;
            4) chat_matrix; pause ;;
            5) chat_mumble; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    chat_menu
fi
