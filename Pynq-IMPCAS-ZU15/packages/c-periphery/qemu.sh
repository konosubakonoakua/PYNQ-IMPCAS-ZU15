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

log "[c-periphery] start"

cd $HOME

REPO_DIR="c-periphery"
REPO_URL="https://github.com/vsergeev/c-periphery.git"

git_clone_with_retry "$REPO_URL" --retries 3 --branch master
if [[ -d "$REPO_DIR" ]]; then
  echo "Directory '$REPO_DIR' exists. Start building..."
  cd "$REPO_DIR" && mkdir build && cd build && cmake -DBUILD_SHARED_LIBS=ON -DBUILD_TESTS=OFF .. && make && make install || exit 1
fi

log "[c-periphery] done"
