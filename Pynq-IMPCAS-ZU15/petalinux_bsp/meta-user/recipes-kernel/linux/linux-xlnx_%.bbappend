SRC_URI:append = " file://fixed-kernel-version.cfg"

KERNEL_CONFIG_FRAGMENTS += "fixed-kernel-version.cfg"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

