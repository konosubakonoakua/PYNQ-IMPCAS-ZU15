SUMMARY = "Userspace DMA Buffer Kernel Module"
DESCRIPTION = "Kernel module to provide a buffer for DMA from userspace"
LICENSE = "BSD-2-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=bebf0492502927bef0741aa04d1f35f5"

SRC_URI = "git://github.com/ikwzm/udmabuf.git;protocol=https;branch=master"

PV = "v5.5.0"
SRCREV = "288f2f2281ebc95a7c8da9ca31d5be08e9aa0705"

S = "${WORKDIR}/git"

inherit module
