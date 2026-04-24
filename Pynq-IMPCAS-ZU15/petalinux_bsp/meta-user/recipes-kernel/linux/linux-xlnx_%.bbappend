FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://disable-kernel-localversion-auto.cfg"

LINUX_VERSION_EXTENSION = "-xilinx-v2024.1-impcas"
