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
#  Kafka
# ============================================================
middleware_kafka() {
    header "安装 Kafka"
    echo "  高吞吐分布式消息队列（KRaft模式，无需ZooKeeper）"
    _ensure_docker || return 1
    local dir="$MW_BASE/kafka"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Broker端口" "9092")"
    step "启动 Kafka (KRaft)"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  kafka:
    image: bitnami/kafka:latest
    container_name: kafka
    ports:
      - "${port}:9092"
    environment:
      - KAFKA_CFG_NODE_ID=0
      - KAFKA_CFG_PROCESS_ROLES=controller,broker
      - KAFKA_CFG_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093
      - KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://localhost:${port}
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
      - KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=0@kafka:9093
      - KAFKA_CFG_CONTROLLER_LISTENER_NAMES=CONTROLLER
    volumes:
      - ./data:/bitnami/kafka
    restart: always
EOF
    docker compose up -d
    sleep 8
    success "Kafka 部署完成"
    echo "  Broker: localhost:${port}"
    echo "  创建Topic: docker exec kafka kafka-topics.sh --create --topic test --bootstrap-server localhost:9092"
}

# ============================================================
#  Elasticsearch + Kibana
# ============================================================
middleware_elasticsearch() {
    header "安装 Elasticsearch + Kibana"
    echo "  分布式搜索引擎 + 可视化分析"
    _ensure_docker || return 1
    local dir="$MW_BASE/elasticsearch"
    mkdir -p "$dir/esdata" "$dir/kibanadata" && cd "$dir" || return 1
    local es_port kb_port
    es_port="$(ask "ES端口" "9200")"
    kb_port="$(ask "Kibana端口" "5601")"
    step "调整系统参数"
    sysctl -w vm.max_map_count=262144 2>/dev/null
    step "启动 ES + Kibana"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  elasticsearch:
    image: elasticsearch:8.14.0
    container_name: elasticsearch
    ports:
      - "${es_port}:9200"
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    volumes:
      - ./esdata:/usr/share/elasticsearch/data
    restart: always
  kibana:
    image: kibana:8.14.0
    container_name: kibana
    ports:
      - "${kb_port}:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    depends_on:
      - elasticsearch
    restart: always
EOF
    docker compose up -d
    sleep 15
    success "Elasticsearch + Kibana 部署完成"
    echo "  ES: http://localhost:${es_port}"
    echo "  Kibana: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${kb_port}"
}

# ============================================================
#  Mosquitto MQTT
# ============================================================
middleware_mosquitto() {
    header "安装 Mosquitto"
    echo "  MQTT 消息代理（IoT 设备通信）"
    _ensure_docker || return 1
    mkdir -p "$MW_BASE/mosquitto/config" "$MW_BASE/mosquitto/data" "$MW_BASE/mosquitto/log"
    local port ws_port
    port="$(ask "MQTT端口" "1883")"
    ws_port="$(ask "WebSocket端口" "9001")"
    cat > "$MW_BASE/mosquitto/config/mosquitto.conf" <<EOF
listener ${port}
listener ${ws_port}
protocol websockets
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
EOF
    docker run -d --name mosquitto         -p "${port}:1883" -p "${ws_port}:9001"         -v "$MW_BASE/mosquitto/config:/mosquitto/config"         -v "$MW_BASE/mosquitto/data:/mosquitto/data"         -v "$MW_BASE/mosquitto/log:/mosquitto/log"         --restart=always eclipse-mosquitto
    sleep 3
    success "Mosquitto 部署完成"
    echo "  MQTT: ${port}, WebSocket: ${ws_port}"
}

# ============================================================
#  Pi-hole
# ============================================================
middleware_pihole() {
    header "安装 Pi-hole"
    echo "  DNS 广告过滤（全网络去广告）"
    _ensure_docker || return 1
    mkdir -p "$MW_BASE/pihole/etc" "$MW_BASE/pihole/dnsmasq"
    local port web_port password
    port="$(ask "DNS端口(53)" "53")"
    web_port="$(ask "Web端口" "8089")"
    password="$(ask "管理密码" "admin123")"
    docker run -d --name pihole         -p "${port}:53/tcp" -p "${port}:53/udp" -p "${web_port}:80"         -e TZ=Asia/Shanghai -e WEBPASSWORD="$password"         -v "$MW_BASE/pihole/etc:/etc/pihole"         -v "$MW_BASE/pihole/dnsmasq:/etc/dnsmasq.d"         --restart=always pihole/pihole:latest
    sleep 5
    success "Pi-hole 部署完成"
    echo "  管理面板: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${web_port}/admin"
    echo "  密码: $password"
    echo "  将设备 DNS 设为本机IP即可全网络去广告"
}


# ============================================================
#  ClickHouse
# ============================================================
middleware_clickhouse() {
    header "安装 ClickHouse"
    echo "  列式数据库，大数据分析场景（比ES更快）"
    _ensure_docker || return 1
    mkdir -p "$MW_BASE/clickhouse"
    local http_port tcp_port
    http_port="$(ask "HTTP端口" "8123")"
    tcp_port="$(ask "TCP端口" "9000")"
    step "启动 ClickHouse"
    docker run -d --name clickhouse         -p "${http_port}:8123" -p "${tcp_port}:9000"         -e TZ=Asia/Shanghai         -v "$MW_BASE/clickhouse:/var/lib/clickhouse"         --ulimit nofile=262144:262144         --restart=always clickhouse/clickhouse-server
    sleep 5
    success "ClickHouse 部署完成"
    echo "  HTTP: http://localhost:${http_port}"
    echo "  TCP: localhost:${tcp_port}"
    echo "  测试: curl http://localhost:${http_port}/?query=SELECT+1"
}

# ============================================================
#  NATS
# ============================================================
middleware_nats() {
    header "安装 NATS"
    echo "  轻量高性能消息系统（云原生）"
    _ensure_docker || return 1
    local port monitor_port
    port="$(ask "客户端端口" "4222")"
    monitor_port="$(ask "监控端口" "8222")"
    docker run -d --name nats         -p "${port}:4222" -p "${monitor_port}:8222"         --restart=always nats:latest -js -m 8222
    sleep 2
    success "NATS 部署完成"
    echo "  客户端: nats://localhost:${port}"
    echo "  监控: http://localhost:${monitor_port}"
}

# ============================================================
#  APISIX
# ============================================================
middleware_apisix() {
    header "安装 APISIX"
    echo "  云原生 API 网关（Apache 顶级项目）"
    _ensure_docker || return 1
    local dir="$MW_BASE/apisix"
    mkdir -p "$dir" && cd "$dir" || return 1
    local http_port admin_port
    http_port="$(ask "HTTP端口" "9080")"
    admin_port="$(ask "Admin端口" "9180")"
    step "生成配置并启动"
    cat > config.yaml <<EOF
apisix:
  node_listen: 9080
  admin_key:
    - name: admin
      key: edd1c9f034335f136f87ad84b625c8f1
      role: admin
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - "http://etcd:2379"
EOF
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  apisix:
    image: apache/apisix:latest
    container_name: apisix
    ports:
      - "${http_port}:9080"
      - "${admin_port}:9180"
    volumes:
      - ./config.yaml:/usr/local/apisix/conf/config.yaml:ro
    depends_on:
      - etcd
    restart: always
  etcd:
    image: bitnami/etcd:latest
    environment:
      - ALLOW_NONE_AUTHENTICATION=yes
    restart: always
EOF
    docker compose up -d
    sleep 8
    success "APISIX 部署完成"
    echo "  HTTP: http://localhost:${http_port}"
    echo "  Admin: http://localhost:${admin_port}"
    echo "  Admin Key: edd1c9f034335f136f87ad84b625c8f1"
}

# ============================================================
#  状态查看
# ============================================================
middleware_status() {
    header "中间件状态"
    echo ""
    if has_cmd docker; then
        for c in rabbitmq meilisearch memcached influxdb kafka elasticsearch kibana mosquitto pihole clickhouse nats apisix; do
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
        echo "  5) Kafka (消息队列)"
        echo "  6) Elasticsearch+Kibana (搜索+可视化)"
        echo "  7) Mosquitto (MQTT/IoT)"
        echo "  8) Pi-hole (DNS广告过滤)"
        echo "  9) ClickHouse (列式数据库)"
        echo " 10) NATS (云原生消息)"
        echo " 11) APISIX (API网关)"
        echo " 12) 查看运行状态"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) middleware_rabbitmq; pause ;;
            2) middleware_meilisearch; pause ;;
            3) middleware_memcached; pause ;;
            4) middleware_influxdb; pause ;;
            5) middleware_kafka; pause ;;
            6) middleware_elasticsearch; pause ;;
            7) middleware_mosquitto; pause ;;
            8) middleware_pihole; pause ;;
            9) middleware_clickhouse; pause ;;
            10) middleware_nats; pause ;;
            11) middleware_apisix; pause ;;
            12) middleware_status; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    middleware_menu
fi
