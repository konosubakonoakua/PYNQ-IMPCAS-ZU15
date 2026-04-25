FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# 1. Add the initialization file to the source list
SRC_URI += "file://regs.init"

# 2. Prepend 'init' to the partition attribute list
# The space after 'init' is mandatory to prevent string concatenation during .split() [cite: 18]
BIF_PARTITION_ATTR:prepend = "init "

# 3. Define the BIF flag for the init partition
# This results in the [init] tag in the final .bif file [cite: 7, 19]
BIF_PARTITION_ATTR[init] = "init"

# 4. Map the logical 'init' partition to the physical file path
# The file will be located in ${WORKDIR} after being fetched via SRC_URI [cite: 5, 6]
BIF_PARTITION_IMAGE[init] = "${WORKDIR}/regs.init"
