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

log "[pwndbg] start"

# INFO: https://pwndbg.re/stable/setup/
BYPASS_SUDO='2a\sudo(){ while [[ "$1" == -* ]]; do shift; done; "$@"; }'
curl -qsL 'https://install.pwndbg.re' | sed -e "$BYPASS_SUDO" | bash -s -- -t pwndbg-gdb

log "[pwndbg] done"
