# Requirement
Generated code must use english, answers & plans use chinese; kiss principle;

# Pynq-IMPCAS-ZU15 Project Context

This project defines the PYNQ board and image build environment for the IMPCAS Beam Loss Monitor based on the Xilinx Zynq UltraScale+ ZU15 FPGA. It includes hardware overlays, PetaLinux BSP configurations, and extensive rootfs customization scripts.

## Project Overview

-   **Target Hardware:** IMPCAS ZU15 Board (Zynq UltraScale+ MPSoC).
-   **Core Technologies:** PYNQ, PetaLinux, Vivado/Vitis, Python, EPICS.
-   **Key Features:**
    -   Custom hardware overlay (`base`) with GPIO, DMA, and Timer support.
    -   Integrated EPICS environment for control system communication.
    -   Extensive set of pre-installed packages (Zig, Rust, Node.js, vcpkg, etc.).
    -   Custom kernel modules (e.g., `u-dma-buf`).

## Directory Structure of bord folder Pynq-IMPACS-ZU15

-   `Pynq-IMPCAS-ZU15.spec`: Main PYNQ board specification file.
-   `base/`: Contains the default hardware overlay.
    -   `base.bit`, `base.hwh`: Hardware bitstream and description.
    -   `base.py`: Python driver class (`BaseOverlay`) for the overlay.
    -   `base.xsa`: Xilinx Shell Archive for PetaLinux.
    -   `notebooks/`: PYNQ Jupyter notebooks for testing the hardware.
-   `packages/`: Rootfs customization packages. Each subdirectory typically contains:
    -   `pre.sh`: Host-side setup/build script.
    -   `qemu.sh`: Image-side configuration script (runs in QEMU during build).
-   `petalinux_bsp/`: PetaLinux Board Support Package files.
    -   `meta-user/`: Custom Yocto recipes for device-tree, kernel, and modules.

## Key Components

### Hardware Overlay (`base`)
The `BaseOverlay` in `base/base.py` provides high-level Python APIs for:
-   **GPIO:** Controlling LEDs, reading binary counters, and interacting with User/Fiber IO.
-   **DMA:** Asynchronous data transfers using `axi_dma`.
-   **Interrupts:** Handling fabric interrupts from AXI Timer and GPIO.
-   **Monitoring:** Checking CMA memory and system interrupts.

### PetaLinux BSP
The `petalinux_bsp` directory contains hardware-specific configurations:
-   **Device Tree:** `system-user.dtsi` for custom hardware mapping.
-   **Kernel:** Configuration fragments in `recipes-kernel/linux`.
-   **FSBL:** Patches for CCI (Cache Coherent Interconnect) debug and snoop settings.

## Building and Running

### Image Building
This project is intended to be built using the PYNQ image build flow.
```bash
# Example command (requires PYNQ image_builder environment)
# cd PYNQ/sdbuild
# make BOARDDIR=/path/to/Pynq-IMPCAS-ZU15
```

### Hardware Deployment
To use the overlay on a running PYNQ board:
```python
from base import BaseOverlay
overlay = BaseOverlay("base.bit")
overlay.write_led(1)
print(overlay.read_binary_counter())
```

## Development Conventions

-   **Package Scripts:** Use `packages/helper/helper.sh` for common tasks (git cloning, GitHub release downloads, etc.).
-   **Kernel Modules:** New kernel modules should be added as recipes in `petalinux_bsp/meta-user/recipes-modules` and referenced in `packages/`.
-   **Overlay Updates:** When updating the hardware, ensure `base.bit`, `base.hwh`, and `base.py` are kept in sync.
