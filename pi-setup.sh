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

apt-get update
apt-get upgrade -y

apt-get install -y docker.io docker-compose
usermod -aG docker "$1"
