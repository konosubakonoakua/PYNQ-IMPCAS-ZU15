#!/bin/bash
set -e
set -x

target=$1

PROXY_URL="${PYNQ_PROXY_URL:-}"

if [[ -z "$PROXY_URL" ]]; then
  echo "[proxy] PYNQ_PROXY_URL not set, skip"
  exit 0
fi

sudo tee "$target/etc/profile.d/proxy.sh" > /dev/null <<EOF
################################################################################
# proxy settings auto-generated at build time
#
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
################################################################################
EOF

sudo chmod 0644 "$target/etc/profile.d/proxy.sh"
echo "[proxy] proxy injected: $PROXY_URL"
