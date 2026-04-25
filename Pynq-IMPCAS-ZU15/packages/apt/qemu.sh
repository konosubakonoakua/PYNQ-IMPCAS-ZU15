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

log "[apt] start"

# BUG: Redirection from https to 'http://mirrors.ustc.edu.cn/ubuntu-ports/dists/jammy/main/binary-arm64/Packages.xz' is forbidden [IP: 192.168.138.254 7897]
#
# tee /etc/apt/sources.list.d/multistrap-jammy.list > /dev/null <<'EOF'
# deb https://mirrors.lzu.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
# deb https://mirrors.lzu.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
# deb https://mirrors.lzu.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
# deb http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse
# EOF

apt_update

# INFO: don't add sudo
apt_install \
	ripgrep smbclient avahi-utils btop iotop ncdu sysstat strace ltrace \
	u-boot-tools tio net-tools minicom libtool re2c swig npm \
	cmake autoconf automake gdb-multiarch gdbserver valgrind meson ninja-build \
	git-lfs screen tmux procserv xterm gawk xz-utils util-linux \
	i2c-tools spi-tools coreutils device-tree-compiler elfutils busybox

apt_install bc bison flex pkg-config libssl-dev libelf-dev libncurses-dev \
	libfdt-dev libnet-dev libpcap-dev libusb-1.0-0-dev python3-dev \
	libz-dev libbpf-dev gpiod libgpiod-dev

apt_install libboost-all-dev libzmq3-dev libczmq-dev libzmq5
apt_install libspdlog-dev libfmt-dev nlohmann-json3-dev libyaml-cpp-dev libyaml-dev

apt_install gcc-12 g++-12 universal-ctags

log "[apt] done"
