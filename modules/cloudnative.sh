#!/usr/bin/env bash
# ============================================================
#  cloudnative.sh - K8s / 云原生
#  Rancher / K8s Dashboard / ArgoCD / Drone / Istio / OpenFaaS / Kubecost / Backstage
# ============================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
CN_BASE="${HOME}/cloudnative"

# ============================================================
#  Rancher
# ============================================================
cn_rancher() {
    header "安装 Rancher"
    echo "  K8s 多集群管理平台"
    _ensure_docker || return 1
    local port
    port="$(ask "Web端口" "8443")"
    docker run -d --name rancher -p "${port}:443" -p 80:80 \
        --privileged --restart=unless-stopped \
        rancher/rancher:latest
    sleep 15
    success "Rancher 部署完成: https://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  初始密码: docker logs rancher 2>&1 | grep 'Bootstrap Password'"
}

# ============================================================
#  Kubernetes Dashboard
# ============================================================
cn_dashboard() {
    header "安装 Kubernetes Dashboard"
    echo "  K8s 官方 Web UI"
    if ! has_cmd kubectl; then
        step "安装 kubectl"
        curl -fsSL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl" -o /usr/local/bin/kubectl
        chmod +x /usr/local/bin/kubectl
    fi
    step "部署 Dashboard"
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml 2>/dev/null
    step "创建管理员用户"
    kubectl create serviceaccount admin -n kubernetes-dashboard 2>/dev/null
    kubectl create clusterrolebinding admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:admin 2>/dev/null
    local token
    token="$(kubectl -n kubernetes-dashboard create token admin --duration=87600h 2>/dev/null)"
    step "启动代理"
    nohup kubectl proxy --address='0.0.0.0' --accept-hosts='^*$' >/tmp/k8s-proxy.log 2>&1 &
    success "K8s Dashboard 部署完成"
    echo "  访问: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
    echo "  Token: $token"
}

# ============================================================
#  ArgoCD
# ============================================================
cn_argocd() {
    header "安装 ArgoCD"
    echo "  GitOps 持续部署"
    if ! has_cmd kubectl; then warn "需先安装 kubectl 和 K8s 集群"; return 1; fi
    step "部署 ArgoCD"
    kubectl create namespace argocd 2>/dev/null
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>/dev/null
    step "暴露服务"
    kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}' 2>/dev/null
    local port
    port="$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)"
    local password
    password="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)"
    success "ArgoCD 部署完成"
    echo "  访问: https://$(hostname -I 2>/dev/null|awk '{print $1}'):${port}"
    echo "  账号: admin / $password"
}

# ============================================================
#  Drone
# ============================================================
cn_drone() {
    header "安装 Drone"
    echo "  轻量 CI/CD（Docker 原生）"
    _ensure_docker || return 1
    local dir="$CN_BASE/drone"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "8080")"
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  drone-server:
    image: drone/drone:latest
    container_name: drone
    ports:
      - "${port}:80"
    environment:
      - DRONE_GITEA_SERVER=http://gitea:3000
      - DRONE_GITEA_CLIENT_ID=xxx
      - DRONE_GITEA_CLIENT_SECRET=xxx
      - DRONE_RPC_SECRET=$(openssl rand -hex 16)
      - DRONE_SERVER_HOST=localhost:${port}
      - DRONE_SERVER_PROTO=http
    volumes:
      - ./data:/data
    restart: always
  drone-runner:
    image: drone/drone-runner-docker:latest
    environment:
      - DRONE_RPC_PROTO=http
      - DRONE_RPC_HOST=drone-server
      - DRONE_RPC_SECRET=xxx
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: always
EOF
    success "Drone 配置已生成: $dir/docker-compose.yml"
    warn "需手动配置 Gitea/GitHub OAuth 后执行: docker compose up -d"
}

# ============================================================
#  Istio
# ============================================================
cn_istio() {
    header "安装 Istio"
    echo "  服务网格（流量管理/安全/可观测）"
    if ! has_cmd kubectl; then warn "需先安装 kubectl 和 K8s 集群"; return 1; fi
    if has_cmd istioctl; then
        success "istioctl 已安装"
    else
        step "下载 istioctl"
        curl -L https://istio.io/downloadIstio | sh -
        local istio_dir
        istio_dir="$(ls -d istio-* 2>/dev/null | head -1)"
        [ -n "$istio_dir" ] && cp "$istio_dir/bin/istioctl" /usr/local/bin/
    fi
    step "安装 Istio (demo配置)"
    istioctl install --set profile=demo -y 2>/dev/null
    kubectl label namespace default istio-injection=enabled 2>/dev/null
    success "Istio 安装完成"
    echo "  部署 Kiali: kubectl apply -f <(istioctl manifest generate --set components.egressGateways[0].enabled=true)"
    echo "  查看: istioctl proxy-status"
}

# ============================================================
#  OpenFaaS
# ============================================================
cn_openfaas() {
    header "安装 OpenFaaS"
    echo "  Serverless 函数计算"
    if ! has_cmd kubectl; then warn "需先安装 kubectl 和 K8s 集群"; return 1; fi
    if ! has_cmd arkade; then
        step "安装 arkade"
        curl -SLs https://get.arkade.dev | sh
    fi
    step "安装 OpenFaaS"
    arkade install openfaas 2>/dev/null
    local password
    password="$(kubectl get secret -n openfaas basic-auth -o jsonpath="{.data.basic-auth-password}" 2>/dev/null | base64 -d)"
    success "OpenFaaS 安装完成"
    echo "  网关: http://gateway.openfaas:8080"
    echo "  账号: admin / $password"
    echo "  CLI: curl -SLs https://cli.openfaas.com | sh"
}

# ============================================================
#  Kubecost
# ============================================================
cn_kubecost() {
    header "安装 Kubecost"
    echo "  K8s 成本分析与优化"
    if ! has_cmd kubectl; then warn "需先安装 kubectl 和 K8s 集群"; return 1; fi
    if ! has_cmd helm; then warn "需先安装 Helm"; return 1; fi
    step "安装 Kubecost"
    helm repo add kubecost https://kubecost.github.io/cost-analyzer/ 2>/dev/null
    helm repo update 2>/dev/null
    helm install kubecost kubecost/cost-analyzer --namespace kubecost --create-namespace 2>/dev/null
    step "暴露服务"
    kubectl port-forward -n kubecost service/kubecost-cost-analyzer 9090 2>/dev/null &
    success "Kubecost 安装完成"
    echo "  访问: http://localhost:9090"
}

# ============================================================
#  Backstage
# ============================================================
cn_backstage() {
    header "安装 Backstage"
    echo "  内部开发者门户/服务目录"
    _ensure_docker || return 1
    local dir="$CN_BASE/backstage"
    mkdir -p "$dir" && cd "$dir" || return 1
    local port
    port="$(ask "Web端口" "7007")"
    step "克隆并构建"
    git clone --depth 1 https://github.com/backstage/backstage.git . 2>/dev/null || true
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  backstage:
    build: .
    container_name: backstage
    ports:
      - "${port}:7000"
    environment:
      - POSTGRES_HOST=db
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    depends_on:
      - db
    restart: always
  db:
    image: postgres:15
    environment:
      - POSTGRES_PASSWORD=postgres
    restart: always
EOF
    success "Backstage 配置已生成: $dir"
    warn "Backstage 需 Node.js 构建，建议参考官方文档手动部署"
}

# ============================================================
#  菜单
# ============================================================
cn_menu() {
    while true; do
        header "K8s / 云原生"
        echo "  1) Rancher          (多集群管理)"
        echo "  2) K8s Dashboard    (官方Web UI)"
        echo "  3) ArgoCD           (GitOps部署)"
        echo "  4) Drone            (轻量CI/CD)"
        echo "  5) Istio            (服务网格)"
        echo "  6) OpenFaaS         (Serverless)"
        echo "  7) Kubecost         (成本分析)"
        echo "  8) Backstage        (开发者门户)"
        echo "  0) 返回主菜单"
        echo ""
        local choice
        choice="$(ask "请选择" "")"
        case "$choice" in
            1) cn_rancher; pause ;;
            2) cn_dashboard; pause ;;
            3) cn_argocd; pause ;;
            4) cn_drone; pause ;;
            5) cn_istio; pause ;;
            6) cn_openfaas; pause ;;
            7) cn_kubecost; pause ;;
            8) cn_backstage; pause ;;
            0) break ;;
            *) warn "无效选项" ;;
        esac
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    detect_all
    cn_menu
fi
