#!/bin/bash

set -e
set -x

if [ "$(id -u)" != "0" ]; then
  echo "to be run with sudo"
  exit 1
fi

# Decide target hostname:
# 1) use $PYNQ_BOARD if set
# 2) else use first argument if provided
# 3) else default
TARGET_HOST="${PYNQ_BOARD:-${1:-pynq}}"

# Optional: try PYNQ helper if available, but don't rely on it in chroot
if command -v pynq_hostname.sh >/dev/null 2>&1; then
  pynq_hostname.sh "$TARGET_HOST" || true
fi

# Always enforce hostname via files (most reliable in chroot/build)
echo "$TARGET_HOST" > /etc/hostname

# Rebuild /etc/hosts safely
# Keep localhost line; update/add 127.0.1.1 for the hostname
if [ -f /etc/hosts ]; then
  # Ensure localhost exists
  if ! grep -qE '^127\.0\.0\.1\s+localhost' /etc/hosts; then
    echo "127.0.0.1    localhost" > /etc/hosts.new
    cat /etc/hosts >> /etc/hosts.new
    mv /etc/hosts.new /etc/hosts
  fi

  if grep -qE '^127\.0\.1\.1' /etc/hosts; then
    sed -i -E "s/^127\.0\.1\.1\s+.*/127.0.1.1    ${TARGET_HOST}/" /etc/hosts
  else
    echo "127.0.1.1    ${TARGET_HOST}" >> /etc/hosts
  fi
else
  echo "127.0.0.1    localhost" > /etc/hosts
  echo "127.0.1.1    ${TARGET_HOST}" >> /etc/hosts
fi

# Best-effort runtime hostname change (may fail in chroot; that's OK)
hostname "$TARGET_HOST" 2>/dev/null || true

echo "Hostname set to: $(cat /etc/hostname)"
echo "Please manually reboot board:"
echo "sudo shutdown -r now"
echo ""
