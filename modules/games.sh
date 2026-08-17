#!/usr/bin/env bash
# ============================================================
#  games.sh - 游戏服务器
#  CS2 / Valheim / Factorio / Rust / Satisfactory / V Rising
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
GAMES_BASE="${HOME}/games"

# ============================================================
#  CS2
# ============================================================
games_cs2() {
    header "安装 CS2 服务器"
    echo "  反恐精英 2 专用服务器"
    _ensure_docker || return 1
    mkdir -p "$GAMES_BASE/cs2"
    local port
    port="$(ask "游戏端口" "27015")"
    docker run -d --name cs2 -p "${port}:27015" -p "${port}:27015/udp" \
        -e TZ=Asia/Shanghai -e SRCDS_TOKEN=0 \
        -v "$GAMES_BASE/cs2:/home/steam/cs2-dedicated" \
        --restart=always joedwards32/cs2
    sleep 10
    success "CS2 服务器启动中"
    echo "  端口: ${port} (UDP+TCP)"
    echo "  日志: docker logs -f cs2"
}

# ============================================================
#  Valheim
# ============================================================
games_valheim() {
    header "安装 Valheim 服务器"
    echo "  英灵神殿专用服务器"
    _ensure_docker || return 1
    mkdir -p "$GAMES_BASE/valheim"
    local port
    port="$(ask "游戏端口" "2456")"
    docker run -d --name valheim \
        -p "${port}:2456/udp" -p "$((port+1)):2457/udp" \
        -e TZ=Asia/Shanghai \
        -e SERVER_NAME=ValheimServer -e WORLD_NAME=Dedicated -e SERVER_PASS=valheim123 \
        -v "$GAMES_BASE/valheim:/config" \
        --restart=always lloesche/valheim-server
    sleep 10
    success "Valheim 服务器启动中"
    echo "  端口: ${port}-$((port+1)) (UDP)"
    echo "  密码: valheim123"
}

# ============================================================
#  Factorio
# ============================================================
games_factorio() {
    header "安装 Factorio 服务器"
    echo "  异星工厂专用服务器"
    _ensure_docker || return 1
    mkdir -p "$GAMES_BASE/factorio"
    local port
    port="$(ask "游戏端口" "34197")"
    docker run -d --name factorio -p "${port}:34197/udp" \
        -e TZ=Asia/Shanghai \
        -v "$GAMES_BASE/factorio:/factorio" \
        --restart=always factoriotools/factorio
    sleep 8
    success "Factorio 服务器启动中"
    echo "  端口: ${port} (UDP)"
}

# ============================================================
#  Rust
# ============================================================
games_rust() {
    header "安装 Rust 服务器"
    echo "  腐蚀专用服务器"
    _ensure_docker || return 1
    mkdir -p "$GAMES_BASE/rust"
    local port rcon_port
    port="$(ask "游戏端口" "28015")"
    rcon_port="$(ask "RCON端口" "28016")"
    docker run -d --name rust \
        -p "${port}:28015/udp" -p "${rcon_port}:28016/tcp" \
        -e TZ=Asia/Shanghai -e RUST_RCON_PASSWORD=rust123 \
        -v "$GAMES_BASE/rust:/steamcmd/rust" \
        --restart=always didstopia/rust-server
    sleep 15
    success "Rust 服务器启动中"
    echo "  游戏端口: ${port} (UDP), RCON: ${rcon_port}"
}

# ============================================================
#  Satisfactory
# ============================================================
games_satisfactory() {
    header "安装 Satisfactory 服务器"
    echo "  幸福工厂专用服务器"
    _ensure_docker || return 1
    mkdir -p "$GAMES_BASE/satisfactory"
    local port
    port="$(ask "游戏端口" "7777")"
    docker run -d --name satisfactory \
        -p "${port}:7777/udp" -p "$((port+1)):7778/udp" \
        -e TZ=Asia/Shanghai \
        -v "$GAMES_BASE/satisfactory:/config" \
        --restart=always wolveix/satisfactory-server:latest
    sleep 10
    success "Satisfactory 服务器启动中"
    echo "  端口: ${port}-$((port+1)) (UDP)"
}

# ============================================================
#  V Rising
# ============================================================
games_vrising() {
    header "安装 V Rising 服务器"
    echo "  夜族崛起专用服务器"
    _ensure_docker || return 1
    mkdir -p "$GAMES_BASE/vrising"
    local port query_port
    port="$(ask "游戏端口" "9876")"
    query_port="$(ask "查询端口" "9877")"
    docker run -d --name vrising \
        -p "${port}:9876/udp" -p "${query_port}:9877/udp" \
        -e TZ=Asia/Shanghai \
        -v "$GAMES_BASE/vrising:/vrising" \
        --restart=always trueosiris/vrising
    sleep 10
    success "V Rising 服务器启动中"
    echo "  游戏端口: ${port}, 查询端口: ${query_port}"
}

# ============================================================
#  菜单
# ============================================================
games_menu() {
    while true; do
        header "游戏服务器"
        echo "  1) CS2           (反恐精英2)"
        echo "  2) Valheim       (英灵神殿)"
        echo "  3) Factorio      (异星工厂)"
        echo "  4) Rust          (腐蚀)"
        echo "  5) Satisfactory  (幸福工厂)"
        echo "  6) V Rising      (夜族崛起)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) games_cs2; pause ;;
            2) games_valheim; pause ;;
            3) games_factorio; pause ;;
            4) games_rust; pause ;;
            5) games_satisfactory; pause ;;
            6) games_vrising; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    games_menu
fi
