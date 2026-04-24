#!/bin/bash

set -e
# set -x

. /etc/environment
for f in /etc/profile.d/*.sh; do source $f; done

export HOME=/home/xilinx

LIB="/tmp/stage4/helper.sh"
[[ -f "$LIB" ]] || {
	echo "Missing $LIB" >&2
	exit 1
}
source "$LIB"


cd $HOME

log "[nodejs] start"
log "[nodejs] Installing fnm..."

curl -fsSL https://fnm.vercel.app/install | bash

FNM_PATH="$HOME/.local/share/fnm"
FNM="$FNM_PATH/fnm"
[ -x "$FNM" ] || die "[nodejs] fnm binary not found at $FNM"

export PATH="$FNM_PATH:$PATH"
eval "$($FNM env)"
log "[nodejs] $($FNM --version) installed."

log "[nodejs] Installing Node.js..."
$FNM install --arch arm64 --lts
$FNM use default
command -v node >/dev/null 2>&1 || die "[nodejs] Node.js installation failed"
npm config set registry https://registry.npmmirror.com
log "[nodejs] Node.js $(node --version) installed; npm configured"


log "[nodejs] Installing bun..."
curl -fsSL https://bun.com/install | bash

BUN_PATH="$HOME/.bun"
BUN="$BUN_PATH/bin/bun"
chmod +x $BUN
[ -x "$BUN" ] || die "[nodejs] bun binary not found at $BUN"

export PATH="$BUN_PATH:$PATH"
log "[nodejs] bun $($BUN --version) installed."

chown -R xilinx:xilinx "$HOME/.local"
chown -R xilinx:xilinx "$HOME/.bun"
log "[nodejs] done"
