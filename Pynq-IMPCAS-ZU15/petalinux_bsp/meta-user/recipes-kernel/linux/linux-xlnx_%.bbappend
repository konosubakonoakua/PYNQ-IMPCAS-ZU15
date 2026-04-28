FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://disable-kernel-localversion-auto.cfg"
SRC_URI += "file://0001-scripts-setlocalversion-physically-remove-the-sign.patch"

LINUX_VERSION_EXTENSION = "-xilinx-v2024.1-impcas"

python __anonymous() {
    bb.note("==================== linux-xlnx_%.bbappend loaded ====================")
}
