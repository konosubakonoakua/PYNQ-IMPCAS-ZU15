#!/bin/bash

set -e
# set -x

if [[ -f /etc/profile.d/proxy.sh ]]; then
    rm -f /etc/profile.d/proxy.sh
    echo "[cleanup][proxy] Removed /etc/profile.d/proxy.sh"
fi

if [[ -f /tmp/stage4/helper.sh ]]; then
    rm -f /tmp/stage4/helper.sh
    echo "[cleanup][helper] Removed /tmp/stage4/helper.sh"
fi
