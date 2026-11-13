#!/bin/bash
set -euo pipefail
# =========================================
# 🚀 HAPROXY-XRAY DEPLOYER — FIXED
# ✅ Removed --startup-period (not supported in Qwiklabs)
# ✅ All features retained
# ✅ No syntax errors
# =========================================
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

# ==============================================
# 🔧 CONFIG
# ==============================================
UUID_VLESS="a2c4d6e8-f0b1-3c5d-7e9f-1a2b3c4d5e6f"
UUID_VMESS="a2c4d6e8-f0b1-3c5d-7e9f-1a2b3c4d5e6f"
TROJAN_PASS="gcp-xray"
SS_PASS="gcp-xray"

PATH_VLESS="/xray-vless"
PATH_VMESS="/xray-vmess"
PATH_TROJAN="/xray-trojan"
PATH_SS="/xray-ss"

MEMORY="2Gi"
CPU="2"
MIN_INST=1
MAX_INST=5
CONCURRENCY=130
TIMEOUT=3600

# ==============================================
# 🔄 MAIN LOOP
# ==============================================
while true; do
    clear
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${GREEN}🚀 HAPROXY-XRAY DEPLOYER${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""
    echo "What would you like to do?"
    echo "1) Start Deployment"
    echo "0) Exit"
    echo ""
    read -p "👉 Enter choice: " MAIN_CHOICE

    if [[ "$MAIN_CHOICE" == "0" ]]; then
        echo -e "${GREEN}👋 Goodbye!${NC}"
        exit 0
    fi

    if [[ "$MAIN_CHOICE" != "1" ]]; then
        echo -e "${RED}❌ Invalid choice!${NC}"
        sleep 1.5
        continue
    fi

    # ==============================================
    # 🗺️  REGION SELECT
    # ==============================================
    clear
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${GREEN}🌍 SELECT REGION${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""
    echo "--- Asia Pacific ---"
    echo "1) asia-southeast1   🇸🇬 Singapore"
    echo "2) asia-east1        🇹🇼 Taiwan"
    echo "3) asia-northeast1   🇯🇵 Tokyo"
    echo "4) asia-northeast3   🇰🇷 Seoul"
    echo "5) asia-south1       🇮🇳 Mumbai"
    echo ""
    echo "--- North America ---"
    echo "6) us-central1       🇺🇸 Iowa"
    echo "7) us-east1          🇺🇸 South Carolina"
    echo "8) us-east4          🇺🇸 N. Virginia"
    echo "9) us-west1          🇺🇸 Oregon"
    echo ""
    echo "--- Europe ---"
    echo "10) europe-west1     🇧🇪 Belgium"
    echo "11) europe-west4     🇳🇱 Netherlands"
    echo "12) europe-west9     🇫🇷 Paris"
    echo ""
    echo "99) ✏️  Manual Input"
    echo "0) 🔙 Back / Exit"
    echo ""
    read -p "👉 Enter number: " NUM

    if [[ "$NUM" == "0" ]]; then
        continue
    fi

    if [[ "$NUM" == "99" ]]; then
        echo ""
        read -p "Enter region code: " REGION
        if [[ -z "$REGION" ]]; then
            echo -e "${RED}❌ Region cannot be empty!${NC}"
            sleep 1.5
            continue
        fi
        echo -e "${GREEN}✅ Manual Region:${NC} $REGION"
    else
        case $NUM in
            1) REGION="asia-southeast1" ;;
            2) REGION="asia-east1" ;;
            3) REGION="asia-northeast1" ;;
            4) REGION="asia-northeast3" ;;
            5) REGION="asia-south1" ;;
            6) REGION="us-central1" ;;
            7) REGION="us-east1" ;;
            8) REGION="us-east4" ;;
            9) REGION="us-west1" ;;
            10) REGION="europe-west1" ;;
            11) REGION="europe-west4" ;;
            12) REGION="europe-west9" ;;
            *) echo -e "${YELLOW}⚠️ Invalid! Using Singapore${NC}"; REGION="asia-southeast1" ;;
        esac
        echo -e "${GREEN}✅ Region:${NC} $REGION"
    fi
    echo ""

    # ==============================================
    # ✅ CHECK PROJECT
    # ==============================================
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}❌ No GCP project set!${NC}"
        echo "Run: gcloud config set project YOUR_PROJECT_ID"
        echo ""
        read -p "Press Enter to return..."
        continue
    fi
    echo -e "${GREEN}✅ Project:${NC} $PROJECT_ID"

    # ==============================================
    # 🔧 ENABLE SERVICES
    # ==============================================
    echo -e "${CYAN}🔧 Enabling services...${NC}"
    gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project="$PROJECT_ID" --quiet

    # ==============================================
    # 📦 ARTIFACT REGISTRY
    # ==============================================
    REPO_NAME="xray-images"
    if ! gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        echo -e "${CYAN}📦 Creating repository...${NC}"
        gcloud artifacts repositories create "$REPO_NAME" \
            --repository-format=docker \
            --location="$REGION" \
            --project="$PROJECT_ID" \
            --quiet
    fi
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    ARTIFACT_REGISTRY_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"
    IMAGE_TAG="${ARTIFACT_REGISTRY_URL}/xray-haproxy:latest"
    SERVICE_NAME="xray-haproxy-$(openssl rand -hex 2)"

    # ==============================================
    # 📁 BUILD FILES
    # ==============================================
    BUILD_DIR=$(mktemp -d)
    trap 'rm -rf "$BUILD_DIR"' EXIT
    cd "$BUILD_DIR" || exit 1

    # XRAY CONFIG
    cat > xray.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": { "clients": [{"id": "$UUID_VLESS"}], "decryption": "none" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "$PATH_VLESS" } }
    },
    {
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": { "clients": [{"id": "$UUID_VMESS", "alterId": 0}] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "$PATH_VMESS" } }
    },
    {
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": { "clients": [{"password": "$TROJAN_PASS"}] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "$PATH_TROJAN" } }
    },
    {
      "port": 10003,
      "listen": "127.0.0.1",
      "protocol": "shadowsocks",
      "settings": { "clients": [{"password": "$SS_PASS"}], "method": "aes-256-gcm", "network": "tcp,udp" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "$PATH_SS" } }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

    # HAPROXY CONFIG
    cat > haproxy.cfg <<EOF
global
    log stdout format raw local0 info
    maxconn 10000
defaults
    mode http
    timeout connect 10s
    timeout client 3600s
    timeout server 3600s
frontend http-in
    bind *:8080
    http-response set-header Server Cloudflare
    acl health path /health
    acl p_vless path_beg /xray-vless
    acl p_vmess path_beg /xray-vmess
    acl p_trojan path_beg /xray-trojan
    acl p_ss path_beg /xray-ss
    use_backend health_back if health
    use_backend vless_back if p_vless
    use_backend vmess_back if p_vmess
    use_backend trojan_back if p_trojan
    use_backend ss_back if p_ss
    default_backend decoy_back
backend health_back
    http-request return status 200 content-type "text/plain" string "OK\n"
backend vless_back
    server vless 127.0.0.1:10000
backend vmess_back
    server vmess 127.0.0.1:10001
backend trojan_back
    server trojan 127.0.0.1:10002
backend ss_back
    server ss 127.0.0.1:10003
backend decoy_back
    server static 127.0.0.1:9091
EOF

    # SUPERVISORD
    cat > supervisord.conf <<EOF
[supervisord]
nodaemon=true
user=root
loglevel=info
[program:decoy]
command=python3 -m http.server 9091
directory=/var/www/decoy
autorestart=true
startsecs=3
[program:xray]
command=/opt/xray/xray run -config /etc/xray/config.json
autorestart=true
startsecs=5
[program:haproxy]
command=haproxy -f /etc/haproxy/haproxy.cfg
autorestart=true
startsecs=3
EOF

    # DECOY PAGE
    mkdir -p decoy
    cat > decoy/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Application Gateway</title>
    <style>
        body{font-family:system-ui;background:#0f172a;color:#e2e8f0;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
        .card{background:#1e293b;padding:40px;border-radius:12px;text-align:center}
        .status{color:#4ade80;font-weight:600;margin-top:10px}
        .dot{display:inline-block;width:10px;height:10px;background:#4ade80;border-radius:50%;margin-right:8px}
    </style>
</head>
<body>
    <div class="card">
        <h2>Application Gateway</h2>
        <div class="status"><span class="dot"></span> Operational</div>
    </div>
</body>
</html>
EOF

    # DOCKERFILE
    cat > Dockerfile <<EOF
FROM alpine:3.20
RUN apk update && apk add --no-cache haproxy curl ca-certificates unzip python3 supervisor && rm -rf /var/cache/apk/*
RUN mkdir -p /opt/xray && curl -fL "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" -o /tmp/xray.zip && unzip /tmp/xray.zip -d /opt/xray && chmod +x /opt/xray/xray && rm /tmp/xray.zip
COPY haproxy.cfg /etc/haproxy/haproxy.cfg
COPY xray.json /etc/xray/config.json
COPY supervisord.conf /etc/supervisord.conf
COPY decoy /var/www/decoy
EXPOSE 8080
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
EOF

    # ==============================================
    # 🔨 BUILD & DEPLOY — FIXED: REMOVED --startup-period
    # ==============================================
    echo -e "${CYAN}🔨 Building image...${NC}"
    gcloud builds submit --project="$PROJECT_ID" --tag "$IMAGE_TAG" . --quiet

    echo -e "${CYAN}🚀 Deploying to Cloud Run...${NC}"
    gcloud run deploy "$SERVICE_NAME" \
        --image="$IMAGE_TAG" \
        --region="$REGION" \
        --platform=managed \
        --port=8080 \
        --allow-unauthenticated \
        --no-cpu-throttling \
        --cpu="$CPU" \
        --memory="$MEMORY" \
        --min-instances="$MIN_INST" \
        --max-instances="$MAX_INST" \
        --concurrency="$CONCURRENCY" \
        --timeout="$TIMEOUT" \
        --quiet

    # ==============================================
    # ✅ DONE
    # ==============================================
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region="$REGION" --format="value(status.url)")

    clear
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}✅ DEPLOYMENT SUCCESS!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "🌍 Region:     $REGION"
    echo -e "🔗 Service:   $SERVICE_URL"
    echo -e "💚 Health:     $SERVICE_URL/health"
    echo ""
    echo -e "${GREEN}Paths:${NC}"
    echo -e "  VLESS:   $SERVICE_URL/xray-vless"
    echo -e "  VMess:   $SERVICE_URL/xray-vmess"
    echo -e "  Trojan:  $SERVICE_URL/xray-trojan"
    echo -e "  SS:      $SERVICE_URL/xray-ss"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    read -p "Press Enter to return to main menu..."
done
