#!/bin/bash

echo "Setting user/root/samba password to ${PYNQ_PSWD:-"xilinx"}"
echo -e "${PYNQ_PSWD:-"xilinx"}\\n${PYNQ_PSWD:-"xilinx"}" | passwd xilinx
echo -e "${PYNQ_PSWD:-"xilinx"}\\n${PYNQ_PSWD:-"xilinx"}" | smbpasswd -a xilinx
echo -e "${PYNQ_PSWD:-"xilinx"}\\n${PYNQ_PSWD:-"xilinx"}" | passwd root
