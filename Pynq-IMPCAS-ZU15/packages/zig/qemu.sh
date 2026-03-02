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

log "[zig] start"

ZIG_ARCH=aarch64
ZIG_URL=https://ziglang.org/download/
PKG_FOLDER=/tmp/zig
INSTALL_PREFIX=$HOME/.local/
SEMVER_GREP_REGEX="[[:digit:]]{1,2}\.[[:digit:]]{1,2}\.[[:digit:]]{1,2}"
zig_pkg_file_suffix=".tar.xz"
zig_pkg_file_prefix=$(
	curl -L $ZIG_URL | grep -oE "zig-$ZIG_ARCH-linux-$SEMVER_GREP_REGEX\.tar\.xz" |
		awk 'NR==1{print $1}' | sort -r --version-sort | uniq | sed 's/\.tar\.xz//'
)

if [ -z "$zig_pkg_file_prefix" ]; then
	echo "Error: can not get zig version from $ZIG_URL" >&2
	exit 1
fi

zig_pkg_file=$zig_pkg_file_prefix$zig_pkg_file_suffix
zig_ver_latest=$(echo $zig_pkg_file | grep -oE "$SEMVER_GREP_REGEX")
zig_install_path=/opt/zig/$zig_pkg_file_prefix
mkdir -p $zig_install_path
dowload_link=https://ziglang.org/download/$zig_ver_latest/$zig_pkg_file

echo "Found zig latest veriosn: $zig_ver_latest"
echo "Download link: $dowload_link"

[[ ! -d $PKG_FOLDER ]] && mkdir -p $PKG_FOLDER
chown -R xilinx:xilinx $PKG_FOLDER
cd $PKG_FOLDER

if [[ ! -f $zig_pkg_file ]]; then
	wget $dowload_link || exit 1
else
	echo "$zig_pkg_file already exits."
	echo "Use cached version."
fi

echo "Deleting old zig pkg..."
rm -rf $zig_install_path
echo "Extracting new zig pkg..."
tar -xJf $zig_pkg_file -C /opt/zig
rm -rf $INSTALL_PREFIX/bin/zig
chmod +x $zig_install_path/zig
ln -s $(readlink -f $zig_install_path/zig) $(readlink -f $INSTALL_PREFIX/bin/zig)

echo "Zig installed into $zig_install_path"
rm -rf $PKG_FOLDER

log "[zig] done"
