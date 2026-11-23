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
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

# instalations
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y caddy

apt-get install -y docker.io docker-compose
usermod -aG docker "$1"

# caddy 
if [ -d "./caddy/html" ]; then
    sudo cp -r ./caddy/html/. /var/www/html/
else
    echo "Warning: ./caddy/html not found (not running from repo root). Skipping HTML copy." >&2
fi

if [ -f "./caddy/Caddyfile" ]; then
    sudo cp ./caddy/Caddyfile /etc/caddy/Caddyfile
    sudo systemctl reload caddy
else
    echo "Warning: ./caddy/Caddyfile not found. Skipping Caddyfile copy." >&2
fi

sudo systemctl enable --now caddy