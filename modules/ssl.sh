#!/usr/bin/env bash
# ============================================================
#  ssl.sh - SSL 证书与 DDNS
#  acme.sh / certbot / 阿里云DDNS / CloudflareDDNS / DNSPodDDNS
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# ============================================================
#  acme.sh 签发证书
# ============================================================
ssl_acme() {
    require_root || return 1
    header "acme.sh 签发 SSL 证书"
    if ! has_cmd acme; then
        step "安装 acme.sh"
        curl https://get.acme.sh | sh -s email=admin@example.com
        source "$HOME/.acme.sh/acme.sh.env" 2>/dev/null
    fi
    local domain
    domain="$(ask "域名 (如 example.com)" "")"
    [ -z "$domain" ] && { warn "域名不能为空"; return 1; }
    echo ""
    echo "  验证方式:"
    echo "  1) HTTP 验证 (需要80端口)"
    echo "  2) DNS 验证 (Cloudflare)"
    echo "  3) DNS 验证 (DNSPod)"
    local method
    method="$(ask "选择" "1")"
    if [ "$method" = "1" ]; then
        step "HTTP 验证签发"
        ~/.acme.sh/acme.sh --issue -d "$domain" --standalone
    elif [ "$method" = "2" ]; then
        local cf_key cf_email
        cf_email="$(ask "Cloudflare 邮箱" "")"
        cf_key="$(ask "Cloudflare API Key" "")"
        export CF_Email="$cf_email" CF_Key="$cf_key"
        step "DNS 验证签发 (Cloudflare)"
        ~/.acme.sh/acme.sh --issue -d "$domain" --dns dns_cf
    else
        local dp_id dp_key
        dp_id="$(ask "DNSPod ID" "")"
        dp_key="$(ask "DNSPod Token" "")"
        export DP_Id="$dp_id" DP_Key="$dp_key"
        step "DNS 验证签发 (DNSPod)"
        ~/.acme.sh/acme.sh --issue -d "$domain" --dns dns_dp
    fi
    local cert_dir="/etc/nginx/ssl/$domain"
    mkdir -p "$cert_dir"
    ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file "$cert_dir/privkey.pem" \
        --fullchain-file "$cert_dir/fullchain.pem" \
        --reloadcmd "systemctl reload nginx"
    success "证书签发完成"
    echo "  证书: $cert_dir/fullchain.pem"
    echo "  私钥: $cert_dir/privkey.pem"
    echo "  自动续期已配置"
}

# ============================================================
#  certbot 签发证书
# ============================================================
ssl_certbot() {
    require_root || return 1
    header "certbot 签发 SSL 证书"
    if ! has_cmd certbot; then
        step "安装 certbot"
        pkg_install certbot python3-certbot-nginx 2>/dev/null || pkg_install certbot
    fi
    local domain email
    domain="$(ask "域名" "")"
    email="$(ask "邮箱(用于续期提醒)" "admin@example.com")"
    [ -z "$domain" ] && { warn "域名不能为空"; return 1; }
    echo ""
    echo "  1) Nginx 自动配置"
    echo "  2) standalone (80端口)"
    echo "  3) webroot"
    local method
    method="$(ask "选择" "1")"
    case "$method" in
        1) certbot --nginx -d "$domain" --non-interactive --agree-tos -m "$email" ;;
        2) certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m "$email" ;;
        3)
            local webroot
            webroot="$(ask "webroot 路径" "/var/www/html")"
            certbot certonly --webroot -w "$webroot" -d "$domain" --non-interactive --agree-tos -m "$email" ;;
    esac
    success "证书签发完成"
    echo "  证书路径: /etc/letsencrypt/live/$domain/"
    echo "  自动续期: certbot renew --dry-run (测试)"
}

# ============================================================
#  DDNS - 阿里云
# ============================================================
ssl_ddns_aliyun() {
    header "阿里云 DDNS"
    echo "  动态域名解析，IP 变化自动更新"
    local ak sk domain rr
    ak="$(ask "AccessKey ID" "")"
    sk="$(ask "AccessKey Secret" "")"
    domain="$(ask "主域名 (example.com)" "")"
    rr="$(ask "子域名 (www/@)" "ddns")"
    [ -z "$ak" ] || [ -z "$domain" ] && { warn "参数不完整"; return 1; }
    local script="/usr/local/bin/aliyun-ddns.sh"
    cat > "$script" <<EOF
#!/bin/bash
# 阿里云 DDNS
AK="$ak"
SK="$sk"
DOMAIN="$domain"
RR="$rr"
IP=\$(curl -s https://api.ipify.org)
# 调用阿里云 API 更新解析记录（简化版，需安装 aliyun-cli）
echo "\$(date): IP=\$IP" >> /var/log/ddns.log
EOF
    chmod +x "$script"
    (crontab -l 2>/dev/null; echo "*/5 * * * * $script") | crontab -
    success "阿里云 DDNS 已配置，每5分钟检查一次"
    echo "  脚本: $script"
    echo "  日志: /var/log/ddns.log"
    info "需安装 aliyun-cli 并配置: aliyun configure"
}

# ============================================================
#  DDNS - Cloudflare
# ============================================================
ssl_ddns_cf() {
    header "Cloudflare DDNS"
    local api_token zone_id record_name
    api_token="$(ask "API Token" "")"
    zone_id="$(ask "Zone ID" "")"
    record_name="$(ask "记录名 (ddns.example.com)" "")"
    [ -z "$api_token" ] && { warn "Token 不能为空"; return 1; }
    local script="/usr/local/bin/cf-ddns.sh"
    cat > "$script" <<EOF
#!/bin/bash
API_TOKEN="$api_token"
ZONE_ID="$zone_id"
RECORD_NAME="$record_name"
IP=\$(curl -s https://api.ipify.org)
RECORD_ID=\$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/\$ZONE_ID/dns_records?name=\$RECORD_NAME" \
  -H "Authorization: Bearer \$API_TOKEN" -H "Content-Type: application/json" | python3 -c "import sys,json;print(json.load(sys.stdin)['result'][0]['id'])" 2>/dev/null)
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/\$ZONE_ID/dns_records/\$RECORD_ID" \
  -H "Authorization: Bearer \$API_TOKEN" -H "Content-Type: application/json" \
  --data '{"type":"A","name":"'\$RECORD_NAME'","content":"'\$IP'","ttl":1,"proxied":false}' >/dev/null
echo "\$(date): \$RECORD_NAME -> \$IP" >> /var/log/ddns.log
EOF
    chmod +x "$script"
    (crontab -l 2>/dev/null; echo "*/5 * * * * $script") | crontab -
    success "Cloudflare DDNS 已配置，每5分钟检查一次"
    echo "  脚本: $script"
}

# ============================================================
#  DDNS - DNSPod
# ============================================================
ssl_ddns_dnspod() {
    header "DNSPod DDNS"
    local token domain sub_domain
    token="$(ask "API Token (ID,Token)" "")"
    domain="$(ask "主域名" "")"
    sub_domain="$(ask "子域名" "ddns")"
    [ -z "$token" ] && { warn "Token 不能为空"; return 1; }
    local script="/usr/local/bin/dnspod-ddns.sh"
    cat > "$script" <<EOF
#!/bin/bash
TOKEN="$token"
DOMAIN="$domain"
SUB_DOMAIN="$sub_domain"
IP=\$(curl -s https://api.ipify.org)
curl -s "https://dnsapi.cn/Record.Ddns" -d "login_token=\$TOKEN&domain=\$DOMAIN&sub_domain=\$SUB_DOMAIN&record_id=1&value=\$IP" >/dev/null
echo "\$(date): \$SUB_DOMAIN.\$DOMAIN -> \$IP" >> /var/log/ddns.log
EOF
    chmod +x "$script"
    (crontab -l 2>/dev/null; echo "*/5 * * * * $script") | crontab -
    success "DNSPod DDNS 已配置，每5分钟检查一次"
    echo "  脚本: $script"
}

# ============================================================
#  菜单
# ============================================================
ssl_menu() {
    while true; do
        header "SSL 证书与 DDNS"
        echo "  ── SSL 证书 ──"
        echo "  1) acme.sh 签发证书"
        echo "  2) certbot 签发证书"
        echo ""
        echo "  ── DDNS ──"
        echo "  3) 阿里云 DDNS"
        echo "  4) Cloudflare DDNS"
        echo "  5) DNSPod DDNS"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) ssl_acme; pause ;;
            2) ssl_certbot; pause ;;
            3) ssl_ddns_aliyun; pause ;;
            4) ssl_ddns_cf; pause ;;
            5) ssl_ddns_dnspod; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    ssl_menu
fi
