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

log "[cynq] start"

cd $HOME
git_clone_with_retry https://github.com/konosubakonoakua/cynq.git --retries 3 --branch main
git_clone_with_retry https://github.com/konosubakonoakua/pynq_capi.git --retries 3 --branch master

log "[cynq] done"
