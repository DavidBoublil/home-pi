#!/bin/bash

# ensure sudoer
if [[ $EUID -ne 0 ]]; then
  echo "Error: Must be run as root (use sudo)." >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Error: You must pass the main user's username as a parameter (e.g., sudo $0 pi)." >&2
  exit 1
fi

if ! id "$1" &>/dev/null; then
  echo "Error: User '$1' does not exist on this system." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# Register repositories
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

# instalations
apt-get update
apt-get upgrade -y
apt-get install -y caddy

apt-get install -y docker.io docker-compose
usermod -aG docker "$1"

# caddy 
if [ -d "./caddy/html" ]; then
    mkdir -p /var/www/html
    cp -r ./caddy/html/. /var/www/html/
else
    echo "Warning: ./caddy/html not found (not running from repo root). Skipping HTML copy." >&2
fi

if [ -f "./caddy/Caddyfile" ]; then
    cp ./caddy/Caddyfile /etc/caddy/Caddyfile
    systemctl reload caddy
else
    echo "Warning: ./caddy/Caddyfile not found. Skipping Caddyfile copy." >&2
fi

systemctl enable --now caddy