#!/bin/bash
set -e

# ==============================================
# 📋 CONFIGURATION — EDIT HERE
# ==============================================
SERVICE_NAME="xray-haproxy"
AR_REPO="xray-deploy"

# 🔑 CREDENTIALS
UUID_VLESS="a2c4d6e8-f0b1-3c5d-7e9f-1a2b3c4d5e6f"
UUID_VMESS="a2c4d6e8-f0b1-3c5d-7e9f-1a2b3c4d5e6f"
TROJAN_PASS="gcp-xray"
SS_PASS="gcp-xray"

# 🗺️ FALLBACK REGIONS
FALLBACK_REGIONS=(
  "asia-southeast1"    # Singapore — BEST for PH
  "asia-southeast2"    # Jakarta
  "asia-east1"         # Taiwan
  "asia-east2"         # Hong Kong
  "asia-northeast1"    # Tokyo
  "asia-northeast2"    # Osaka
  "asia-northeast3"    # Seoul
  "us-central1"        # Iowa
  "us-east1"           # South Carolina
  "us-west1"           # Oregon
  "europe-west1"       # Belgium
  "europe-west2"       # London
  "europe-central2"    # Warsaw
)
# ==============================================

clear
echo "=========================================="
echo " 🚀 Xray + HAProxy + SUPERVISORD Deployer"
echo "=========================================="
echo ""

# ✅ Check dependencies
command -v gcloud >/dev/null 2>&1 || { echo "❌ gcloud CLI required"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "❌ Docker required"; exit 1; }

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
  echo "❌ No GCP project set!"
  echo "👉 Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi
echo "✅ Project: $PROJECT_ID"
echo ""

# 🌍 REGION SELECTOR
echo "🌍 Fetching available regions..."
AVAILABLE_REGIONS=$(gcloud run regions list --format="value(name)" 2>/dev/null | tr '\n' ' ')

if [ -n "$AVAILABLE_REGIONS" ]; then
  echo "✅ Online list loaded"
  REGION_LIST=($(echo "$AVAILABLE_REGIONS"))
else
  echo "⚠️  Using built-in region list"
  REGION_LIST=("${FALLBACK_REGIONS[@]}")
fi

echo ""
echo "🗺️  Select Region:"
for i in "${!REGION_LIST[@]}"; do
  printf "   [%2d] %s\n" "$((i+1))" "${REGION_LIST[$i]}"
done
echo "   [ M ] Manual input — type your own region code"
echo ""
read -p "👉 Enter number OR M for manual: " CHOICE

if [[ "$CHOICE" =~ ^[Mm]$ ]]; then
  read -p "✏️  Enter region code (e.g. us-south1): " REGION
  if [ -z "$REGION" ]; then
    echo "⚠️  Empty — using asia-southeast1"
    REGION="asia-southeast1"
  fi
elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#REGION_LIST[@]} ]; then
  REGION="${REGION_LIST[$((CHOICE-1))]}"
else
  echo "⚠️  Invalid — using asia-southeast1"
  REGION="asia-southeast1"
fi
echo "✅ Region: $REGION"
echo ""

# 📦 Artifact Registry Setup
echo "📦 Setting up Artifact Registry..."
if ! gcloud artifacts repositories describe "$AR_REPO" --location="$REGION" &>/dev/null; then
  gcloud artifacts repositories create "$AR_REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Xray Deployments" >/dev/null
  echo "✅ Repository created"
else
  echo "✅ Repository ready"
fi
echo ""

# 🔧 GENERATE CONFIG FILES
echo "🔧 Generating configuration files..."
mkdir -p decoy

# === haproxy.cfg — UPDATED: tunnel & keep-alive ===
cat > haproxy.cfg <<'EOF'
global
    log stdout format raw local0 info
    maxconn 10000
    nbthread 4

defaults
    mode http
    log global
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client 300s
    timeout server 300s
    timeout http-request 10s
    timeout tunnel 1h
    timeout http-keep-alive 60s

frontend http-in
    bind *:8080
    
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    http-response set-header X-Frame-Options "DENY"
    http-response set-header X-Content-Type-Options "nosniff"
    
    stick-table type ip size 50000 expire 10m store http_req_rate(10s)
    http-request track-sc0 src
    http-request deny if { sc_http_req_rate(0) gt 30 }
    
    tcp-request connection reject if { src_conn_cur gt 100 }
    
    acl is_decoy path_beg /
    acl xray_vless path_beg /xray-vless
    acl xray_vmess path_beg /xray-vmess
    acl xray_trojan path_beg /xray-trojan
    acl xray_ss path_beg /xray-ss
    acl is_websocket hdr_upgrade -i websocket
    
    use_backend vless_back if xray_vless or is_websocket
    use_backend vmess_back if xray_vmess or is_websocket
    use_backend trojan_back if xray_trojan or is_websocket
    use_backend ss_back if xray_ss or is_websocket
    default_backend decoy_back

backend vless_back
    server vless 127.0.0.1:10000 maxconn 5000
    timeout connect 15s
    timeout server 1h

backend vmess_back
    server vmess 127.0.0.1:10001 maxconn 5000
    timeout connect 15s
    timeout server 1h

backend trojan_back
    server trojan 127.0.0.1:10002 maxconn 5000
    timeout connect 15s
    timeout server 1h

backend ss_back
    server ss 127.0.0.1:10003 maxconn 5000
    timeout connect 15s
    timeout server 1h

backend decoy_back
    server static 127.0.0.1:9091
EOF

# === xray.json ===
cat > xray.json <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID_VLESS"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/xray-vless" }
      }
    },
    {
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$UUID_VMESS", "alterId": 0, "security": "auto"}]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/xray-vmess" }
      }
    },
    {
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$TROJAN_PASS"}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/xray-trojan" }
      }
    },
    {
      "port": 10003,
      "listen": "127.0.0.1",
      "protocol": "shadowsocks",
      "settings": {
        "clients": [{"password": "$SS_PASS"}],
        "method": "aes-256-gcm",
        "network": "tcp,udp"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/xray-ss" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
JSON

# === supervisord.conf — NEW! ===
cat > supervisord.conf <<'EOF'
[supervisord]
nodaemon=true
logfile=/dev/stdout
logfile_maxbytes=0
loglevel=info
pidfile=/run/supervisord.pid

[program:decoy-server]
command=python3 -m http.server 9091
directory=/var/www/decoy
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
autorestart=true
startsecs=3
stopwaitsecs=5
user=nobody

[program:xray]
command=/opt/xray/xray run -config /etc/xray/config.json
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
autorestart=true
startsecs=5
stopwaitsecs=10
user=nobody

[program:haproxy]
command=haproxy -f /etc/haproxy/haproxy.cfg
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
autorestart=true
startsecs=3
stopwaitsecs=5
EOF

# === decoy/index.html ===
cat > decoy/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Service Portal</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:system-ui}
body{background:linear-gradient(135deg,#1e3a5f,#2d5a87);min-height:100vh;display:flex;align-items:center;justify-content:center;color:#fff}
.box{text-align:center;padding:2.5rem;max-width:500px}
h1{font-size:1.8rem;margin-bottom:0.5rem}
p{opacity:0.75;line-height:1.6;margin-bottom:2rem}
.status{display:inline-flex;align-items:center;gap:0.6rem;background:rgba(255,255,255,0.08);padding:0.6rem 1.4rem;border-radius:50px}
.dot{width:10px;height:10px;background:#4ade80;border-radius:50%;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.3}}
</style>
</head>
<body>
  <div class="box">
    <h1>✅ Service Operational</h1>
    <p>All systems are running normally.</p>
    <div class="status"><span class="dot"></span><span>Online • Secure</span></div>
  </div>
</body>
</html>
EOF

# === Dockerfile — UPDATED: Supervisord Entrypoint ===
cat > Dockerfile <<'EOF'
FROM alpine:3.20

ENV XRAY_VERSION="v24.11.10"

RUN apk update && apk add --no-cache haproxy wget unzip python3 py3-supervisord && \
    rm -rf /var/cache/apk/*

# Install Xray
RUN mkdir -p /opt/xray && \
    wget -qO /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip" && \
    unzip /tmp/xray.zip -d /opt/xray && chmod +x /opt/xray/xray && rm /tmp/xray.zip

# Copy configs
COPY haproxy.cfg /etc/haproxy/haproxy.cfg
COPY xray.json /etc/xray/config.json
COPY supervisord.conf /etc/supervisord.conf
COPY decoy /var/www/decoy

EXPOSE 8080

WORKDIR /var/www/decoy

# ✅ Supervisord as entrypoint — auto-restart each service
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
EOF

echo "✅ Configuration files ready"
echo ""

# 🏗️ BUILD & DEPLOY
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/${SERVICE_NAME}:latest"

echo "🐳 Building container image..."
docker build --platform linux/amd64 -t "$IMAGE_URI" . >/dev/null

echo "📤 Pushing to Artifact Registry..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
docker push "$IMAGE_URI" >/dev/null

echo "☁️ Deploying to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE_URI" \
  --region="$REGION" \
  --platform=managed \
  --port=8080 \
  --allow-unauthenticated \
  --session-affinity \
  --no-use-http2 \
  --no-cpu-throttling \
  --ingress=all \
  --cpu=2 \
  --memory=4Gi \
  --min-instances=1 \
  --max-instances=6 \
  --concurrency=120 \
  --timeout=3600s >/dev/null

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region="$REGION" --format="value(status.url)")

echo ""
echo "=========================================="
echo "      ✅ DEPLOYMENT SUCCESSFUL!"
echo "=========================================="
echo "🌐 Service URL: $SERVICE_URL"
echo "📍 Region:      $REGION"
echo ""
echo "📋 CONNECTION DETAILS"
echo "------------------------------------------"
echo "🔹 VLESS"
echo "   Address: $SERVICE_URL"
echo "   Port:    443"
echo "   Path:    /xray-vless"
echo "   UUID:    $UUID_VLESS"
echo ""
echo "🔹 VMESS"
echo "   Address: $SERVICE_URL"
echo "   Port:    443"
echo "   Path:    /xray-vmess"
echo "   UUID:    $UUID_VMESS"
echo ""
echo "🔹 TROJAN"
echo "   Address: $SERVICE_URL"
echo "   Port:    443"
echo "   Path:    /xray-trojan"
echo "   Password: gcp-xray"
echo ""
echo "🔹 SHADOWSOCKS"
echo "   Address: $SERVICE_URL"
echo "   Port:    443"
echo "   Path:    /xray-ss"
echo "   Method:   aes-256-gcm"
echo "   Password: gcp-xray"
echo "=========================================="
echo "🔧 Powered by: Supervisord — Auto-Restart Enabled ✅"
