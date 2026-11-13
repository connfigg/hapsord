#!/bin/bash
set -euo pipefail
# =========================================
# 🚀 HAPROXY-XRAY DEPLOYER — COMPLETE FIXED
# ✅ Health check OK
# ✅ Fixed Xray config format
# ✅ Fixed Xray download + permissions
# ✅ Proper supervisord logging
# ✅ All features retained — Region select, Manual input, Exit
# ✅ No --startup-period
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
MAX_INST=2
CONCURRENCY=80
TIMEOUT=3600

# ==============================================
# 🔄 MAIN MENU
# ==============================================
while true; do
    clear
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${GREEN}🚀 HAPROXY-XRAY DEPLOYER — FINAL${NC}"
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
    echo "0) 🔙 Back"
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
            *)
                echo -e "${YELLOW}⚠️ Invalid selection — using us-east1${NC}"
                REGION="us-east1"
                ;;
        esac
        echo -e "${GREEN}✅ Region:${NC} $REGION"
    fi
    echo ""

    # ==============================================
    # ✅ CHECK PROJECT
    # ==============================================
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
    if [[ -z "$PROJECT_ID" ]]; then
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
        echo -e "${CYAN}📦 Creating repository: $REPO_NAME${NC}"
        gcloud artifacts repositories create "$REPO_NAME" \
            --repository-format=docker \
            --location="$REGION" \
            --project="$PROJECT_ID" \
            --quiet
    fi
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    ARTIFACT_REGISTRY_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"
    IMAGE_TAG="${ARTIFACT_REGISTRY_URL}/xray-haproxy:v1.0"
    SERVICE_NAME="xray-haproxy-$(openssl rand -hex 3)"

    # ==============================================
    # 📁 BUILD DIRECTORY
    # ==============================================
    BUILD_DIR=$(mktemp -d)
    trap 'rm -rf "$BUILD_DIR"' EXIT
    cd "$BUILD_DIR" || exit 1
    echo -e "${CYAN}📁 Working directory:${NC} $BUILD_DIR"

    # ==============================================
    # 📄 1. XRAY CONFIG — FIXED validated format
    # ==============================================
    echo -e "${CYAN}📝 Generating xray.json...${NC}"
    cat > xray.json <<'XRAYEOF'
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
        "clients": [
          {
            "id": "a2c4d6e8-f0b1-3c5d-7e9f-1a2b3c4d5e6f",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/xray-vless",
          "headers": {}
        }
      }
    },
    {
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "a2c4d6e8-f0b1-3c5d-7e9f-1a2b3c4d5e6f",
            "alterId": 0,
            "security": "auto"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/xray-vmess"
        }
      }
    },
    {
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "gcp-xray"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/xray-trojan"
        }
      }
    },
    {
      "port": 10003,
      "listen": "127.0.0.1",
      "protocol": "shadowsocks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 10003,
            "method": "aes-256-gcm",
            "password": "gcp-xray"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/xray-ss"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
XRAYEOF

    # ==============================================
    # 📄 2. HAPROXY CONFIG
    # ==============================================
    echo -e "${CYAN}📝 Generating haproxy.cfg...${NC}"
    cat > haproxy.cfg <<'HAPROXYEOF'
global
    log stdout format raw local0 info
    maxconn 10000
    nbthread 2

defaults
    mode http
    timeout connect 10s
    timeout client 3600s
    timeout server 3600s
    timeout http-request 30s
    timeout queue 30s

frontend http-in
    bind *:8080
    http-response set-header Server "Cloudflare"
    http-response set-header Access-Control-Allow-Origin "*"
    http-response set-header Access-Control-Allow-Methods "GET,POST,OPTIONS"
    http-response set-header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization"

    acl health path -i /health
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
    server vless 127.0.0.1:10000 maxconn 10000

backend vmess_back
    server vmess 127.0.0.1:10001 maxconn 10000

backend trojan_back
    server trojan 127.0.0.1:10002 maxconn 10000

backend ss_back
    server ss 127.0.0.1:10003 maxconn 10000

backend decoy_back
    server static 127.0.0.1:9090
HAPROXYEOF

    # ==============================================
    # 📄 3. SUPERVISORD CONFIG — FIXED logging
    # ==============================================
    echo -e "${CYAN}📝 Generating supervisord.conf...${NC}"
    cat > supervisord.conf <<'SUPERVISOREOF'
[supervisord]
nodaemon=true
user=root
loglevel=info
logfile=/dev/stdout
logfile_maxbytes=0
pidfile=/tmp/supervisord.pid

[program:decoy]
command=python3 -m http.server 9090 --bind 127.0.0.1
directory=/var/www/decoy
autostart=true
autorestart=true
startretries=10
startsecs=3
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
environment=PYTHONUNBUFFERED=1

[program:xray]
command=/opt/xray/xray run -config /etc/xray/config.json
autostart=true
autorestart=true
startretries=10
startsecs=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
user=root

[program:haproxy]
command=haproxy -f /etc/haproxy/haproxy.cfg -db
autostart=true
autorestart=true
startretries=10
startsecs=3
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
user=root
SUPERVISOREOF

    # ==============================================
    # 📄 4. DECOY PAGE
    # ==============================================
    echo -e "${CYAN}📝 Generating decoy page...${NC}"
    mkdir -p decoy
    cat > decoy/index.html <<'HTMLDECOYEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Application Gateway</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
            color: #e2e8f0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .card {
            background: #1e293b;
            padding: 48px 36px;
            border-radius: 16px;
            text-align: center;
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
            max-width: 400px;
            width: 100%;
        }
        .status-icon {
            width: 16px;
            height: 16px;
            background: #4ade80;
            border-radius: 50%;
            display: inline-block;
            margin-right: 8px;
            box-shadow: 0 0 12px #4ade8080;
        }
        h2 { font-size: 1.5rem; margin-bottom: 8px; color: #f1f5f9; }
        .status { color: #94a3b8; font-size: 1rem; }
    </style>
</head>
<body>
    <div class="card">
        <h2><span class="status-icon"></span>Application Gateway</h2>
        <p class="status">Service Operational</p>
    </div>
</body>
</html>
HTMLDECOYEOF

    # ==============================================
    # 📄 5. DOCKERFILE — FIXED Xray download & setup
    # ==============================================
    echo -e "${CYAN}📝 Generating Dockerfile...${NC}"
    cat > Dockerfile <<'DOCKEREOF'
FROM alpine:3.20

# Install system dependencies
RUN apk update && apk add --no-cache \
    haproxy \
    curl \
    ca-certificates \
    unzip \
    python3 \
    supervisor \
    tzdata \
    && rm -rf /var/cache/apk/*

# Set timezone
ENV TZ=UTC

# Download and install Xray — pinned verified version
RUN set -ex && \
    mkdir -p /opt/xray /etc/xray && \
    curl -fL "https://github.com/XTLS/Xray-core/releases/download/v1.8.24/Xray-linux-64.zip" -o /tmp/xray.zip && \
    unzip -q /tmp/xray.zip -d /opt/xray && \
    chmod +x /opt/xray/xray && \
    ls -la /opt/xray/ && \
    /opt/xray/xray --version && \
    rm /tmp/xray.zip

# Copy configuration files
COPY haproxy.cfg /etc/haproxy/haproxy.cfg
COPY xray.json /etc/xray/config.json
COPY supervisord.conf /etc/supervisord.conf
COPY decoy /var/www/decoy

# Verify config files
RUN ls -la /etc/xray/ && \
    ls -la /etc/haproxy/ && \
    ls -la /var/www/decoy/

# Expose port
EXPOSE 8080

# Start services via supervisord
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
DOCKEREOF

    # Verify files
    echo -e "${CYAN}📋 Files ready to build:${NC}"
    ls -la

    # ==============================================
    # 🔨 BUILD IMAGE
    # ==============================================
    echo ""
    echo -e "${CYAN}🔨 Building Docker image...${NC}"
    gcloud builds submit --project="$PROJECT_ID" --tag "$IMAGE_TAG" . --quiet

    # ==============================================
    # 🚀 DEPLOY TO CLOUD RUN
    # ==============================================
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
    # ✅ DEPLOYMENT COMPLETE
    # ==============================================
    SERVICE_URL=$(gcloud run services describe "$SERVICE
