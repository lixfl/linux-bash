#!/usr/bin/env bash
# ============================================================
#  remote.sh - 远程桌面 / 运维 / 文件共享
#  Guacamole / RustDesk / MeshCentral / SFTPGo / Samba
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
REMOTE_BASE="${HOME}/remote"

# ============================================================
#  Guacamole
# ============================================================
remote_guacamole() {
    header "安装 Guacamole"
    echo "  浏览器里用 RDP/VNC/SSH 远程桌面"
    _ensure_docker || return 1
    local dir="$REMOTE_BASE/guacamole"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8080")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  guacamole:
    image: oznu/guacamole
    container_name: guacamole
    ports:
      - "${port}:8080"
    volumes:
      - ./config:/config
    restart: always
EOF
    docker compose up -d
    sleep 8
    success "Guacamole 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  默认账号: guacadmin / guacadmin"
}

# ============================================================
#  RustDesk
# ============================================================
remote_rustdesk() {
    header "安装 RustDesk Server"
    echo "  开源 TeamViewer/AnyDesk 替代"
    _ensure_docker || return 1
    local dir="$REMOTE_BASE/rustdesk"
    mkdir -p "$dir" && cd "$dir" || return 1
    step "生成密钥"
    docker run --rm -v "$dir:/root" rustdesk/rustdesk-server:latest hbbs -k _ 2>/dev/null
    local hbbs_port hbbr_port
    hbbs_port="$(ask "HBBS端口" "21115")"
    hbbr_port="$(ask "HBBR端口" "21117")"
    step "启动 RustDesk Server"
    docker run -d --name rustdesk-hbbs -p "${hbbs_port}:21115" -p 21116:21116 -p 21116:21116/udp -p 21118:21118 \
        -v "$dir:/root" --restart=always rustdesk/rustdesk-server:latest hbbs -r "$(hostname -I 2>/dev/null|awk '{print $1}'):21117"
    docker run -d --name rustdesk-hbbr -p "${hbbr_port}:21117" -p 21119:21119 \
        -v "$dir:/root" --restart=always rustdesk/rustdesk-server:latest hbbr
    sleep 3
    success "RustDesk Server 部署完成"
    echo "  ID服务器: $(hostname -I 2>/dev/null|awk '{print $1}')"
    echo "  公钥: $(cat "$dir/id_ed25519.pub" 2>/dev/null || echo '查看配置目录')"
}

# ============================================================
#  MeshCentral
# ============================================================
remote_meshcentral() {
    header "安装 MeshCentral"
    echo "  远程设备管理平台"
    _ensure_docker || return 1
    local dir="$REMOTE_BASE/meshcentral"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8089")"
    docker run -d --name meshcentral -p "${port}:443" -p 80:80 \
        -e TZ=Asia/Shanghai \
        -e HOSTNAME=localhost \
        -v "$dir:/opt/meshcentral/meshcentral-data" \
        --restart=always ghcr.io/ylianst/meshcentral:latest
    sleep 8
    success "MeshCentral 部署完成: https://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
}

# ============================================================
#  SFTPGo
# ============================================================
remote_sftpgo() {
    header "安装 SFTPGo"
    echo "  SFTP/FTP/WebDAV 服务器，带 Web 管理"
    _ensure_docker || return 1
    local dir="$REMOTE_BASE/sftpgo"
    mkdir -p "$dir/data" "$dir/home"
    local sftp_port web_port
    sftp_port="$(ask "SFTP端口" "2222")"
    web_port="$(ask "Web管理端口" "8080")"
    docker run -d --name sftpgo \
        -p "${sftp_port}:22" -p "${web_port}:8080" \
        -e TZ=Asia/Shanghai \
        -e SFTPGO_DATA_PROVIDER__CREATE_DEFAULT_ADMIN=1 \
        -e SFTPGO_DEFAULT_ADMIN_USERNAME=admin \
        -e SFTPGO_DEFAULT_ADMIN_PASSWORD=admin123 \
        -v "$dir/data:/var/lib/sftpgo" \
        -v "$dir/home:/srv/sftpgo" \
        --restart=always drakkan/sftpgo:latest
    sleep 5
    success "SFTPGo 部署完成"
    echo "  Web管理: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${web_port} (admin/admin123)"
    echo "  SFTP: sftp://$(hostname -I 2>/dev/null|awk '{print $1}'):${sftp_port}"
}

# ============================================================
#  Samba
# ============================================================
remote_samba() {
    require_root || return 1
    header "安装 Samba"
    echo "  SMB 文件共享（Windows 网络邻居）"
    if ! has_cmd smbd; then
        step "安装 Samba"
        pkg_install samba samba-common-bin 2>/dev/null || pkg_install samba
    fi
    local share_dir share_name user
    share_dir="$(ask "共享目录路径" "/srv/samba/share")"
    share_name="$(ask "共享名" "share")"
    user="$(ask "访问用户名" "samba")"
    mkdir -p "$share_dir"
    chmod 777 "$share_dir"
    step "创建 Samba 用户"
    id "$user" &>/dev/null || useradd -m -s /usr/sbin/nologin "$user"
    smbpasswd -a "$user"
    step "配置共享"
    cat >> /etc/samba/smb.conf <<EOF

[$share_name]
   path = $share_dir
   browseable = yes
   read only = no
   valid users = $user
EOF
    systemctl restart smbd 2>/dev/null || service smbd restart
    success "Samba 配置完成"
    echo "  共享: \\\\$(hostname -I 2>/dev/null|awk '{print $1}')\\$share_name"
    echo "  用户: $user"
}

# ============================================================
#  菜单
# ============================================================
remote_menu() {
    while true; do
        header "远程桌面 / 运维 / 文件共享"
        echo "  1) Guacamole   (浏览器远程桌面 RDP/VNC/SSH)"
        echo "  2) RustDesk    (远程控制服务端)"
        echo "  3) MeshCentral (远程设备管理)"
        echo "  4) SFTPGo      (SFTP/FTP/WebDAV)"
        echo "  5) Samba       (SMB文件共享)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) remote_guacamole; pause ;;
            2) remote_rustdesk; pause ;;
            3) remote_meshcentral; pause ;;
            4) remote_sftpgo; pause ;;
            5) remote_samba; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    remote_menu
fi
