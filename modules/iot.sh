#!/usr/bin/env bash
# ============================================================
#  iot.sh - 智能家居 / IoT
#  Frigate / Scrypted / Homebridge / Node-RED / ThingsBoard / OctoPrint
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
IOT_BASE="${HOME}/iot"

# ============================================================
#  Frigate
# ============================================================
iot_frigate() {
    header "安装 Frigate"
    echo "  摄像头 NVR + AI 物体/人脸检测（需GPU/TPU）"
    _ensure_docker || return 1
    local dir="$IOT_BASE/frigate"
    mkdir -p "$dir/config" "$dir/storage"
    local port
    port="$(ask "Web端口" "5000")"
    cat > "$dir/config/config.yml" <<'EOF'
mqtt:
  enabled: false
cameras:
  demo:
    ffmpeg:
      inputs:
        - path: rtsp://demo:demo@demo:554/stream
          roles:
            - detect
    detect:
      width: 1280
      height: 720
EOF
    docker run -d --name frigate -p "${port}:5000" -p 8554:8554 -p 8555:8555/tcp -p 8555:8555/udp \
        -e TZ=Asia/Shanghai \
        -v "$dir/config:/config" -v "$dir/storage:/media/frigate" \
        --gpus all 2>/dev/null \
        --restart=always ghcr.io/blakeblackshear/frigate:stable
    sleep 8
    success "Frigate 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    warn "需编辑 config/config.yml 配置真实摄像头 RTSP 地址"
}

# ============================================================
#  Scrypted
# ============================================================
iot_scrypted() {
    header "安装 Scrypted"
    echo "  智能家居桥接（HomeKit/Google/Alexa）"
    _ensure_docker || return 1
    local dir="$IOT_BASE/scrypted"
    mkdir -p "$dir"
    local port
    port="$(ask "Web端口" "10443")"
    docker run -d --name scrypted -p "${port}:10443" -p 10444:10444 \
        -e TZ=Asia/Shanghai \
        -v "$dir:/server/volume" \
        --restart=always koush/scrypted
    sleep 8
    success "Scrypted 部署完成: https://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  Homebridge
# ============================================================
iot_homebridge() {
    header "安装 Homebridge"
    echo "  把非 HomeKit 设备接入 Apple HomeKit"
    _ensure_docker || return 1
    local dir="$IOT_BASE/homebridge"
    mkdir -p "$dir"
    local port
    port="$(ask "Web端口" "8581")"
    docker run -d --name homebridge -p "${port}:8581" \
        -e TZ=Asia/Shanghai -e PGID=1000 -e PUID=1000 \
        -v "$dir:/homebridge" \
        --net=host --restart=always homebridge/homebridge:latest
    sleep 8
    success "Homebridge 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  默认账号: admin / admin"
}

# ============================================================
#  Node-RED
# ============================================================
iot_nodered() {
    header "安装 Node-RED"
    echo "  可视化 IoT 流程编排"
    _ensure_docker || return 1
    local dir="$IOT_BASE/nodered"
    mkdir -p "$dir"
    local port
    port="$(ask "Web端口" "1880")"
    docker run -d --name nodered -p "${port}:1880" \
        -e TZ=Asia/Shanghai \
        -v "$dir:/data" \
        --restart=always nodered/node-red
    sleep 5
    success "Node-RED 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  ThingsBoard
# ============================================================
iot_thingsboard() {
    header "安装 ThingsBoard"
    echo "  开源 IoT 平台（设备管理/数据可视化）"
    _ensure_docker || return 1
    local dir="$IOT_BASE/thingsboard"
    mkdir -p "$dir/data" "$dir/logs"
    local port
    port="$(ask "Web端口" "9090")"
    docker run -d --name thingsboard -p "${port}:9090" -p 1883:1883 -p 5683:5683/udp \
        -e TZ=Asia/Shanghai \
        -v "$dir/data:/data" -v "$dir/logs:/var/log/thingsboard" \
        --restart=always thingsboard/tb-postgres
    sleep 15
    success "ThingsBoard 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  管理员: sysadmin@thingsboard.org / sysadmin"
    echo "  租户: tenant@thingsboard.org / tenant"
}

# ============================================================
#  OctoPrint
# ============================================================
iot_octoprint() {
    header "安装 OctoPrint"
    echo "  3D 打印机 Web 控制"
    _ensure_docker || return 1
    local dir="$IOT_BASE/octoprint"
    mkdir -p "$dir"
    local port
    port="$(ask "Web端口" "5000")"
    docker run -d --name octoprint -p "${port}:5000" \
        -e TZ=Asia/Shanghai \
        -v "$dir:/octoprint" \
        --device=/dev/ttyUSB0 2>/dev/null \
        --restart=always octoprint/octoprint
    sleep 8
    success "OctoPrint 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    warn "需将3D打印机USB设备映射到容器: --device=/dev/ttyUSB0"
}

# ============================================================
#  菜单
# ============================================================
iot_menu() {
    while true; do
        header "智能家居 / IoT"
        echo "  1) Frigate      (摄像头NVR+AI检测)"
        echo "  2) Scrypted     (智能家居桥接)"
        echo "  3) Homebridge   (HomeKit接入)"
        echo "  4) Node-RED     (可视化流程编排)"
        echo "  5) ThingsBoard  (IoT平台)"
        echo "  6) OctoPrint    (3D打印控制)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) iot_frigate; pause ;;
            2) iot_scrypted; pause ;;
            3) iot_homebridge; pause ;;
            4) iot_nodered; pause ;;
            5) iot_thingsboard; pause ;;
            6) iot_octoprint; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    iot_menu
fi
