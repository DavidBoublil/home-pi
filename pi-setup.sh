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

# Installations
apt-get update
apt-get install -y curl gpg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

apt-get update
apt-get upgrade -y
apt-get install -y caddy
apt-get install -y qbittorrent-nox
apt-get install -y docker.io docker-compose
usermod -aG docker "$1"
apt-get install -y nfs-kernel-server


# Mount drive, hardcoded meni_drive david_drive, they are hardcoded in qbitorrent config to
FSTAB_CHANGED=0

for label in meni_drive david_drive; do
    if ! mountpoint -q "/mnt/$label"; then
        mkdir -p "/mnt/$label"
        chattr +i "/mnt/$label"
    fi

    if ! grep -q "LABEL=$label" /etc/fstab; then
        echo "LABEL=$label  /mnt/$label  ext4  defaults,nofail,noatime,x-systemd.automount,x-systemd.device-timeout=10  0  2" >> /etc/fstab
        FSTAB_CHANGED=1
    fi
done

if [[ $FSTAB_CHANGED -eq 1 ]]; then
    systemctl daemon-reload
    mount -a
fi

# Share drives via NFS
for label in meni_drive david_drive; do
    if ! grep -q "^/mnt/$label " /etc/exports 2>/dev/null; then
        echo "/mnt/$label  *(rw,async,no_subtree_check,insecure)" >> /etc/exports
    fi
done

exportfs -ra
systemctl enable --now nfs-kernel-server

# caddy 
if [ -d "./caddy/html" ]; then
    mkdir -p /var/www/html
    cp -r ./caddy/html/. /var/www/html/
else
    echo "Warning: ./caddy/html not found (not running from repo root). Skipping HTML copy." >&2
fi

if [ -f "./caddy/Caddyfile" ]; then
    cp ./caddy/Caddyfile /etc/caddy/Caddyfile
    systemctl reload-or-restart caddy
else
    echo "Warning: ./caddy/Caddyfile not found. Skipping Caddyfile copy." >&2
fi


# qbitorrent
if [ -f "./qbitorrent/qBittorrent.conf" ]; then
    systemctl stop "qbittorrent-nox@$1" 2>/dev/null || true
    mkdir -p "/home/$1/.config/qBittorrent"
    cp ./qbitorrent/qBittorrent.conf "/home/$1/.config/qBittorrent/qBittorrent.conf"
    chown -R "$1:$1" "/home/$1/.config/qBittorrent"
else
    echo "Warning: ./qbitorrent/qBittorrent.conf not found. Skipping config copy." >&2
fi

systemctl enable --now caddy
systemctl enable --now "qbittorrent-nox@$1"

