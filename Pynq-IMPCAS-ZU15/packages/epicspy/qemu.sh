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

python3 -m pip install numpy==1.21.5
python3 -m pip install pyserial==3.5 smbus3==0.5.5 spidev==3.8
python3 -m pip install caproto==1.3.0
python3 -m pip install grpcio==1.64.0 grpcio-tools==1.64.0
python3 -m pip install fastapi==0.136.0 uvicorn==0.44.0 python-socketio==5.16.1
python3 -m pip install Jinja2==3.0.3

python3 -m pip install phoebusgen==3.2.0
python3 -m pip install phoebusgen==3.2.0
python3 -m pip install epicsdbbuilder==1.5
python3 -m pip install epicscorelibs==7.0.10.99.0.0
python3 -m pip install pvxslibs==1.5.1 --no-deps
python3 -m pip install pyepics==3.5.2 --no-deps
python3 -m pip install cothread==2.18.3 --no-deps
python3 -m pip install softioc==4.6.1 --no-deps

python3 -c "import softioc;print(softioc.__version__)"

log "[epicspy] done"
