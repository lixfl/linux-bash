#!/usr/bin/env bash
# ============================================================
#  auth.sh - 身份认证 / SSO / 密钥管理
#  Keycloak / Authelia / Authentik / Casdoor / Vault
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
AUTH_BASE="${HOME}/auth"

# ============================================================
#  Keycloak
# ============================================================
auth_keycloak() {
    header "安装 Keycloak"
    echo "  企业级身份认证，SSO/OIDC/SAML/LDAP"
    _ensure_docker || return 1
    local dir="$AUTH_BASE/keycloak"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8080")"
    docker run -d --name keycloak -p "${port}:8080" \
        -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin123 \
        -e TZ=Asia/Shanghai \
        -v "$dir:/opt/keycloak/data" \
        --restart=always quay.io/keycloak/keycloak:latest start-dev
    sleep 8
    success "Keycloak 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  管理后台: /admin (admin/admin123)"
}

# ============================================================
#  Authelia
# ============================================================
auth_authelia() {
    header "安装 Authelia"
    echo "  轻量 SSO + 2FA，配合反代做统一登录"
    _ensure_docker || return 1
    local dir="$AUTH_BASE/authelia"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "9091")"
    step "生成配置"
    cat > configuration.yml <<'EOF'
theme: auto
default_redirection_url: https://www.google.com
totp:
  issuer: authelia.com
authentication_backend:
  file:
    path: /config/users_database.yml
access_control:
  default_policy: bypass
session:
  secret: insecure_session_secret
  cookie: authelia_session
  domain: example.com
storage:
  encryption_key: insecure_encryption_key
  local:
    path: /config/db.sqlite3
notifier:
  filesystem:
    filename: /config/notification.txt
EOF
    cat > users_database.yml <<'EOF'
users:
  admin:
    disabled: false
    displayname: Admin
    password: "$6$rounds=50000$johndoe$5Gq7QpY5..."
    email: admin@example.com
    groups:
      - admins
      - dev
EOF
    docker run -d --name authelia -p "${port}:9091" \
        -e TZ=Asia/Shanghai \
        -v "$dir:/config" \
        --restart=always authelia/authelia
    sleep 5
    success "Authelia 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    warn "需手动配置用户密码和域名，编辑 configuration.yml"
}

# ============================================================
#  Authentik
# ============================================================
auth_authentik() {
    header "安装 Authentik"
    echo "  现代化 SSO，OAuth2/SAML/LDAP/SCIM"
    _ensure_docker || return 1
    local dir="$AUTH_BASE/authentik"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "9000")"
    step "下载 compose"
    curl -fsSL https://raw.githubusercontent.com/goauthentik/authentik/main/docker-compose.yml -o docker-compose.yml 2>/dev/null
    curl -fsSL https://raw.githubusercontent.com/goauthentik/authentik/main/.env -o .env 2>/dev/null
    [ -f .env ] && {
        sed -i "s/^AUTHENTIK_PORT_HTTP=.*/AUTHENTIK_PORT_HTTP=${port}/" .env
        echo "AUTHENTIK_SECRET_KEY=$(openssl rand -hex 32)" >> .env
    }
    docker compose up -d 2>/dev/null || warn "compose 启动失败，请检查配置"
    sleep 15
    success "Authentik 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}/if/flow/initial-setup/"
    echo "  首次访问创建管理员账号"
}

# ============================================================
#  Casdoor
# ============================================================
auth_casdoor() {
    header "安装 Casdoor"
    echo "  轻量统一认证，UI 友好，支持多语言"
    _ensure_docker || return 1
    local dir="$AUTH_BASE/casdoor"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8000")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  casdoor:
    image: casbin/casdoor:latest
    container_name: casdoor
    ports:
      - "${port}:8000"
    environment:
      - driverName=mysql
      - dataSourceName=root:123456@tcp(db:3306)/
    depends_on:
      - db
    restart: always
  db:
    image: mysql:8
    environment:
      - MYSQL_ROOT_PASSWORD=123456
      - MYSQL_DATABASE=casdoor
    volumes:
      - ./db:/var/lib/mysql
    restart: always
EOF
    docker compose up -d
    sleep 10
    success "Casdoor 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  默认账号: admin / 123456"
}

# ============================================================
#  Vault
# ============================================================
auth_vault() {
    header "安装 Vault"
    echo "  HashiCorp 密钥/证书/密码管理"
    _ensure_docker || return 1
    local dir="$AUTH_BASE/vault"
    mkdir -p "$dir/file" "$dir/logs" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8200")"
    cat > vault.json <<'EOF'
{
  "storage": { "file": { "path": "/vault/file" } },
  "listener": { "tcp": { "address": "0.0.0.0:8200", "tls_disable": 1 } },
  "ui": true
}
EOF
    docker run -d --name vault -p "${port}:8200" --cap-add=IPC_LOCK \
        -e TZ=Asia/Shanghai \
        -v "$dir/vault.json:/vault/config/vault.json" \
        -v "$dir/file:/vault/file" -v "$dir/logs:/vault/logs" \
        --restart=always vault:latest server
    sleep 5
    success "Vault 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  首次需初始化和解封(Unseal)"
    echo "  CLI: export VAULT_ADDR=http://localhost:${port}"
}

# ============================================================
#  菜单
# ============================================================
auth_menu() {
    while true; do
        header "身份认证 / SSO / 密钥管理"
        echo "  1) Keycloak   (企业级SSO/OIDC/SAML)"
        echo "  2) Authelia   (轻量SSO+2FA)"
        echo "  3) Authentik  (现代化SSO/SCIM)"
        echo "  4) Casdoor    (轻量统一认证)"
        echo "  5) Vault      (密钥/证书管理)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) auth_keycloak; pause ;;
            2) auth_authelia; pause ;;
            3) auth_authentik; pause ;;
            4) auth_casdoor; pause ;;
            5) auth_vault; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    auth_menu
fi
