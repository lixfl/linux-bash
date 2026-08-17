#!/usr/bin/env bash
# ============================================================
#  database.sh - 数据库服务一键安装
#  MySQL / PostgreSQL / Redis / MongoDB
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# ============================================================
#  MySQL / MariaDB
# ============================================================
database_mysql() {
    require_root || return 1
    header "安装 MySQL / MariaDB"
    if has_cmd mysql; then
        warn "MySQL 已安装: $(mysql --version)"
        confirm "重新安装?" "n" || return 0
        pkg_remove mysql-server mysql 2>/dev/null
    fi
    echo "  1) MySQL 8.0"
    echo "  2) MariaDB 10.11"
    local choice
    choice="$(ask "选择" "1")"
    if [ "$choice" = "1" ]; then
        pkg_install mysql-server
    else
        pkg_install mariadb-server
    fi
    svc_enable mysql 2>/dev/null || svc_enable mariadb 2>/dev/null
    svc_start mysql 2>/dev/null || svc_start mariadb 2>/dev/null
    sleep 2
    local root_pwd
    root_pwd="$(ask "设置 root 密码" "root123456")"
    step "初始化安全配置"
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$root_pwd'; FLUSH PRIVILEGES;" 2>/dev/null || \
    mysqladmin -u root password "$root_pwd" 2>/dev/null
    if confirm "允许 root 远程访问?" "n"; then
        mysql -uroot -p"$root_pwd" -e "CREATE USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY '$root_pwd'; GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;" 2>/dev/null
        sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf 2>/dev/null
        svc_restart mysql 2>/dev/null
    fi
    success "MySQL 安装完成"
    echo "  root 密码: $root_pwd"
    echo "  端口: 3306"
    echo "  管理: mysql -uroot -p"
}

# ============================================================
#  PostgreSQL
# ============================================================
database_postgres() {
    require_root || return 1
    header "安装 PostgreSQL"
    if has_cmd psql; then
        warn "PostgreSQL 已安装: $(psql --version)"
        confirm "重新安装?" "n" || return 0
        pkg_remove postgresql 2>/dev/null
    fi
    pkg_install postgresql postgresql-contrib
    svc_enable postgresql 2>/dev/null
    svc_start postgresql 2>/dev/null
    sleep 2
    local pg_pwd
    pg_pwd="$(ask "设置 postgres 密码" "postgres123")"
    step "设置密码和远程访问"
    sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$pg_pwd';" 2>/dev/null
    if confirm "允许远程访问?" "n"; then
        local pg_hba
        pg_hba="$(find /etc/postgresql -name pg_hba.conf 2>/dev/null | head -1)"
        local pg_conf
        pg_conf="$(find /etc/postgresql -name postgresql.conf 2>/dev/null | head -1)"
        [ -n "$pg_hba" ] && echo "host all all 0.0.0.0/0 md5" >> "$pg_hba"
        [ -n "$pg_conf" ] && sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" "$pg_conf"
        svc_restart postgresql 2>/dev/null
    fi
    if confirm "安装 pgvector 扩展?" "y"; then
        pkg_install postgresql-16-pgvector 2>/dev/null || pkg_install pgvector 2>/dev/null
    fi
    success "PostgreSQL 安装完成"
    echo "  postgres 密码: $pg_pwd"
    echo "  端口: 5432"
    echo "  管理: sudo -u postgres psql"
}

# ============================================================
#  Redis
# ============================================================
database_redis() {
    require_root || return 1
    header "安装 Redis"
    if has_cmd redis-server; then
        warn "Redis 已安装: $(redis-server --version)"
        confirm "重新安装?" "n" || return 0
        pkg_remove redis-server 2>/dev/null
    fi
    pkg_install redis-server
    local redis_pwd
    redis_pwd="$(ask "设置密码(留空无密码)" "")"
    step "配置 Redis"
    local conf="/etc/redis/redis.conf"
    [ -f "$conf" ] || conf="/etc/redis.conf"
    if [ -f "$conf" ]; then
        sed -i 's/^supervised.*/supervised systemd/' "$conf"
        sed -i 's/^bind .*/bind 0.0.0.0/' "$conf"
        [ -n "$redis_pwd" ] && sed -i "s/^# requirepass.*/requirepass $redis_pwd/" "$conf"
        sed -i 's/^appendonly.*/appendonly yes/' "$conf"
    fi
    svc_enable redis-server 2>/dev/null || svc_enable redis 2>/dev/null
    svc_restart redis-server 2>/dev/null || svc_restart redis 2>/dev/null
    success "Redis 安装完成"
    echo "  密码: ${redis_pwd:-无}"
    echo "  端口: 6379"
    echo "  持久化: AOF 已开启"
    echo "  测试: redis-cli${redis_pwd:+ -a $redis_pwd} ping"
}

# ============================================================
#  MongoDB
# ============================================================
database_mongo() {
    require_root || return 1
    header "安装 MongoDB"
    if has_cmd mongod; then
        warn "MongoDB 已安装: $(mongod --version 2>/dev/null | head -1)"
        confirm "重新安装?" "n" || return 0
        pkg_remove mongodb-org 2>/dev/null
    fi
    if [ "$PKG_MANAGER" = "apt" ]; then
        step "添加 MongoDB 官方源"
        curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor 2>/dev/null
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-7.0.list
        apt-get update -qq
        pkg_install mongodb-org
    else
        pkg_install mongodb-org mongodb 2>/dev/null || pkg_install mongodb 2>/dev/null
    fi
    svc_enable mongod 2>/dev/null
    svc_start mongod 2>/dev/null
    sleep 2
    local mongo_user mongo_pwd
    mongo_user="$(ask "管理员用户名" "admin")"
    mongo_pwd="$(ask "管理员密码" "admin123")"
    step "创建管理员用户"
    mongosh --eval "db.getSiblingDB('admin').createUser({user:'$mongo_user',pwd:'$mongo_pwd',roles:[{role:'root',db:'admin'}]})" 2>/dev/null || \
    mongo --eval "db.getSiblingDB('admin').createUser({user:'$mongo_user',pwd:'$mongo_pwd',roles:[{role:'root',db:'admin'}]})" 2>/dev/null
    success "MongoDB 安装完成"
    echo "  用户: $mongo_user / $mongo_pwd"
    echo "  端口: 27017"
    echo "  管理: mongosh -u $mongo_user -p $mongo_pwd --authenticationDatabase admin"
}


# ============================================================
#  数据库管理面板 (Docker)
# ============================================================
database_panels() {
    header "数据库管理面板"
    echo "  1) phpMyAdmin (MySQL/MariaDB)"
    echo "  2) pgAdmin (PostgreSQL)"
    echo "  3) RedisInsight (Redis)"
    echo "  4) Mongo Express (MongoDB)"
    echo "  0) 返回"
    local opt
    opt="$(ask "选择" "1")"
    _ensure_docker || return 1
    case "$opt" in
        1)
            local port
            port="$(ask "端口" "8081")"
            docker run -d --name phpmyadmin -p "${port}:80" -e PMA_ARBITRARY=1 --restart=always phpmyadmin:latest
            success "phpMyAdmin: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}" ;;
        2)
            local port
            port="$(ask "端口" "8082")"
            docker run -d --name pgadmin -p "${port}:80" -e PGADMIN_DEFAULT_EMAIL=admin@example.com -e PGADMIN_DEFAULT_PASSWORD=admin123 --restart=always dpage/pgadmin4
            success "pgAdmin: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port} (admin@example.com/admin123)" ;;
        3)
            local port
            port="$(ask "端口" "8083")"
            docker run -d --name redisinsight -p "${port}:5540" --restart=always redislabs/redisinsight:latest
            success "RedisInsight: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}" ;;
        4)
            local port
            port="$(ask "端口" "8084")"
            docker run -d --name mongo-express -p "${port}:8081" -e ME_CONFIG_MONGODB_URL=mongodb://host.docker.internal:27017 --add-host=host.docker.internal:host-gateway --restart=always mongo-express
            success "Mongo Express: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}" ;;
        0) return 0 ;;
        *) warn "无效选项" ;;
    esac
}


# ============================================================
#  TiDB
# ============================================================
database_tidb() {
    header "安装 TiDB"
    echo "  分布式 HTAP 数据库（MySQL 兼容）"
    _ensure_docker || return 1
    local port
    port="$(ask "MySQL端口" "4000")"
    docker run -d --name tidb -p "${port}:4000" -p 10080:10080         -e TZ=Asia/Shanghai         --restart=always pingcap/tidb:latest
    sleep 8
    success "TiDB 部署完成"
    echo "  MySQL兼容: mysql -h 127.0.0.1 -P ${port} -u root"
    echo "  状态: http://localhost:10080/status"
}

# ============================================================
#  CockroachDB
# ============================================================
database_cockroach() {
    header "安装 CockroachDB"
    echo "  分布式 SQL（PostgreSQL 兼容）"
    _ensure_docker || return 1
    local dir="$HOME/cockroach"
    mkdir -p "$dir"
    local port sql_port
    port="$(ask "Web端口" "8080")"
    sql_port="$(ask "SQL端口" "26257")"
    docker run -d --name cockroach         -p "${sql_port}:26257" -p "${port}:8080"         -v "$dir:/cockroach/cockroach-data"         --restart=always cockroachdb/cockroach:latest start-single-node --insecure
    sleep 8
    success "CockroachDB 部署完成"
    echo "  SQL: postgresql://root@localhost:${sql_port}/defaultdb?sslmode=disable"
    echo "  控制台: http://localhost:${port}"
}

# ============================================================
#  Neo4j
# ============================================================
database_neo4j() {
    header "安装 Neo4j"
    echo "  图数据库（知识图谱/关系分析）"
    _ensure_docker || return 1
    local dir="$HOME/neo4j"
    mkdir -p "$dir/data" "$dir/logs" "$dir/plugins"
    local port bolt_port
    port="$(ask "Web端口" "7474")"
    bolt_port="$(ask "Bolt端口" "7687")"
    docker run -d --name neo4j         -p "${port}:7474" -p "${bolt_port}:7687"         -e NEO4J_AUTH=neo4j/neo4j123         -e NEO4J_PLUGINS='["apoc"]'         -v "$dir/data:/data" -v "$dir/logs:/logs" -v "$dir/plugins:/plugins"         --restart=always neo4j:latest
    sleep 10
    success "Neo4j 部署完成"
    echo "  控制台: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  账号: neo4j / neo4j123"
}

# ============================================================
#  Qdrant
# ============================================================
database_qdrant() {
    header "安装 Qdrant"
    echo "  向量数据库（AI/RAG 必备）"
    _ensure_docker || return 1
    local dir="$HOME/qdrant"
    mkdir -p "$dir/storage"
    local port
    port="$(ask "HTTP端口" "6333")"
    docker run -d --name qdrant -p "${port}:6333" -p 6334:6334         -e TZ=Asia/Shanghai         -v "$dir/storage:/qdrant/storage"         --restart=always qdrant/qdrant
    sleep 3
    success "Qdrant 部署完成: http://localhost:${port}"
    echo "  Dashboard: http://localhost:${port}/dashboard"
}

# ============================================================
#  Milvus
# ============================================================
database_milvus() {
    header "安装 Milvus"
    echo "  向量数据库（大规模）"
    _ensure_docker || return 1
    local dir="$HOME/milvus"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "端口" "19530")"
    step "下载 compose"
    curl -fsSL https://github.com/milvus-io/milvus/releases/latest/download/milvus-standalone-docker-compose.yml -o docker-compose.yml 2>/dev/null
    docker compose up -d 2>/dev/null || warn "启动失败"
    sleep 10
    success "Milvus 部署完成"
    echo "  端口: ${port}, 管理: http://localhost:9091 (attu)"
}

# ============================================================
#  VictoriaMetrics
# ============================================================
database_victoriametrics() {
    header "安装 VictoriaMetrics"
    echo "  时序数据库（比 Prometheus 更省资源）"
    _ensure_docker || return 1
    local dir="$HOME/victoriametrics"
    mkdir -p "$dir"
    local port
    port="$(ask "端口" "8428")"
    docker run -d --name victoriametrics -p "${port}:8428"         -e TZ=Asia/Shanghai         -v "$dir:/victoria-metrics-data"         --restart=always victoriametrics/victoria-metrics
    sleep 3
    success "VictoriaMetrics 部署完成: http://localhost:${port}"
}

# ============================================================
#  Doris
# ============================================================
database_doris() {
    header "安装 Apache Doris"
    echo "  国产 OLAP 引擎（MPP架构）"
    _ensure_docker || return 1
    local dir="$HOME/doris"
    mkdir -p "$dir" && cd "$dir" || return 1
    step "下载 Docker 镜像并启动"
    docker run -d --name doris-fe -p 8030:8030 -p 9030:9030         -e TZ=Asia/Shanghai         -v "$dir/fe:/opt/apache-doris/fe/doris-meta"         --restart=always apache/doris:2.0.3-fe-x86_64
    sleep 10
    docker run -d --name doris-be --link doris-fe         -e TZ=Asia/Shanghai         -v "$dir/be:/opt/apache-doris/be/storage"         --restart=always apache/doris:2.0.3-be-x86_64
    sleep 10
    success "Doris 部署完成"
    echo "  FE Web: http://localhost:8030 (root/空密码)"
    echo "  MySQL: mysql -h 127.0.0.1 -P 9030 -u root"
}

# ============================================================
#  状态查看
# ============================================================
database_status() {
    header "数据库服务状态"
    echo ""
    for db in mysql mariadb postgresql redis-server redis mongod; do
        if has_cmd "${db%-server}" || has_cmd "$db"; then
            local status
            status="$(svc_is_active "$db" 2>/dev/null && echo '运行中' || echo '已停止')"
            echo "  $db: $status"
        fi
    done
    echo ""
    section "监听端口"
    (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -E '3306|5432|6379|27017' | sed 's/^/  /'
}

# ============================================================
#  菜单
# ============================================================
database_menu() {
    while true; do
        header "数据库服务"
        echo "  1) MySQL / MariaDB"
        echo "  2) PostgreSQL (含 pgvector)"
        echo "  3) Redis"
        echo "  4) MongoDB"
        echo "  5) 数据库管理面板 (Docker)"
        echo "  ── 更多数据库 ──"
        echo "  6) TiDB (分布式HTAP)"
        echo "  7) CockroachDB (分布式SQL)"
        echo "  8) Neo4j (图数据库)"
        echo "  9) Qdrant (向量数据库)"
        echo " 10) Milvus (向量数据库)"
        echo " 11) VictoriaMetrics (时序)"
        echo " 12) Doris (OLAP)"
        echo " 13) 查看运行状态"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) database_mysql; pause ;;
            2) database_postgres; pause ;;
            3) database_redis; pause ;;
            4) database_mongo; pause ;;
            5) database_panels; pause ;;
            6) database_tidb; pause ;;
            7) database_cockroach; pause ;;
            8) database_neo4j; pause ;;
            9) database_qdrant; pause ;;
            10) database_milvus; pause ;;
            11) database_victoriametrics; pause ;;
            12) database_doris; pause ;;
            13) database_status; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    database_menu
fi
