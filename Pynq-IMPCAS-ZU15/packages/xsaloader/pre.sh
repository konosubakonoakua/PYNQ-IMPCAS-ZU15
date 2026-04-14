#! /bin/bash
set -x
set -e

target=$1
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

sudo cp $script_dir/xsaloader $target/usr/local/bin/
sudo chmod +x $target/usr/local/bin/xsaloader

