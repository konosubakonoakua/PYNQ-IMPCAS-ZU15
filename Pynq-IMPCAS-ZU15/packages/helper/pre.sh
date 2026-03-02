#!/bin/bash

set -e
set -x

target=$1
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

sudo mkdir -p $target/tmp/stage4
sudo cp $script_dir/helper.sh $target/tmp/stage4/helper.sh
