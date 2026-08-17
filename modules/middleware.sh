#!/usr/bin/env bash
# ============================================================
#  middleware.sh - 后端中间件
#  RabbitMQ / Meilisearch / Memcached / InfluxDB
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MW_BASE="${HOME}/middleware"

# ============================================================
#  RabbitMQ
# ============================================================
middleware_rabbitmq() {
    header "安装 RabbitMQ"
    echo "  消息队列，带管理面板"
    _ensure_docker || return 1
    mkdir -p "$MW_BASE/rabbitmq"
    local port mgmt_port
    port="$(ask "AMQP端口" "5672")"
    mgmt_port="$(ask "管理面板端口" "15672")"
    step "启动 RabbitMQ (含管理插件)"
    docker run -d \
        --name rabbitmq \
        -p "${port}:5672" -p "${mgmt_port}:15672" \
        -e TZ=Asia/Shanghai \
        -e RABBITMQ_DEFAULT_USER=admin \
        -e RABBITMQ_DEFAULT_PASS=admin123 \
        -v "$MW_BASE/rabbitmq:/var/lib/rabbitmq" \
        --restart=always \
        rabbitmq:3-management
    sleep 5
    success "RabbitMQ 部署完成"
    echo "  管理面板: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${mgmt_port}"
    echo "  账号: admin / admin123"
    echo "  AMQP: ${port}"
}

# ============================================================
#  Meilisearch
# ============================================================
middleware_meilisearch() {
    header "安装 Meilisearch"
    echo "  轻量搜索引擎，比 Elasticsearch 简单"
    _ensure_docker || return 1
    mkdir -p "$MW_BASE/meilisearch"
    local port master_key
    port="$(ask "HTTP端口" "7700")"
    master_key="$(ask "Master Key(留空不设)" "")"
    local extra=""
    [ -n "$master_key" ] && extra="-e MEILI_MASTER_KEY=$master_key"
    step "启动 Meilisearch"
    docker run -d \
        --name meilisearch \
        -p "${port}:7700" \
        -e TZ=Asia/Shanghai \
        $extra \
        -v "$MW_BASE/meilisearch:/meili_data" \
        --restart=always \
        getmeili/meilisearch:latest
    sleep 3
    success "Meilisearch 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  Master Key: ${master_key:-无}"
}

# ============================================================
#  Memcached
# ============================================================
middleware_memcached() {
    header "安装 Memcached"
    echo "  内存缓存服务"
    _ensure_docker || return 1
    local port memory
    port="$(ask "端口" "11211")"
    memory="$(ask "最大内存(MB)" "64")"
    step "启动 Memcached"
    docker run -d \
        --name memcached \
        -p "${port}:11211" \
        --restart=always \
        memcached:latest memcached -m "$memory"
    sleep 2
    success "Memcached 部署完成"
    echo "  端口: ${port}, 内存: ${memory}MB"
    echo "  测试: echo 'stats' | nc localhost ${port}"
}

# ============================================================
#  InfluxDB
# ============================================================
middleware_influxdb() {
    header "安装 InfluxDB"
    echo "  时序数据库，适合监控数据存储"
    _ensure_docker || return 1
    mkdir -p "$MW_BASE/influxdb"
    local port
    port="$(ask "HTTP端口" "8086")"
    step "启动 InfluxDB"
    docker run -d \
        --name influxdb \
        -p "${port}:8086" \
        -e TZ=Asia/Shanghai \
        -v "$MW_BASE/influxdb:/var/lib/influxdb2" \
        --restart=always \
        influxdb:2
    sleep 5
    success "InfluxDB 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${port}"
    echo "  首次访问完成初始化设置"
}

# ============================================================
#  状态查看
# ============================================================
middleware_status() {
    header "中间件状态"
    echo ""
    if has_cmd docker; then
        for c in rabbitmq meilisearch memcached influxdb; do
            docker inspect "$c" &>/dev/null && {
                local status
                status="$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)"
                echo "  ✓ $c: $status"
            }
        done
    fi
}

# ============================================================
#  菜单
# ============================================================
middleware_menu() {
    while true; do
        header "后端中间件"
        echo "  1) RabbitMQ (消息队列)"
        echo "  2) Meilisearch (搜索引擎)"
        echo "  3) Memcached (内存缓存)"
        echo "  4) InfluxDB (时序数据库)"
        echo "  5) 查看运行状态"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) middleware_rabbitmq; pause ;;
            2) middleware_meilisearch; pause ;;
            3) middleware_memcached; pause ;;
            4) middleware_influxdb; pause ;;
            5) middleware_status; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    middleware_menu
fi
