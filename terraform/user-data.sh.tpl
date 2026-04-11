#!/bin/bash
set -euo pipefail
exec > /var/log/instance-setup.log 2>&1

echo "=== Instance Setup Starting $(date) ==="

# --- System Updates ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y curl unzip jq nginx unattended-upgrades

# Enable automatic security updates
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTOUPGRADE'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOUPGRADE

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

# --- Swap File ---
%{ if swap_size_gb > 0 ~}
if [ ! -f /swapfile ]; then
  fallocate -l ${swap_size_gb}G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
%{ endif ~}

# --- Node.js 22 LTS ---
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# --- AWS CLI v2 ---
if ! command -v aws &>/dev/null; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
  rm -rf /tmp/aws /tmp/awscliv2.zip
fi

# --- Install OpenClaw ---
npm install -g openclaw@${openclaw_version}

# --- Create service user ---
useradd -r -m -s /bin/bash openclaw || true

OPENCLAW_HOME="/home/openclaw/.openclaw"
mkdir -p "$OPENCLAW_HOME"

# --- Fetch secrets from SSM Parameter Store ---
REGION="${aws_region}"
PREFIX="${ssm_prefix}"

GEMINI_KEY=$(aws ssm get-parameter --name "$PREFIX/gemini_api_key" \
  --with-decryption --region "$REGION" --query 'Parameter.Value' --output text)
TAVILY_KEY=$(aws ssm get-parameter --name "$PREFIX/tavily_api_key" \
  --with-decryption --region "$REGION" --query 'Parameter.Value' --output text)
AUTH_TOKEN=$(aws ssm get-parameter --name "$PREFIX/openclaw_auth_token" \
  --with-decryption --region "$REGION" --query 'Parameter.Value' --output text)

# Auto-generate auth token if not provided
if [ "$AUTH_TOKEN" = "auto" ]; then
  AUTH_TOKEN=$(openssl rand -hex 32)
fi

# --- Build openclaw.json (replace secret placeholders) ---
CONFIG='${openclaw_config}'

# Replace auth token and public IP placeholders
CONFIG=$(echo "$CONFIG" | jq --arg tok "$AUTH_TOKEN" --arg ip "${public_ip}" \
  '.gateway.auth.token = $tok | walk(if type == "string" and . == "https://__PUBLIC_IP__" then "https://" + $ip else . end)')

# Fetch per-agent bot tokens from SSM and replace placeholders
%{ for agent in agents ~}
AGENT_TOKEN_${agent.id}=$(aws ssm get-parameter \
  --name "$PREFIX/agents/${agent.id}/telegram_bot_token" \
  --with-decryption --region "$REGION" --query 'Parameter.Value' --output text)
CONFIG=$(echo "$CONFIG" | jq --arg tok "$AGENT_TOKEN_${agent.id}" \
  'walk(if type == "string" and . == "__TELEGRAM_BOT_TOKEN_${agent.id}__" then $tok else . end)')
%{ endfor ~}

# Write config
umask 077
echo "$CONFIG" | jq . > "$OPENCLAW_HOME/openclaw.json"

# --- Create workspaces ---
mkdir -p "$OPENCLAW_HOME/workspace/memory"
%{ for i, agent in agents ~}
%{ if i > 0 ~}
mkdir -p "$OPENCLAW_HOME/workspace-${agent.id}/memory"
%{ endif ~}
%{ endfor ~}

# Shared memory directory (symlinked into each workspace)
mkdir -p "$OPENCLAW_HOME/shared-memory"
ln -sf "$OPENCLAW_HOME/shared-memory" "$OPENCLAW_HOME/workspace/memory/shared"
%{ for i, agent in agents ~}
%{ if i > 0 ~}
ln -sf "$OPENCLAW_HOME/shared-memory" "$OPENCLAW_HOME/workspace-${agent.id}/memory/shared"
%{ endif ~}
%{ endfor ~}

# --- Environment file ---
cat > "$OPENCLAW_HOME/.env" <<ENVFILE
AWS_PROFILE=default
AWS_REGION=$REGION
GEMINI_API_KEY=$GEMINI_KEY
TAVILY_API_KEY=$TAVILY_KEY
ENVFILE

# --- Fix ownership ---
chown -R openclaw:openclaw /home/openclaw
umask 022

# --- Systemd service ---
cat > /etc/systemd/system/openclaw.service <<'SYSTEMD'
[Unit]
Description=OpenClaw AI Assistant Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/home/openclaw/.openclaw
EnvironmentFile=/home/openclaw/.openclaw/.env
ExecStart=/usr/bin/openclaw gateway
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/openclaw/.openclaw
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable openclaw
systemctl start openclaw

# --- Nginx reverse proxy (self-signed cert) ---
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/server.key \
  -out /etc/nginx/ssl/server.crt \
  -subj "/CN=openclaw"

cat > /etc/nginx/sites-available/openclaw <<'NGINX'
server {
    listen 443 ssl;

    ssl_certificate     /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

echo "=== Instance Setup Complete $(date) ==="
