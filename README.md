# Server Toolkit - Linux 服务器运维脚本集

一套模块化的 Linux 服务器运维 Bash 脚本集，**自动识别服务器环境**（发行版、包管理器、架构、虚拟化、云厂商），提供 Swap 管理、备份、监控、安全加固、性能优化、系统清理、网络诊断、Docker 管理等功能。

## 特性

- **自动识别**：自动检测操作系统、包管理器、CPU 架构、初始化系统、虚拟化类型、云厂商
- **跨发行版**：支持 Debian/Ubuntu、CentOS/RHEL/Rocky/Alma、Alpine、Arch、openSUSE 等
- **模块化设计**：每个功能独立成模块，可单独调用
- **安全可靠**：修改操作前自动备份原文件，关键操作需二次确认
- **零依赖**：纯 Bash 实现，仅依赖系统基础命令

## 快速开始

```bash
# 克隆或上传到服务器
cd server-toolkit

# 添加执行权限
chmod +x main.sh modules/*.sh

# 运行交互式菜单
sudo ./main.sh

# 或直接调用某个模块
./main.sh info
./main.sh swap status
./main.sh monitor overview
```

## 目录结构

```
server-toolkit/
├── main.sh              # 主入口（交互式菜单 + 命令行调用）
├── lib/
│   ├── colors.sh        # 颜色输出与交互函数
│   └── common.sh        # 公共库：系统检测、包管理、服务管理封装
├── modules/
│   ├── info.sh          # 系统信息（OS/硬件/网络/用户/服务）
│   ├── mirror.sh        # 软件源换源（linuxmirrors.cn一键换源/清华源）
│   ├── essential.sh     # 环境完善（一键安装基础工具/分类安装/缺失检测/配置初始化）
│   ├── swap.sh          # Swap/Zram 管理（创建/扩容/删除/内存压缩）
│   ├── backup.sh        # 备份恢复（目录/MySQL/PostgreSQL/系统配置）
│   ├── monitor.sh       # 系统监控（资源概览/实时/进程/端口/告警/报告）
│   ├── terminal.sh      # 终端美化（Zsh/OhMyZsh/Powerlevel10k/MOTD/Locale）
│   ├── devtools.sh      # 开发工具（常用工具/Mise/NextTrace/Speedtest）
│   ├── autoupdate.sh    # 自动系统更新（定时更新/无人值守/自动重启）
│   ├── security.sh      # 安全加固（SSH/防火墙/fail2ban/密码策略/审计）
│   ├── optimize.sh      # 性能优化（sysctl/ulimit/BBR/时间同步/I/O调度）
│   ├── cleanup.sh       # 系统清理（包缓存/日志/旧内核/Docker/大文件）
│   ├── network.sh       # 网络诊断（ping/DNS/端口/流量/路由/测速）
│   ├── docker.sh        # Docker 管理（安装/容器/镜像/Compose/快速部署）
│   ├── yunzai.sh        # Yunzai机器人（Node环境/依赖/Valkey/Yunzai/NapCat/启动管理）
│   ├── botframework.sh  # 机器人框架（AstrBot/NoneBot/Koishi/Mirai/LangBot/qq-ai-bot）
│   ├── aiagent.sh       # AI Agent（DeepSeek Harness/Claude Code/Codex等）
│   ├── aistack.sh       # AI应用栈（OneAPI/Ollama/Open WebUI/FastGPT等）
│   ├── devops.sh        # DevOps工具（Portainer/NPM/Uptime Kuma等）
│   ├── selfhost.sh      # 自建服务（Alist/Vaultwarden/Jellyfin等）（DeepSeek Harness/Claude Code/Codex/Penguin/LangGraph/CrewAI/AutoGen）
│   └── reinstall.sh     # 一键DD重装系统（Linux/Windows/Alpine/netboot.xyz）
├── backups/             # 备份文件默认存放目录
└── logs/                # 日志与报告目录
```

## 功能模块详解

### 1. 系统信息 (info)
- 操作系统、内核、运行时间、负载
- CPU 型号/核心、内存、磁盘
- 网卡、IP、路由、DNS、公网 IP
- 用户登录记录、sudo 用户
- systemd 服务状态、失败服务

### 2. 软件源换源 (mirror)
- 一键换源（直接调用 linuxmirrors.cn 官方脚本，交互式选择镜像）
- 查看当前源配置

### 3. 一键完善系统环境 (essential)
- **一键安装全部基础工具**（10 大类 100+ 包）
- 分类选择安装（基础/网络/压缩/编译/监控/文件系统/终端/Python/安全/数据库客户端）
- 常用命令缺失检测（30+ 命令一键巡检）
- 基础配置初始化（常用目录/vimrc/bash别名/Git配置/时区）
- 自动适配 apt/dnf/apk/pacman 包名差异
- 安装前自动跳过已安装的包，只装缺失的

### 4. Swap / Zram 管理 (swap)
- 查看当前 Swap 状态和 swappiness
- 自动推荐 Swap 大小（根据内存）
- 创建/扩容 Swap 文件（fallocate 优先，dd 兜底）
- 删除 Swap（支持单个或全部）
- 调整 swappiness 并持久化
- **Zram 内存压缩**（比传统 swap 更高效，支持 zstd/lz4 算法，开机自启）

### 5. 备份与恢复 (backup)
- 任意目录 tar.gz 备份
- MySQL/MariaDB 备份（单库或全库，自动 gzip）
- PostgreSQL 备份（pg_dump / pg_dumpall）
- 系统配置一键备份（含已安装包列表）
- 备份列表查看、恢复、过期清理

### 6. 系统监控 (monitor)
- 资源概览（CPU/内存/磁盘/网络/负载）
- 实时监控（类 top，2 秒刷新）
- 进程 TOP 10（按 CPU/内存）
- 监听端口列表
- 资源告警检测（CPU/内存/磁盘/OOM/只读文件系统）
- 生成完整监控报告

### 7. 终端美化 (terminal)
- Zsh + Oh My Zsh + Powerlevel10k 主题（GitHub/Gitee 双源）
- 常用插件：自动补全、语法高亮、补全增强
- 常用别名和历史记录优化
- 动态 MOTD 登录欢迎信息（系统信息+服务状态）
- 中文 Locale 配置

### 8. 开发工具 (devtools)
- 常用系统工具一键安装（curl/wget/git/vim/htop/jq/tree/build-essential 等 30+）
- Mise 多语言版本管理（Python/Node.js/Go/Rust/Java 等）
- NextTrace 可视化路由追踪
- Speedtest CLI 官方测速工具
- 已安装工具版本检查

### 9. 自动系统更新 (autoupdate)
- 立即更新系统
- 定时自动更新（每天/每周/自定义，cron 实现）
- 可选更新后自动重启
- 无人值守安全更新（Debian/Ubuntu unattended-upgrades）
- 更新日志查看与状态管理

### 10. 安全加固 (security)
- SSH 加固（改端口、禁 root、禁密码登录、超时断开）
- 防火墙配置（自动适配 ufw/firewalld/iptables）
- Fail2ban 安装与配置（防爆破）
- 密码策略（最小长度、复杂度、有效期）
- 安全审计（异常 UID 用户、空密码、SUID 文件、失败登录）
- 一键安全加固

### 11. 性能优化 (optimize)
- sysctl 内核参数调优（网络/内存/文件句柄）
- **BBR + fq 网络加速**（一键开启，自动检测内核支持）
- 文件描述符上限（ulimit + systemd）
- 时区设置与 NTP 时间同步
- I/O 调度器（SSD→none，HDD→bfq）
- 关闭不必要的桌面服务
- 清理页缓存
- 一键优化

### 12. 系统清理 (cleanup)
- 包管理器缓存清理（apt/dnf/apk/pacman 自适应）
- 系统日志清理（journal、轮转日志、大日志截断）
- 旧内核清理
- 用户缓存清理（npm/gradle/m2/回收站）
- Docker 清理（镜像/容器/卷/构建缓存）
- 大文件查找
- 一键清理

### 13. 网络诊断 (network)
- 多目标连通性测试（国内+国外 DNS）
- DNS 诊断与一键换 DNS
- 端口检测（bash /dev/tcp，无需 nc）
- 网卡流量统计
- TCP 连接状态与 TOP 远程 IP
- 路由追踪
- 下载速度测试

### 14. Docker 管理 (docker)
- 一键安装 Docker（直接调用 linuxmirrors.cn 官方脚本）
- 容器管理（启动/停止/重启/删除/进入/日志）
- 镜像管理（列表/拉取/删除/清理悬空）
- Docker Compose 管理
- 资源统计
- 快速运行常用服务（Nginx/MySQL/Redis/PostgreSQL/MongoDB）

### 15. 机器人框架一键安装 (botframework)
- 16 个主流框架：AstrBot / NoneBot2 / Koishi / Mirai / LangBot / qq-ai-bot / Yunzai / 早柚核心(gsuid_core) / Wechaty / nanobot / LobeChat / OpenClaw / Dify / n8n / Lagrange.Core / NapCat
- 自动配置运行环境（Python 3.10+ / Node.js 18+ / Java 17+ / Docker / .NET）
- 自动安装 uv / pipx / npm 国内源
- 分类展示：机器人框架 / AI平台工作流 / 协议端，每种框架提供 Docker 和原生两种部署方式
- 统一安装目录 ~/bots/，状态一键查看
- Docker 部署自动配置时区、端口映射、重启策略、数据卷

### 16. AI Agent 一键安装 (aiagent)
- 4 个 CLI 编程助手：DeepSeek Harness / Claude Code / OpenAI Codex / PenguinHarness
- 3 个 Python Agent 框架：LangGraph / CrewAI / AutoGen
- 自动配置 Node.js 20+ / Python 3.11+ / uv 环境
- CLI 工具支持官方脚本和 npm 两种安装方式
- Python 框架自动创建虚拟环境 + 示例代码
- 统一项目目录 ~/ai-agents/，状态一键查看

### 18. AI 应用栈 (aistack)
- 7 个应用：OneAPI / new-api / Ollama / Open WebUI / FastGPT / MaxKB / RAGFlow
- 分类展示：API中转 / 本地模型 / 前端知识库
- Docker 一键部署，自动配置时区和数据卷
- 统一数据目录 ~/ai-stack/，状态一键查看

### 19. DevOps 可视化工具 (devops)
- 5 个工具：Portainer / Nginx Proxy Manager / Uptime Kuma / Netdata / Glances
- Docker 一键部署，自动配置时区和数据卷
- 统一数据目录 ~/devops/，状态一键查看

### 20. 自建服务 (selfhost)
- 6 个服务：Alist / FileBrowser / Vaultwarden / Jellyfin / Memos / Gitea
- Docker 一键部署，自动配置时区和数据卷
- 统一数据目录 ~/selfhost/，状态一键查看

### 21. 一键 DD 重装系统 (reinstall)
> ⚠️ 危险操作：将清除整个硬盘所有数据！

- 重装为 Linux（Ubuntu/Debian/CentOS/Rocky/Alma/Alpine/Arch/Kali 等 12 种）
- 安装 Windows（自动查找 ISO 或自定义链接，支持 Win10/11/Server）
- DD 自定义镜像（.img/.gz/.xz 等 RAW 镜像）
- 引导到 Alpine Live OS（不删数据，用于救砖/手动操作）
- 引导到 netboot.xyz（不删数据，VNC 手动安装）
- 取消已计划的重装
- 集成 bin456789/reinstall，国内镜像自动加速

## 命令行直接调用

```bash
# 查看 swap 状态
./main.sh swap status

# 创建 swap（交互输入参数）
sudo ./main.sh swap create

# 资源概览
./main.sh monitor overview

# 安全审计
sudo ./main.sh security audit

# 生成监控报告
./main.sh monitor report

# 一键清理
sudo ./main.sh cleanup all
```

## 自动识别的系统信息

脚本启动时自动检测并展示：

| 检测项 | 说明 |
|--------|------|
| 操作系统 | 发行版名称、版本、家族 |
| 包管理器 | apt / dnf / yum / apk / pacman / zypper |
| CPU 架构 | x86_64 / aarch64 / armv7l 等 |
| 初始化系统 | systemd / openrc / sysvinit |
| 虚拟化 | KVM / VMware / Docker / LXC / 物理机 |
| 云厂商 | AWS / 阿里云 / 腾讯云 / Azure / GCP / 华为云 |
| 硬件 | CPU 核心、内存、根分区容量 |
| 网络 | 主机 IP |

## 扩展新模块

在 `modules/` 下新建 `xxx.sh`，遵循以下模板：

```bash
#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

xxx_function1() {
    # 你的功能
}

xxx_menu() {
    while true; do
        header "模块名"
        echo "  1) 功能1"
        echo "  0) 返回"
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) xxx_function1; pause ;;
            0) break ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    xxx_menu
fi
```

然后在 `main.sh` 的 `MODULES` 数组中添加 `"xxx:模块描述"` 即可。

## 注意事项

1. **建议使用 sudo 运行**，大部分系统级操作需要 root 权限
2. **SSH 加固前请确认已配置密钥**，避免禁用密码登录后无法登录
3. 所有修改配置文件的操作都会自动创建 `.bak.时间戳` 备份
4. 备份文件默认存放在 `backups/` 目录，定期清理避免占满磁盘
5. 脚本在 Debian 12、Ubuntu 22.04、CentOS 7/8、Alpine 3.x 上测试通过

## 许可证

MIT License
