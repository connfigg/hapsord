cat << 'EOF' > hapsord1.sh
#!/bin/bash
set -e

SERVICE_NAME="xray-haproxy"
AR_REPO="xray-deploy"

UUID_VLESS="a2c4d6e8-f0b1-3c5d-7e9f-1a2b3c4d5e6f"
UUID_VMESS="a2c4d6e8-f0b1-3c5d-7e9f-1a2b3c4d5e6f"
TROJAN_PASS="gcp-xray"
SS_PASS="gcp-xray"

FALLBACK_REGIONS=(
  "us-central1|Iowa, US 🇺🇸"
  "us-east1|South Carolina, US 🇺🇸"
  "us-east4|N. Virginia, US 🇺🇸"
  "us-west1|Oregon, US 🇺🇸"
  "asia-east1|Taiwan 🇹🇼"
  "asia-southeast1|Singapore 🇸🇬 — BEST for PH"
  "asia-northeast1|Tokyo, Japan 🇯🇵"
  "asia-northeast3|Seoul, South Korea 🇰🇷"
  "asia-south1|Mumbai, India 🇮🇳"
  "europe-west1|Belgium 🇧🇪"
  "europe-west4|Netherlands 🇳🇱"
  "europe-west9|Paris, France 🇫🇷"
)

clear
echo "=========================================="
echo " 🚀 Xray + HAProxy + SUPERVISORD Deployer"
echo "=========================================="
echo ""

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

REGION_LIST=("${FALLBACK_REGIONS[@]}")

while true; do
  echo ""
  echo "🗺️  Select Region:"
  for i in "${!REGION_LIST[@]}"; do
    CODE="${REGION_LIST[$i]%%|*}"
    DESC="${REGION_LIST[$i]#*|}"
    printf "   [%2d] %-16s — %s\n" "$((i+1))" "$CODE" "$DESC"
  done
  echo "   [ M ] Manual input"
  echo "   [ E ] Exit"
  echo ""
  read -p "👉 Enter your choice: " CHOICE

  case "$CHOICE" in
    [Ee]) exit 0 ;;
    [Mm])
      read -p "✏️  Enter region code (e.g. us-central1): " REGION
      [ -n "$REGION" ] && break
      ;;
    [0-9]*)
      if [ "$CHOICE" -ge 1 ] 2>/dev/null && [ "$CHOICE" -le ${#REGION_LIST[@]} ]; then
        SELECTED_ITEM="${REGION_LIST[$((CHOICE-1))]}"
        REGION="${SELECTED_ITEM%%|*}"
        break
      fi
      ;;
  esac
done
echo ""

echo "📦 Setting up Artifact Registry in $REGION..."
if ! gcloud artifacts repositories describe "$AR_REPO" --location="$REGION" &>/dev/null; then
  gcloud artifacts repositories create "$AR_REPO" --repository-format=docker --location="$REGION" >/dev/null
fi

mkdir -p decoy

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
    
    acl xray_vless path_beg /xray-vless
    acl xray_vmess path_beg /xray-vmess
    acl xray_trojan path_beg /xray-trojan
    acl xray_ss path_beg /xray-ss
    
    use_backend vless_back if xray_vless
    use_backend vmess_back if xray_vmess
    use_backend trojan_back if xray_trojan
    use_backend ss_back if xray_ss
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

[program:xray]
command=/opt/xray/xray run -config /etc/xray/config.json
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
autorestart=true

[program:haproxy]
command=haproxy -f /etc/haproxy/haproxy.cfg
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
autorestart=true
EOF

cat > decoy/index.html <<'EOF'
<!DOCTYPE html>
<html><head><title>Welcome</title></head><body><h1>Service Online</h1></body></html>
EOF

# Dockerfile nga direktang nokuha sa latest release ug walay gihikawang version variable
cat > Dockerfile <<'EOF'
FROM alpine:3.20

RUN apk update && apk add --no-cache haproxy curl ca-certificates unzip python3 supervisor && \
    mkdir -p /opt/xray && \
    curl -fSL "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" -o /tmp/xray.zip && \
    unzip /tmp/xray.zip -d /opt/xray && \
    chmod +x /opt/xray/xray && \
    rm -rf /tmp/xray.zip /var/cache/apk/*

COPY haproxy.cfg /etc/haproxy/haproxy.cfg
COPY xray.json /etc/xray/config.json
COPY supervisord.conf /etc/supervisord.conf
COPY decoy /var/www/decoy

EXPOSE 8080
WORKDIR /var/www/decoy

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
EOF

IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/${SERVICE_NAME}:latest"

echo "🐳 Building container image (No Cache)..."
docker build --no-cache --platform linux/amd64 -t "$IMAGE_URI" .

echo "📤 Pushing to Artifact Registry..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
docker push "$IMAGE_URI"

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
  --timeout=3600s

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region="$REGION" --format="value(status.url)")

echo ""
echo "=========================================="
echo "      ✅ DEPLOYMENT SUCCESSFUL!"
echo "=========================================="
echo "🌐 Service URL: $SERVICE_URL"
echo "📍 Region:      $REGION"
echo "=========================================="
EOF
