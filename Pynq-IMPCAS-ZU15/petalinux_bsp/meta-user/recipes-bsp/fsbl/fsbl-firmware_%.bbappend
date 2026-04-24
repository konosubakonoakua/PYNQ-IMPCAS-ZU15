## Copyright (C) 2021 Xilinx, Inc
## SPDX-License-Identifier: BSD-3-Clause

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://0001-Enable-CCI-debug-NIDEN-and-SPINDEN-on-CCI400.patch \
    file://0002-Enable-CCI-snoop-on-APU-Slave3-on-CCI400.patch \
    file://0003-Enable-sharing-on-HPC0-and-HPC1-Slave0-on-CCI400.patch \
"

## Enable appropriate FSBL debug flags
YAML_COMPILER_FLAGS:append = " -DFSBL_PRINT"
