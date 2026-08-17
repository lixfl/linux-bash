#!/usr/bin/env bash
# ============================================================
#  bi.sh - 数据可视化 / BI / 链路追踪
#  Metabase / Superset / Redash / Tempo / Jaeger
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
BI_BASE="${HOME}/bi"

# ============================================================
#  Metabase
# ============================================================
bi_metabase() {
    header "安装 Metabase"
    echo "  开源 BI，拖拽式数据分析，零代码"
    _ensure_docker || return 1
    mkdir -p "$BI_BASE/metabase"
    local port
    port="$(ask "Web端口" "3000")"
    docker run -d --name metabase -p "${port}:3000" \
        -e TZ=Asia/Shanghai \
        -e MB_DB_TYPE=h2 \
        -v "$BI_BASE/metabase:/metabase-data" \
        --restart=always metabase/metabase
    sleep 15
    success "Metabase 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  首次访问完成初始化设置"
}

# ============================================================
#  Apache Superset
# ============================================================
bi_superset() {
    header "安装 Apache Superset"
    echo "  企业级数据可视化平台"
    _ensure_docker || return 1
    local dir="$BI_BASE/superset"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8088")"
    step "克隆配置"
    git clone --depth 1 https://github.com/apache/superset.git . 2>/dev/null || true
    cd docker 2>/dev/null || cd .
    [ -f .env-non-dev ] && sed -i "s/8088:8088/${port}:8088/" docker-compose-non-dev.yml 2>/dev/null
    docker compose -f docker-compose-non-dev.yml up -d 2>/dev/null || warn "启动失败，Superset 依赖较多"
    sleep 20
    success "Superset 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  默认账号: admin / admin"
}

# ============================================================
#  Redash
# ============================================================
bi_redash() {
    header "安装 Redash"
    echo "  轻量 BI，SQL 查询 + 仪表盘"
    _ensure_docker || return 1
    local dir="$BI_BASE/redash"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "5000")"
    step "克隆配置"
    git clone --depth 1 https://github.com/getredash/setup.git . 2>/dev/null || true
    [ -f setup.sh ] && sed -i "s/\"5000:5000\"/\"${port}:5000\"/" setup.sh 2>/dev/null
    bash setup.sh 2>/dev/null || warn "安装脚本执行失败，请手动配置"
    success "Redash 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  Grafana Tempo
# ============================================================
bi_tempo() {
    header "安装 Grafana Tempo"
    echo "  分布式链路追踪（配合已有 Grafana）"
    _ensure_docker || return 1
    local dir="$BI_BASE/tempo"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "端口" "3200")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  tempo:
    image: grafana/tempo:latest
    container_name: tempo
    ports:
      - "${port}:3200"
      - "4317:4317"
      - "4318:4318"
    command: ["-config.file=/etc/tempo.yaml"]
    volumes:
      - ./tempo.yaml:/etc/tempo.yaml
      - ./data:/tmp/tempo
    restart: always
EOF
    cat > tempo.yaml <<'EOF'
server:
  http_listen_port: 3200
distributor:
  receivers:
    otlp:
      protocols:
        grpc:
        http:
storage:
  trace:
    backend: local
    local:
      path: /tmp/tempo/traces
    wal:
      path: /tmp/tempo/wal
EOF
    docker compose up -d
    sleep 5
    success "Tempo 部署完成: http://localhost:${port}"
    echo "  OTLP gRPC: 4317, OTLP HTTP: 4318"
    echo "  在 Grafana 中添加 Tempo 数据源即可查看链路"
}

# ============================================================
#  Jaeger
# ============================================================
bi_jaeger() {
    header "安装 Jaeger"
    echo "  分布式链路追踪（CNCF）"
    _ensure_docker || return 1
    local port
    port="$(ask "Web端口" "16686")"
    docker run -d --name jaeger \
        -p "${port}:16686" -p 4317:4317 -p 4318:4318 \
        -e COLLECTOR_OTLP_ENABLED=true \
        --restart=always jaegertracing/all-in-one:latest
    sleep 5
    success "Jaeger 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  OTLP gRPC: 4317, OTLP HTTP: 4318"
}

# ============================================================
#  菜单
# ============================================================
bi_menu() {
    while true; do
        header "数据可视化 / BI / 链路追踪"
        echo "  1) Metabase    (零代码BI)"
        echo "  2) Superset    (企业级可视化)"
        echo "  3) Redash      (轻量BI)"
        echo "  4) Tempo       (Grafana链路追踪)"
        echo "  5) Jaeger      (分布式追踪)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) bi_metabase; pause ;;
            2) bi_superset; pause ;;
            3) bi_redash; pause ;;
            4) bi_tempo; pause ;;
            5) bi_jaeger; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    bi_menu
fi
