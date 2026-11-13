#!/bin/bash
set -euo pipefail
# =========================================
# 🚀 HAPROXY-XRAY DEPLOYER — FINAL FIXED
# ✅ Removed wrong --health-check-path flag
# ✅ Menu: 1=Start, 0=Exit RETAINED
# ✅ Exact regions intact
# ✅ Health check via haproxy.cfg
# =========================================
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

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
MAX_INST=2
CONCURRENCY=80
TIMEOUT=3600

while true; do
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${GREEN}🚀 HAPROXY-XRAY DEPLOYER${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo ""
    echo "1) Start Deployment"
    echo "0) Exit"
    echo ""
    read -p "👉 Enter choice: " MAIN_CHOICE
    [[ "$MAIN_CHOICE" == "0" ]] && { echo -e "${GREEN}👋 Bye!${NC}"; exit 0; }
    [[ "$MAIN_CHOICE" != "1" ]] && { echo -e "${RED}❌ Invalid!${NC}"; sleep 1; continue; }

    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${GREEN}🌍 SELECT REGION${NC}"
    echo -e "${CYAN}==================================================${NC}"
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
    echo "99) Manual Input"
    echo "0) Back"
    echo ""
    read -p "👉 Enter number: " NUM

    if [[ "$NUM" == "0" ]]; then
        continue
    elif [[ "$NUM" == "99" ]]; then
        echo ""
        read -p "Enter region code: " REGION
        if [[ -z "$REGION" ]]; then
            echo -e "${RED}❌ Region cannot be empty!${NC}"
            sleep 1
            continue
        fi
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
            *)
                echo -e "${YELLOW}⚠️ Invalid — using us-east1${NC}"
                REGION="us-east1"
                ;;
        esac
    fi

    PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
    if [[ -z "$PROJECT_ID" ]]; then
        echo -e "${RED}❌ No GCP project set!${NC}"
        echo "Run: gcloud config set project YOUR_PROJECT_ID"
        echo ""
        read -p "Press Enter to return..."
        continue
    fi
    echo -e "${GREEN}✅ Project:${NC} $PROJECT_ID"
    echo -e "${GREEN}✅ Region:${NC} $REGION"
    echo ""

    gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project="$PROJECT_ID" --quiet

    REPO_NAME="xray-images"
    if ! gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        gcloud artifacts repositories create "$REPO_NAME" --repository-format=docker --location="$REGION" --project="$PROJECT_ID" --quiet
    fi
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/xray-haproxy:v3-final"
    SERVICE_NAME="xray-haproxy-$(openssl rand -hex 3)"

    BUILD_DIR=$(mktemp -d)
    trap 'rm -rf "$BUILD_DIR"' EXIT
    cd "$BUILD_DIR" || exit 1

    # === xray.json ===
    cat > xray.json <<EOF
{
  "log": {
    "loglevel": "info",
    "access": "/dev/stdout",
    "error": "/dev/stderr"
  },
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID_VLESS"}],
        "decryption": "none"
      },
      "streamSettings": {"network": "ws", "wsSettings": {"path": "$PATH_VLESS"}}
    },
    {
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$UUID_VMESS", "alterId": 0}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "$PATH_VMESS"}}
    },
    {
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$TROJAN_PASS"}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "$PATH_TROJAN"}}
    },
    {
      "port": 10003,
      "listen": "127.0.0.1",
      "protocol": "shadowsocks",
      "settings": {"servers": [{"address": "127.0.0.1", "port": 10003, "method": "aes-256-gcm", "password": "$SS_PASS"}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "$PATH_SS"}}
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

    # === haproxy.cfg — / and /health return 200 OK ===
    cat > haproxy.cfg <<'EOF'
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
    
    acl root_path path /
    acl health path /health
    acl vless path_beg /xray-vless
    acl vmess path_beg /xray-vmess
    acl trojan path_beg /xray-trojan
    acl ss path_beg /xray-ss
    
    use_backend health_back if root_path
    use_backend health_back if health
    use_backend vless_back if vless
    use_backend vmess_back if vmess
    use_backend trojan_back if trojan
    use_backend ss_back if ss
    default_backend decoy_back

backend health_back
    http-request return status 200 content-type text/plain string OK\n

backend vless_back
    server xray 127.0.0.1:10000
backend vmess_back
    server xray 127.0.0.1:10001
backend trojan_back
    server xray 127.0.0.1:10002
backend ss_back
    server xray 127.0.0.1:10003
backend decoy_back
    server web 127.0.0.1:9090
EOF

    # === supervisord.conf ===
    cat > supervisord.conf <<'EOF'
[supervisord]
nodaemon=true
user=root
loglevel=info
logfile=/dev/stdout
logfile_maxbytes=0

[program:web]
command=python3 -m http.server 9090 --bind 127.0.0.1
directory=/var/www/decoy
autostart=true
autorestart=true
startsecs=10
startretries=999
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr

[program:xray]
command=/opt/xray/xray run -config /etc/xray/config.json
autostart=true
autorestart=true
startsecs=15
startretries=999
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr

[program:haproxy]
command=haproxy -f /etc/haproxy/haproxy.cfg
autostart=true
autorestart=true
startsecs=5
startretries=999
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
EOF

    # === decoy page ===
    mkdir -p decoy
    echo '<html><body style="background:#0f172a;color:#e2e8f0;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;"><div style="text-align:center;"><h2>✅ Gateway Active</h2><p>Service Operational</p></div></body></html>' > decoy/index.html

    # === Dockerfile ===
    cat > Dockerfile <<'EOF'
FROM alpine:3.20

RUN apk update && apk add --no-cache \
    haproxy \
    curl \
    ca-certificates \
    unzip \
    python3 \
    supervisor \
    tzdata \
    && rm -rf /var/cache/apk/*

RUN mkdir -p /opt/xray /etc/xray /var/www/decoy

RUN curl -fL "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" -o /tmp/xray.zip \
    && unzip -q /tmp/xray.zip -d /opt/xray \
    && chmod +x /opt/xray/xray \
    && rm /tmp/xray.zip

COPY haproxy.cfg /etc/haproxy/haproxy.cfg
COPY xray.json /etc/xray/config.json
COPY supervisord.conf /etc/supervisord.conf
COPY decoy /var/www/decoy

EXPOSE 8080

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
EOF

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

    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region="$REGION" --format="value(status.url)")
    clear
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}✅ DEPLOYED SUCCESSFULLY!${NC}"
    echo -e "🔊 Service URL: $SERVICE_URL"
    echo -e "💚 Health Check: $SERVICE_URL/health"
    echo -e "${GREEN}==================================================${NC}"
    echo ""
    read -p "Press Enter to return..."
done
