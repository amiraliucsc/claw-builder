#!/bin/bash
set -euo pipefail
exec > /var/log/instance-setup.log 2>&1

echo "=== Instance Setup Starting $(date) ==="

# --- System Updates ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y curl unzip jq unattended-upgrades

# Enable automatic security updates
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

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

echo "=== Instance Setup Complete $(date) ==="
