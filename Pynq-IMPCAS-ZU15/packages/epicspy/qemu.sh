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

log "[epicspy] start"

# chown -R xilinx:xilinx /opt/epics

# python3 -m pip install numpy==1.21.5
python3 -m pip install pyserial smbus3 spidev
python3 -m pip install caproto
python3 -m pip install grpcio==1.64.0 grpcio-tools==1.64.0
python3 -m pip install epicsdbbuilder==1.5
python3 -m pip install epicscorelibs==7.0.10.99.0.0
python3 -m pip install pyepics==3.5.2 --no-deps
python3 -m pip install cothread==2.18.3 --no-deps
python3 -m pip install softioc==4.6.1 --no-deps

log "[epicspy] done"
