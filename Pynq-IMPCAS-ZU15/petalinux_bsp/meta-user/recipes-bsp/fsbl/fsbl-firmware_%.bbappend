## Copyright (C) 2021 Xilinx, Inc
## SPDX-License-Identifier: BSD-3-Clause

python __anonymous() {
    bb.note("==================== fsbl-firmware_%.bbappend loaded ====================")
}

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

## Enable appropriate FSBL debug flags
YAML_COMPILER_FLAGS:append = " -DFSBL_PRINT"
