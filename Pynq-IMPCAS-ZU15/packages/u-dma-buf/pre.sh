#! /usr/bin/bash

target=$1
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

module_name="u-dma-buf"


echo "[${module_name}] building kernel module: ${module_name} via petalinux-build."
cd ${BUILD_ROOT}/${PYNQ_BOARD}/petalinux_project && petalinux-build -c ${module_name} || exit 1

echo "[${module_name}] copying kernel module: ${module_name}."
src_dir="build/tmp/sysroots-components/*/${module_name}/lib/modules/"
kernel_version=$(ls ${src_dir})
sudo mkdir -p ${target}/lib/modules/${kernel_version}/updates
sudo cp -f ${src_dir}/*/updates/${module_name}.ko ${target}/lib/modules/${kernel_version}/updates/

echo "[${module_name}] kernel module: ${module_name} done."
