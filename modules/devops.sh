#!/usr/bin/env bash
# ============================================================
#  devops.sh - DevOps 可视化工具一键部署
#  Portainer / Nginx Proxy Manager / Uptime Kuma / Netdata / Glances
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

DEVOPS_BASE="${HOME}/devops"

# ============================================================
#  1. Portainer
# ============================================================
devops_portainer() {
    header "安装 Portainer"
    echo "  Docker 容器可视化管理面板，支持多节点管理"
    _ensure_docker || return 1
    mkdir -p "$DEVOPS_BASE/portainer"
    local port
    port="$(ask "Web端口(HTTPS)" "9443")"
    step "启动 Portainer"
    docker run -d \
        --name portainer \
        -p "${port}:9443" \
        -e TZ=Asia/Shanghai \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$DEVOPS_BASE/portainer:/data" \
        --restart=always \
        portainer/portainer-ce:latest
    sleep 3
    success "Portainer 部署完成"
    echo "  访问: https://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  首次访问设置管理员密码"
}

# ============================================================
#  2. Nginx Proxy Manager
# ============================================================
devops_npm() {
    header "安装 Nginx Proxy Manager"
    echo "  反向代理面板，自动签发 Let's Encrypt SSL 证书"
    _ensure_docker || return 1
    local dir="$DEVOPS_BASE/npm"
    mkdir -p "$dir" && cd "$dir" || return 1
    step "生成 Docker Compose"
    cat > docker-compose.yml <<'EOF'
version: '3.8'
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    environment:
      - TZ=Asia/Shanghai
    restart: always
EOF
    step "启动 Nginx Proxy Manager"
    docker compose up -d
    sleep 5
    success "Nginx Proxy Manager 部署完成"
    echo "  管理面板: http://$(hostname -I 2>/dev/null | awk '{print $1}'):81"
    echo "  默认账号: admin@example.com / changeme"
    echo "  80/443 端口用于反代网站流量"
}

# ============================================================
#  3. Uptime Kuma
# ============================================================
devops_uptime() {
    header "安装 Uptime Kuma"
    echo "  高颜值网站/服务监控告警，支持多种通知渠道"
    _ensure_docker || return 1
    mkdir -p "$DEVOPS_BASE/uptime-kuma"
    local port
    port="$(ask "Web端口" "3001")"
    step "启动 Uptime Kuma"
    docker run -d \
        --name uptime-kuma \
        -p "${port}:3001" \
        -e TZ=Asia/Shanghai \
        -v "$DEVOPS_BASE/uptime-kuma:/app/data" \
        --restart=always \
        louislam/uptime-kuma:1
    sleep 3
    success "Uptime Kuma 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
}

# ============================================================
#  4. Netdata
# ============================================================
devops_netdata() {
    header "安装 Netdata"
    echo "  实时系统性能监控，开箱即用，支持告警"
    _ensure_docker || return 1
    local port
    port="$(ask "Web端口" "19999")"
    step "启动 Netdata"
    docker run -d \
        --name netdata \
        -p "${port}:19999" \
        -e TZ=Asia/Shanghai \
        -v /proc:/host/proc:ro \
        -v /sys:/host/sys:ro \
        -v /etc/os-release:/host/etc/os-release:ro \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        --cap-add SYS_PTRACE \
        --security-opt apparmor=unconfined \
        --restart=always \
        netdata/netdata:latest
    sleep 5
    success "Netdata 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
}

# ============================================================
#  5. Glances
# ============================================================
devops_glances() {
    header "安装 Glances"
    echo "  跨平台系统监控（htop 升级版），支持 Web UI 和 API"
    echo ""
    echo "  1) Docker 部署 (Web UI)"
    echo "  2) pip 安装 (命令行)"
    local method
    method="$(ask "选择方式" "1")"
    if [ "$method" = "1" ]; then
        _ensure_docker || return 1
        local port
        port="$(ask "Web端口" "61208")"
        step "启动 Glances"
        docker run -d \
            --name glances \
            -p "${port}:61208" \
            -e TZ=Asia/Shanghai \
            -v /var/run/docker.sock:/var/run/docker.sock:ro \
            --restart=always \
            nicolargo/glances:latest
        sleep 3
        success "Glances 部署完成"
        echo "  Web UI: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    else
        step "pip 安装 glances"
        pip3 install --user glances bottle 2>/dev/null || pip install glances bottle
        success "Glances 安装完成"
        echo "  命令行: glances"
        echo "  Web UI: glances -w (访问 http://localhost:61208)"
    fi
}


# ============================================================
#  Cockpit
# ============================================================
devops_cockpit() {
    require_root || return 1
    header "安装 Cockpit"
    echo "  RedHat 官方 Web 服务器管理面板"
    if has_cmd cockpit-bridge; then
        success "Cockpit 已安装"
        svc_start cockpit 2>/dev/null
        echo "  访问: https://$(hostname -I 2>/dev/null | awk '{print $1}'):9090"
        return 0
    fi
    pkg_install cockpit
    svc_enable cockpit 2>/dev/null
    svc_start cockpit 2>/dev/null
    success "Cockpit 安装完成"
    echo "  访问: https://$(hostname -I 2>/dev/null | awk '{print $1}'):9090"
    echo "  用系统账号登录"
}

# ============================================================
#  GoAccess
# ============================================================
devops_goaccess() {
    header "安装 GoAccess"
    echo "  Nginx/Apache 日志实时可视化分析"
    if ! has_cmd goaccess; then
        pkg_install goaccess 2>/dev/null || {
            step "编译安装 GoAccess"
            pkg_install build-essential libncursesw5-dev libgeoip-dev libtokyocabinet-dev
            curl -fsSL https://tar.goaccess.io/goaccess-1.9.3.tar.gz -o /tmp/goaccess.tar.gz
            tar -xzf /tmp/goaccess.tar.gz -C /tmp
            cd /tmp/goaccess-* && ./configure --enable-utf8 --enable-geoip=mmdb && make && make install
        }
    fi
    success "GoAccess 安装完成: $(goaccess --version 2>/dev/null | head -1)"
    echo "  实时分析: goaccess /var/log/nginx/access.log -c"
    echo "  生成HTML: goaccess /var/log/nginx/access.log -o report.html --log-format=COMBINED"
}


# ============================================================
#  Prometheus + Grafana
# ============================================================
devops_prometheus() {
    header "安装 Prometheus + Grafana"
    echo "  专业监控全套：Node Exporter + Prometheus + Grafana"
    _ensure_docker || return 1
    local dir="$DEVOPS_BASE/prometheus"
    mkdir -p "$dir" && cd "$dir" || return 1
    local grafana_port prom_port
    grafana_port="$(ask "Grafana端口" "3000")"
    prom_port="$(ask "Prometheus端口" "9090")"
    step "生成配置"
    cat > prometheus.yml <<EOF
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
EOF
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: always
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "${prom_port}:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus_data:/prometheus
    restart: always
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "${grafana_port}:3000"
    volumes:
      - ./grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    restart: always
EOF
    step "启动 Prometheus + Grafana"
    docker compose up -d
    sleep 5
    success "Prometheus + Grafana 部署完成"
    echo "  Grafana: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${grafana_port} (admin/admin123)"
    echo "  Prometheus: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${prom_port}"
    echo "  推荐仪表盘ID: 1860 (Node Exporter Full)"
}

# ============================================================
#  Loki + Promtail
# ============================================================
devops_loki() {
    header "安装 Loki + Promtail"
    echo "  轻量日志聚合（Grafana 生态）"
    _ensure_docker || return 1
    local dir="$DEVOPS_BASE/loki"
    mkdir -p "$dir" && cd "$dir" || return 1
    local loki_port
    loki_port="$(ask "Loki端口" "3100")"
    step "生成配置并启动"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  loki:
    image: grafana/loki:latest
    container_name: loki
    ports:
      - "${loki_port}:3100"
    volumes:
      - ./loki:/etc/loki
    restart: always
  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
    restart: always
EOF
    docker compose up -d
    sleep 3
    success "Loki 部署完成"
    echo "  Loki: http://localhost:${loki_port}"
    echo "  在 Grafana 中添加 Loki 数据源即可查询日志"
}

# ============================================================
#  状态查看
# ============================================================
devops_status() {
    header "DevOps 工具状态"
    echo ""
    if has_cmd docker; then
        section "Docker 容器"
        for c in portainer npm uptime-kuma netdata glances; do
            docker inspect "$c" &>/dev/null && {
                local status
                status="$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)"
                echo "  ✓ $c: $status"
            }
        done
    fi
    has_cmd glances && echo "  ✓ glances(命令行): $(glances --version 2>/dev/null | head -1)"
    echo ""
    section "安装目录"
    [ -d "$DEVOPS_BASE" ] && ls -1 "$DEVOPS_BASE" | sed 's/^/  • /' || echo "  暂无"
}

# ============================================================
#  菜单
# ============================================================
devops_menu() {
    while true; do
        header "DevOps 可视化工具"
        echo "  自动配置 Docker 环境，数据统一存放在 ~/devops/"
        echo ""
        echo "  1) Portainer        (Docker容器可视化管理)"
        echo "  2) Nginx Proxy Mgr  (反向代理+自动SSL)"
        echo "  3) Uptime Kuma      (服务监控告警)"
        echo "  4) Netdata          (实时性能监控)"
        echo "  5) Glances          (系统监控, Web/CLI)"
        echo "  6) Cockpit          (Web服务器管理面板)"
        echo "  7) GoAccess         (日志可视化分析)"
        echo "  8) Prometheus+Grafana (专业监控)"
        echo "  9) Loki+Promtail    (日志聚合)"
        echo " 10) 查看已安装状态"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "选择要部署的工具" "")"
        case "$choice" in
            1) devops_portainer; pause ;;
            2) devops_npm; pause ;;
            3) devops_uptime; pause ;;
            4) devops_netdata; pause ;;
            5) devops_glances; pause ;;
            6) devops_cockpit; pause ;;
            7) devops_goaccess; pause ;;
            8) devops_prometheus; pause ;;
            9) devops_loki; pause ;;
            10) devops_status; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    devops_menu
fi
