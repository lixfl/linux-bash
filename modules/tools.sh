#!/usr/bin/env bash
# ============================================================
#  tools.sh - 实用小工具集合
#  SearXNG / Whoogle / Excalidraw / Penpot / Draw.io / Miniflux / YOURLS / Lychee / Grocy / Homebox / Wger / Kimai / Invoice Ninja / Chatwoot / Giscus / Cachet / PostHog / GrowthBook / Roundcube / Mailman / rclone / FFmpeg / Handbrake / Tesseract / chrony / CUPS
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
TOOLS_BASE="${HOME}/tools"

# 通用 Docker 运行
_run_tool() {
    local name=$1 port=$2 image=$3 extra=${4:-}
    mkdir -p "$TOOLS_BASE/$name"
    docker run -d --name "$name" -p "${port}:${port%%:*}" \
        -e TZ=Asia/Shanghai $extra \
        -v "$TOOLS_BASE/$name:/data" \
        --restart=always "$image" 2>/dev/null
    sleep 3
    success "$name 部署完成: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${port%%:*}"
}

# ============================================================
#  搜索 / 白板 / 设计
# ============================================================
tools_searxng() { header "安装 SearXNG (元搜索)"; _ensure_docker || return 1; local p; p="$(ask "端口" "8888")"; _run_tool searxng "$p:8080" searxng/searxng; }
tools_whoogle() { header "安装 Whoogle (Google代理)"; _ensure_docker || return 1; local p; p="$(ask "端口" "5000")"; _run_tool whoogle "$p:5000" benbusby/whoogle-search; }
tools_excalidraw() { header "安装 Excalidraw (手绘白板)"; _ensure_docker || return 1; local p; p="$(ask "端口" "8080")"; _run_tool excalidraw "$p:80" excalidraw/excalidraw; }
tools_penpot() { header "安装 Penpot (Figma替代)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/penpot"; mkdir -p "$dir" && cd "$dir"; local p; p="$(ask "端口" "9001")"; git clone --depth 1 https://github.com/penpot/penpot.git . 2>/dev/null; cd docker-images 2>/dev/null; [ -f docker-compose.yaml ] && sed -i "s/9001:9001/${p}:9001/" docker-compose.yaml 2>/dev/null; docker compose up -d 2>/dev/null || warn "启动失败"; success "Penpot: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p}"; }
tools_drawio() { header "安装 Draw.io (流程图)"; _ensure_docker || return 1; local p; p="$(ask "端口" "8080")"; _run_tool drawio "$p:8080" jgraph/drawio; }

# ============================================================
#  RSS / 短链 / 图床
# ============================================================
tools_miniflux() { header "安装 Miniflux (极简RSS)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/miniflux"; mkdir -p "$dir"; local p; p="$(ask "端口" "8080")"; docker run -d --name miniflux -p "${p}:8080" -e DATABASE_URL="postgres://miniflux:miniflux123@db:5432/miniflux?sslmode=disable" -e RUN_MIGRATIONS=1 -e CREATE_ADMIN=1 -e ADMIN_USERNAME=admin -e ADMIN_PASSWORD=admin123 --link miniflux-db:db --restart=always miniflux/miniflux:latest 2>/dev/null; docker run -d --name miniflux-db -e POSTGRES_USER=miniflux -e POSTGRES_PASSWORD=miniflux123 -e POSTGRES_DB=miniflux -v "$dir:/var/lib/postgresql/data" --restart=always postgres:15 2>/dev/null; success "Miniflux: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p} (admin/admin123)"; }
tools_yourls() { header "安装 YOURLS (短链接)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/yourls"; mkdir -p "$dir"; local p; p="$(ask "端口" "8080")"; docker run -d --name yourls -p "${p}:80" -e YOURLS_DB_PASS=yourls123 -e YOURLS_SITE="http://localhost:${p}" -e YOURLS_USER=admin -e YOURLS_PASS=admin123 --link yourls-db:mysql -v "$dir:/var/www/html" --restart=always yourls 2>/dev/null; docker run -d --name yourls-db -e MYSQL_ROOT_PASSWORD=yourls123 -e MYSQL_DATABASE=yourls --restart=always mysql:5.7 2>/dev/null; success "YOURLS: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p}/admin (admin/admin123)"; }
tools_lychee() { header "安装 Lychee (图床)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/lychee"; mkdir -p "$dir/conf" "$dir/uploads" "$dir/sym"; local p; p="$(ask "端口" "8080")"; docker run -d --name lychee -p "${p}:80" -e TZ=Asia/Shanghai -v "$dir/conf:/conf" -v "$dir/uploads:/uploads" -v "$dir/sym:/sym" --restart=always lscr.io/linuxserver/lychee:latest; sleep 5; success "Lychee: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p}"; }

# ============================================================
#  生活 / 管理
# ============================================================
tools_grocy() { header "安装 Grocy (家庭管理)"; _ensure_docker || return 1; local p; p="$(ask "端口" "9283")"; _run_tool grocy "$p:8080" lscr.io/linuxserver/grocy; }
tools_homebox() { header "安装 Homebox (库存管理)"; _ensure_docker || return 1; local p; p="$(ask "端口" "7745")"; _run_tool homebox "$p:7745" ghcr.io/sysadminsmedia/homebox:latest; }
tools_wger() { header "安装 Wger (健身管理)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/wger"; mkdir -p "$dir" && cd "$dir"; local p; p="$(ask "端口" "8080")"; git clone --depth 1 https://github.com/wger-project/docker.git . 2>/dev/null; [ -f docker-compose.yml ] && sed -i "s/8000:8000/${p}:8000/" docker-compose.yml 2>/dev/null; docker compose up -d 2>/dev/null || warn "启动失败"; success "Wger: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p}"; }
tools_kimai() { header "安装 Kimai (时间追踪)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/kimai"; mkdir -p "$dir"; local p; p="$(ask "端口" "8080")"; docker run -d --name kimai -p "${p}:8001" -e TZ=Asia/Shanghai -e ADMINMAIL=admin@example.com -e ADMINPASS=admin123 -v "$dir:/opt/kimai/var" --restart=always kimai/kimai2:apache; sleep 8; success "Kimai: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p} (admin@example.com/admin123)"; }
tools_invoiceninja() { header "安装 Invoice Ninja (发票)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/invoiceninja"; mkdir -p "$dir"; local p; p="$(ask "端口" "8080")"; docker run -d --name invoiceninja -p "${p}:80" -e TZ=Asia/Shanghai -e APP_URL="http://localhost:${p}" -v "$dir:/var/www/app/storage" --restart=always invoiceninja/invoiceninja5; sleep 10; success "Invoice Ninja: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p}"; }

# ============================================================
#  客服 / 评论 / 状态页 / 分析
# ============================================================
tools_chatwoot() { header "安装 Chatwoot (客服)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/chatwoot"; mkdir -p "$dir" && cd "$dir"; local p; p="$(ask "端口" "3000")"; git clone --depth 1 https://github.com/chatwoot/chatwoot.git . 2>/dev/null; [ -f .env.example ] && cp .env.example .env 2>/dev/null; docker compose up -d 2>/dev/null || warn "启动失败"; success "Chatwoot: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p}"; }
tools_giscus() { header "安装 Giscus (评论系统)"; info "Giscus 基于 GitHub Discussions，无需自托管"; echo "  配置: https://giscus.app"; echo "  选择仓库后嵌入 script 标签即可"; }
tools_cachet() { header "安装 Cachet (状态页)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/cachet"; mkdir -p "$dir"; local p; p="$(ask "端口" "8080")"; docker run -d --name cachet -p "${p}:8000" -e TZ=Asia/Shanghai -e DB_DRIVER=sqlite -v "$dir:/var/www/html" --restart=always cachethq/docker:latest; sleep 8; success "Cachet: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p}"; }
tools_posthog() { header "安装 PostHog (产品分析)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/posthog"; mkdir -p "$dir" && cd "$dir"; local p; p="$(ask "端口" "8000")"; git clone --depth 1 https://github.com/PostHog/posthog.git . 2>/dev/null; docker compose -f docker-compose.dev.yml up -d 2>/dev/null || warn "启动失败，PostHog 依赖较多"; success "PostHog: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p}"; }
tools_growthbook() { header "安装 GrowthBook (功能开关+A/B)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/growthbook"; mkdir -p "$dir" && cd "$dir"; local p; p="$(ask "端口" "3000")"; git clone --depth 1 https://github.com/growthbook/growthbook.git . 2>/dev/null; cd packages/dev 2>/dev/null; docker compose up -d 2>/dev/null || warn "启动失败"; success "GrowthBook: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p}"; }

# ============================================================
#  邮件 / 工具
# ============================================================
tools_roundcube() { header "安装 Roundcube (Web邮件)"; _ensure_docker || return 1; local p; p="$(ask "端口" "8080")"; _run_tool roundcube "$p:80" roundcube/roundcubemail; }
tools_mailman() { header "安装 Mailman (邮件列表)"; _ensure_docker || return 1; local dir="$TOOLS_BASE/mailman"; mkdir -p "$dir"; local p; p="$(ask "端口" "8080")"; docker run -d --name mailman -p "${p}:8000" -e TZ=Asia/Shanghai -v "$dir:/opt/mailman" --restart=always maxking/mailman-web; success "Mailman: http://$(hostname -I 2>/dev/null|awk '{print $1}'):${p}"; warn "Mailman 完整部署需配置 MTA，建议参考官方文档"; }
tools_rclone() { header "安装 rclone (网盘挂载)"; if has_cmd rclone; then success "rclone 已安装: $(rclone version | head -1)"; return 0; fi; curl -fsSL https://rclone.org/install.sh | bash; success "rclone 安装完成"; echo "  配置: rclone config"; echo "  挂载: rclone mount remote:path /mnt/remote --daemon"; echo "  支持: Google Drive/OneDrive/Dropbox/S3/阿里云盘等40+"; }
tools_ffmpeg() { header "安装 FFmpeg"; if has_cmd ffmpeg; then success "FFmpeg 已安装: $(ffmpeg -version | head -1)"; return 0; fi; pkg_install ffmpeg; success "FFmpeg 安装完成: $(ffmpeg -version | head -1)"; echo "  转码: ffmpeg -i input.mp4 output.mp3"; echo "  截图: ffmpeg -i input.mp4 -ss 00:01:00 -vframes 1 shot.png"; }
tools_handbrake() { header "安装 HandBrake CLI"; if has_cmd HandBrakeCLI; then success "已安装"; return 0; fi; pkg_install handbrake-cli 2>/dev/null || warn "请手动安装 HandBrake CLI"; success "HandBrake CLI 安装完成"; echo "  转码: HandBrakeCLI -i input.mkv -o output.mp4 --preset='Fast 1080p30'"; }
tools_tesseract() { header "安装 Tesseract OCR"; if has_cmd tesseract; then success "已安装: $(tesseract --version | head -1)"; return 0; fi; pkg_install tesseract-ocr tesseract-ocr-chi-sim 2>/dev/null || pkg_install tesseract; success "Tesseract 安装完成"; echo "  识别: tesseract image.png output -l chi_sim+eng"; }
tools_chrony() { require_root || return 1; header "安装 chrony (NTP时间同步)"; if has_cmd chronyd; then success "chrony 已安装"; chronyc tracking; return 0; fi; pkg_install chrony; systemctl enable --now chronyd 2>/dev/null; chronyc tracking; success "chrony 安装完成，时间已同步"; }
tools_cups() { require_root || return 1; header "安装 CUPS (打印服务器)"; if has_cmd cupsd; then success "CUPS 已安装"; return 0; fi; pkg_install cups cups-client; systemctl enable --now cups 2>/dev/null; sed -i 's/Listen localhost:631/Listen 0.0.0.0:631/' /etc/cups/cupsd.conf 2>/dev/null; systemctl restart cups 2>/dev/null; success "CUPS 安装完成"; echo "  管理面板: https://$(hostname -I 2>/dev/null|awk '{print $1}'):631"; echo "  需允许远程访问: cupsctl --remote-admin"; }

# ============================================================
#  菜单
# ============================================================
tools_menu() {
    while true; do
        header "实用小工具集合"
        echo "  ── 搜索/设计 ──"
        echo "  1) SearXNG      (元搜索引擎)"
        echo "  2) Whoogle      (Google代理)"
        echo "  3) Excalidraw   (手绘白板)"
        echo "  4) Penpot       (Figma替代)"
        echo "  5) Draw.io      (流程图)"
        echo "  ── RSS/短链/图床 ──"
        echo "  6) Miniflux     (极简RSS)"
        echo "  7) YOURLS       (短链接)"
        echo "  8) Lychee       (图床)"
        echo "  ── 生活/管理 ──"
        echo "  9) Grocy        (家庭管理)"
        echo " 10) Homebox      (库存管理)"
        echo " 11) Wger         (健身管理)"
        echo " 12) Kimai        (时间追踪)"
        echo " 13) Invoice Ninja(发票)"
        echo "  ── 客服/分析 ──"
        echo " 14) Chatwoot     (客服系统)"
        echo " 15) Giscus       (评论系统)"
        echo " 16) Cachet       (状态页)"
        echo " 17) PostHog      (产品分析)"
        echo " 18) GrowthBook   (功能开关+A/B)"
        echo "  ── 邮件/工具 ──"
        echo " 19) Roundcube    (Web邮件)"
        echo " 20) Mailman      (邮件列表)"
        echo " 21) rclone       (网盘挂载)"
        echo " 22) FFmpeg       (音视频处理)"
        echo " 23) HandBrake    (视频转码)"
        echo " 24) Tesseract    (OCR识别)"
        echo " 25) chrony       (NTP时间同步)"
        echo " 26) CUPS         (打印服务器)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) tools_searxng; pause ;;
            2) tools_whoogle; pause ;;
            3) tools_excalidraw; pause ;;
            4) tools_penpot; pause ;;
            5) tools_drawio; pause ;;
            6) tools_miniflux; pause ;;
            7) tools_yourls; pause ;;
            8) tools_lychee; pause ;;
            9) tools_grocy; pause ;;
            10) tools_homebox; pause ;;
            11) tools_wger; pause ;;
            12) tools_kimai; pause ;;
            13) tools_invoiceninja; pause ;;
            14) tools_chatwoot; pause ;;
            15) tools_giscus; pause ;;
            16) tools_cachet; pause ;;
            17) tools_posthog; pause ;;
            18) tools_growthbook; pause ;;
            19) tools_roundcube; pause ;;
            20) tools_mailman; pause ;;
            21) tools_rclone; pause ;;
            22) tools_ffmpeg; pause ;;
            23) tools_handbrake; pause ;;
            24) tools_tesseract; pause ;;
            25) tools_chrony; pause ;;
            26) tools_cups; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    tools_menu
fi
