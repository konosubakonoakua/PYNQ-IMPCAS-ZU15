#! /bin/bash
set -x
set -e

target=$1
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

sudo cp -f $script_dir/.vimrc $target/home/xilinx/
sudo cp -f $script_dir/disable_flow_control.sh $target/etc/profile.d/
