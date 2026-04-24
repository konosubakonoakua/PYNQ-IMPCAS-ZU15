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

log "[u-dma-buf] start"

module_name="u-dma-buf"
depmod -a `ls /lib/modules`
echo "${module_name}" | tee /etc/modules-load.d/${module_name}.conf

log "[u-dma-buf] done"

