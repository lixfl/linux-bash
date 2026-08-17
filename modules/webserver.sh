#!/usr/bin/env bash
# ============================================================
#  webserver.sh - Web 服务环境
#  Nginx / Caddy / LNMP / PHP 多版本
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

WEB_ROOT="/var/www"

# ============================================================
#  Nginx
# ============================================================
webserver_nginx() {
    require_root || return 1
    header "安装 Nginx"
    if has_cmd nginx; then
        warn "Nginx 已安装: $(nginx -v 2>&1)"
        confirm "重新安装?" "n" || return 0
        pkg_remove nginx 2>/dev/null
    fi
    pkg_install nginx
    svc_enable nginx 2>/dev/null
    svc_start nginx 2>/dev/null
    mkdir -p "$WEB_ROOT"
    chown -R www-data:www-data "$WEB_ROOT" 2>/dev/null || chown -R nginx:nginx "$WEB_ROOT" 2>/dev/null
    success "Nginx 安装完成: $(nginx -v 2>&1)"
    echo "  根目录: $WEB_ROOT"
    echo "  配置: /etc/nginx/"
    echo "  测试: nginx -t && systemctl reload nginx"
}

# ============================================================
#  Caddy
# ============================================================
webserver_caddy() {
    require_root || return 1
    header "安装 Caddy"
    echo "  自动 HTTPS，配置比 Nginx 简单"
    if has_cmd caddy; then
        warn "Caddy 已安装: $(caddy version)"
        confirm "重新安装?" "n" || return 0
    fi
    if [ "$PKG_MANAGER" = "apt" ]; then
        step "添加 Caddy 官方源"
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null
        apt-get update -qq
        pkg_install caddy
    else
        pkg_install caddy 2>/dev/null || {
            step "下载 Caddy 二进制"
            local arch_map
            case "$ARCH" in
                x86_64) arch_map="amd64" ;;
                aarch64) arch_map="arm64" ;;
                *) error "不支持的架构"; return 1 ;;
            esac
            curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=${arch_map}" -o /usr/local/bin/caddy
            chmod +x /usr/local/bin/caddy
        }
    fi
    svc_enable caddy 2>/dev/null
    svc_start caddy 2>/dev/null
    success "Caddy 安装完成: $(caddy version 2>/dev/null)"
    echo "  配置: /etc/caddy/Caddyfile"
    echo "  示例: echo 'yourdomain.com { root * /var/www; file_server }' > /etc/caddy/Caddyfile && systemctl reload caddy"
}

# ============================================================
#  PHP 多版本
# ============================================================
webserver_php() {
    require_root || return 1
    header "安装 PHP"
    echo "  支持多版本共存: 7.4 / 8.1 / 8.2 / 8.3"
    if [ "$PKG_MANAGER" = "apt" ]; then
        step "添加 ondrej/php PPA"
        pkg_install software-properties-common
        add-apt-repository -y ppa:ondrej/php 2>/dev/null
        apt-get update -qq
    fi
    echo ""
    echo "  1) PHP 7.4"
    echo "  2) PHP 8.1"
    echo "  3) PHP 8.2"
    echo "  4) PHP 8.3 (推荐)"
    local ver
    ver="$(ask "选择版本" "4")"
    case "$ver" in
        1) php_ver="7.4" ;;
        2) php_ver="8.1" ;;
        3) php_ver="8.2" ;;
        4) php_ver="8.3" ;;
        *) warn "无效选项"; return 1 ;;
    esac
    step "安装 PHP $php_ver + 常用扩展"
    pkg_install "php${php_ver}-fpm" "php${php_ver}-mysql" "php${php_ver}-curl" "php${php_ver}-gd" "php${php_ver}-mbstring" "php${php_ver}-xml" "php${php_ver}-zip" "php${php_ver}-redis" "php${php_ver}-intl" 2>/dev/null
    svc_enable "php${php_ver}-fpm" 2>/dev/null
    svc_start "php${php_ver}-fpm" 2>/dev/null
    success "PHP $php_ver 安装完成: $(php${php_ver} -v 2>/dev/null | head -1)"
    echo "  FPM 服务: php${php_ver}-fpm"
    echo "  配置: /etc/php/${php_ver}/fpm/"
}

# ============================================================
#  LNMP 一键包
# ============================================================
webserver_lnmp() {
    require_root || return 1
    header "LNMP 一键安装 (Nginx + MySQL + PHP)"
    echo "  将依次安装 Nginx、MySQL、PHP-FPM"
    echo ""
    if ! confirm "继续?" "y"; then return 0; fi
    webserver_nginx
    echo ""
    # 调用 database 模块的 mysql 安装
    local mod_dir
    mod_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$mod_dir/database.sh"
    database_mysql
    echo ""
    webserver_php
    echo ""
    success "LNMP 环境安装完成"
    echo "  Nginx: $(nginx -v 2>&1)"
    echo "  MySQL: $(mysql --version 2>/dev/null)"
    echo "  PHP: $(php -v 2>/dev/null | head -1)"
    echo "  网站根目录: $WEB_ROOT"
}

# ============================================================
#  虚拟主机生成
# ============================================================
webserver_vhost() {
    require_root || return 1
    header "生成 Nginx 虚拟主机配置"
    local domain root php_ver
    domain="$(ask "域名 (如 example.com)" "")"
    [ -z "$domain" ] && { warn "域名不能为空"; return 1; }
    root="$(ask "网站根目录" "$WEB_ROOT/$domain")"
    php_ver="$(ask "PHP版本(留空纯静态)" "")"
    mkdir -p "$root"
    local conf="/etc/nginx/conf.d/${domain}.conf"
    if [ -n "$php_ver" ]; then
        cat > "$conf" <<EOF
server {
    listen 80;
    server_name $domain;
    root $root;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php${php_ver}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
    else
        cat > "$conf" <<EOF
server {
    listen 80;
    server_name $domain;
    root $root;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    fi
    nginx -t 2>/dev/null && svc_reload nginx 2>/dev/null
    success "虚拟主机配置已生成: $conf"
    echo "  域名: $domain"
    echo "  根目录: $root"
    echo "  重载: nginx -t && systemctl reload nginx"
}


# ============================================================
#  WordPress
# ============================================================
webserver_wordpress() {
    header "安装 WordPress"
    echo "  最流行的博客/CMS，Docker 一键部署"
    _ensure_docker || return 1
    local dir="$WEB_ROOT/wordpress"
    mkdir -p "$dir" "$WEB_ROOT/wp-db" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8080")"
    step "生成 Docker Compose"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  wordpress:
    image: wordpress:latest
    container_name: wordpress
    ports:
      - "${port}:80"
    environment:
      - WORDPRESS_DB_HOST=db
      - WORDPRESS_DB_USER=wp
      - WORDPRESS_DB_PASSWORD=wp123456
      - WORDPRESS_DB_NAME=wp
    volumes:
      - ./html:/var/www/html
    depends_on:
      - db
    restart: always
  db:
    image: mysql:8
    container_name: wp-db
    environment:
      - MYSQL_DATABASE=wp
      - MYSQL_USER=wp
      - MYSQL_PASSWORD=wp123456
      - MYSQL_ROOT_PASSWORD=root123456
    volumes:
      - $WEB_ROOT/wp-db:/var/lib/mysql
    restart: always
EOF
    docker compose up -d
    sleep 5
    success "WordPress 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  数据库: wp / wp123456"
}

# ============================================================
#  Ghost
# ============================================================
webserver_ghost() {
    header "安装 Ghost"
    echo "  现代化博客平台，自带会员/Newsletter"
    _ensure_docker || return 1
    local dir="$WEB_ROOT/ghost"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port url
    port="$(ask "Web端口" "2368")"
    url="$(ask "站点URL (http://域名:端口)" "http://localhost:${port}")"
    step "启动 Ghost"
    docker run -d --name ghost -p "${port}:2368"         -e url="$url" -e TZ=Asia/Shanghai         -v "$dir:/var/lib/ghost/content"         --restart=always ghost:latest
    sleep 5
    success "Ghost 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  管理后台: /ghost"
}

# ============================================================
#  Discourse
# ============================================================
webserver_discourse() {
    header "安装 Discourse"
    echo "  开源论坛社区（需 Docker，内存建议2G+）"
    _ensure_docker || return 1
    local dir="/var/discourse"
    if [ -d "$dir" ]; then
        warn "Discourse 已安装: $dir"
        cd "$dir" && ./launcher restart app
        return 0
    fi
    step "克隆 Discourse Docker"
    git clone https://github.com/discourse/discourse_docker.git "$dir"
    cd "$dir" || return 1
    info "需要手动配置: cd $dir && ./discourse-setup"
    info "按提示输入域名、邮箱、SMTP 等信息后自动安装"
    if confirm "现在运行配置向导?" "y"; then
        ./discourse-setup
    fi
}

# ============================================================
#  Typecho
# ============================================================
webserver_typecho() {
    header "安装 Typecho"
    echo "  轻量博客程序"
    _ensure_docker || return 1
    local dir="$WEB_ROOT/typecho"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8080")"
    step "启动 Typecho"
    docker run -d --name typecho -p "${port}:80"         -e TZ=Asia/Shanghai         -v "$dir:/var/www/html"         --restart=always 80x86/typecho:latest
    sleep 3
    success "Typecho 部署完成"
    echo "  访问: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  Hugo
# ============================================================
webserver_hugo() {
    header "安装 Hugo"
    echo "  静态站点生成器"
    if has_cmd hugo; then
        success "Hugo 已安装: $(hugo version)"
        return 0
    fi
    local arch_map
    case "$ARCH" in
        x86_64) arch_map="amd64" ;;
        aarch64) arch_map="arm64" ;;
        *) error "不支持的架构"; return 1 ;;
    esac
    step "下载 Hugo"
    local ver
    ver="$(curl -s https://api.github.com/repos/gohugoio/hugo/releases/latest | grep tag_name | cut -d'"' -f4 | sed 's/v//')"
    [ -z "$ver" ] && ver="0.128.0"
    curl -fsSL "https://github.com/gohugoio/hugo/releases/download/v${ver}/hugo_extended_${ver}_linux-${arch_map}.deb" -o /tmp/hugo.deb
    dpkg -i /tmp/hugo.deb 2>/dev/null || {
        curl -fsSL "https://github.com/gohugoio/hugo/releases/download/v${ver}/hugo_extended_${ver}_linux-${arch_map}.tar.gz" -o /tmp/hugo.tar.gz
        tar -xzf /tmp/hugo.tar.gz -C /usr/local/bin hugo
    }
    rm -f /tmp/hugo.*
    success "Hugo 安装完成: $(hugo version)"
    echo "  新建站点: hugo new site mysite"
    echo "  本地预览: hugo server -D"
}

# ============================================================
#  菜单
# ============================================================
webserver_menu() {
    while true; do
        header "Web 服务环境"
        echo "  1) 安装 Nginx"
        echo "  2) 安装 Caddy (自动HTTPS)"
        echo "  3) 安装 PHP (多版本)"
        echo "  4) LNMP 一键安装"
        echo "  5) 生成 Nginx 虚拟主机"
        echo "  6) WordPress"
        echo "  7) Ghost"
        echo "  8) Discourse 论坛"
        echo "  9) Typecho"
        echo " 10) Hugo 静态站点"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) webserver_nginx; pause ;;
            2) webserver_caddy; pause ;;
            3) webserver_php; pause ;;
            4) webserver_lnmp; pause ;;
            5) webserver_vhost; pause ;;
            6) webserver_wordpress; pause ;;
            7) webserver_ghost; pause ;;
            8) webserver_discourse; pause ;;
            9) webserver_typecho; pause ;;
            10) webserver_hugo; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    webserver_menu
fi
