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

USER_NAME="$1"
export DEBIAN_FRONTEND=noninteractive

# --- UI / Progress Bar Setup ---
LOG_FILE="/tmp/pi-setup.log"
: > "$LOG_FILE"
TOTAL_STEPS=10
CURRENT_STEP=0
LOG_LINES=20

cleanup() {
  printf '\033[?25h' # restore cursor
}
trap cleanup EXIT
printf '\033[?25l' # hide cursor

draw_ui() {
  local label="$1"
  local percent=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
  local bar_width=40
  local filled=$(( percent * bar_width / 100 ))
  local empty=$(( bar_width - filled ))
  local cols
  cols=$(tput cols 2>/dev/null || echo 100)

  local bar
  bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
  bar+=$(printf '%*s' "$empty" '' | tr ' ' '-')

  printf '\033[H' # move cursor to top-left
  printf '[%s] %3d%% (%d/%d) %s\033[K\n' "$bar" "$percent" "$CURRENT_STEP" "$TOTAL_STEPS" "$label"
  printf '%*s\033[K\n' "$cols" '' | tr ' ' '-'

  # Print last 20 lines, truncated to terminal width to prevent wrapping
  local lines=0
  while IFS= read -r line; do
    printf '%.*s\033[K\n' "$cols" "$line"
    ((lines++))
  done < <(tr '\r' '\n' < "$LOG_FILE" | tail -n "$LOG_LINES")

  # Clear any remaining lines below
  while (( lines < LOG_LINES )); do
    printf '\033[K\n'
    ((lines++))
  done
}

run_step() {
  local label="$1"
  local func="$2"

  echo "=== $label ===" >> "$LOG_FILE"
  "$func" >> "$LOG_FILE" 2>&1 &
  local pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    draw_ui "$label"
    sleep 0.2
  done

  wait "$pid"
  ((CURRENT_STEP++))
  draw_ui "$label"
}

# --- Step Functions ---

step_prereqs() {
  apt-get update
  apt-get install -y curl gpg
}

step_caddy_repo() {
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
}

step_upgrade() {
  apt-get update
  apt-get upgrade -y
}

step_install_packages() {
  apt-get install -y --install-recommends nfs-kernel-server
  apt-get install -y caddy qbittorrent-nox docker.io docker-compose cockpit
  usermod -aG docker "$USER_NAME"
}

step_mount_drives() {
  local fstab_changed=0
  for label in meni_drive david_drive; do
      if ! mountpoint -q "/mnt/$label"; then
          mkdir -p "/mnt/$label"
          chattr +i "/mnt/$label"
      fi

      if ! grep -q "LABEL=$label" /etc/fstab; then
          echo "LABEL=$label  /mnt/$label  ext4  defaults,nofail,noatime,x-systemd.automount,x-systemd.device-timeout=10  0  2" >> /etc/fstab
          fstab_changed=1
      fi
  done

  if [[ $fstab_changed -eq 1 ]]; then
      systemctl daemon-reload
      mount -a
  fi

  for label in meni_drive david_drive; do
      ls "/mnt/$label" &>/dev/null || true
      if mountpoint -q "/mnt/$label"; then
          chown "$USER_NAME:$USER_NAME" "/mnt/$label"
      fi
  done
}

step_nfs() {
  local fsid=1
  for label in meni_drive david_drive; do
      if ! grep -q "^/mnt/$label " /etc/exports 2>/dev/null; then
          echo "/mnt/$label  *(rw,async,no_subtree_check,insecure,fsid=$fsid)" >> /etc/exports
      fi
      ((fsid++))
  done

  exportfs -ra
  systemctl enable --now nfs-kernel-server
}

step_caddy() {
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

  systemctl enable --now caddy
}

step_qbittorrent() {
  if [ -f "./qbitorrent/qBittorrent.conf" ]; then
      systemctl stop "qbittorrent-nox@$USER_NAME" 2>/dev/null || true
      mkdir -p "/home/$USER_NAME/.config/qBittorrent"
      cp ./qbitorrent/qBittorrent.conf "/home/$USER_NAME/.config/qBittorrent/qBittorrent.conf"
      chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config/qBittorrent"
  else
      echo "Warning: ./qbitorrent/qBittorrent.conf not found. Skipping config copy." >&2
  fi

  systemctl enable --now "qbittorrent-nox@$USER_NAME"
}

step_cockpit() {
  mkdir -p /etc/cockpit
  cat <<EOF > /etc/cockpit/cockpit.conf
[WebService]
AllowUnencrypted = true
EOF

  systemctl enable --now cockpit.socket
  systemctl try-restart cockpit.service
}

step_docker() {
  local docker_data="/opt/docker"
  mkdir -p "$docker_data/filebrowser/database" "$docker_data/filebrowser/config" "$docker_data/portainer"
  chown -R "$USER_NAME:$USER_NAME" "$docker_data"

  PUID=$(id -u "$USER_NAME") PGID=$(id -g "$USER_NAME") USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6) \
    docker compose -f ./docker/docker-compose.yaml up -d
}

# --- Execution ---
printf '\033[2J\033[H' # clear screen once

run_step "Updating apt & installing prerequisites" step_prereqs
run_step "Adding Caddy repository"               step_caddy_repo
run_step "Upgrading system packages"             step_upgrade
run_step "Installing core services"              step_install_packages
run_step "Mounting external drives"              step_mount_drives
run_step "Configuring NFS shares"                step_nfs
run_step "Configuring Caddy"                     step_caddy
run_step "Configuring qBittorrent"               step_qbittorrent
run_step "Configuring Cockpit"                   step_cockpit
run_step "Starting Docker containers"            step_docker

echo ""
echo "Setup complete! Full log saved to $LOG_FILE"