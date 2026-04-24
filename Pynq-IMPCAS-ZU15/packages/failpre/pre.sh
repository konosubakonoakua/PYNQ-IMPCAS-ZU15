#!/bin/bash

set -x
set -e

target=$1
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "[failpre] intentional failure."
exit 1
