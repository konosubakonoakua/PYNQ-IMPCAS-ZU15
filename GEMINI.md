# Requirement
Generated code must use english, answers & plans use chinese; kiss principle;

# Pynq-IMPCAS-ZU15 Project Context

This project defines the PYNQ board and image build environment for the IMPCAS Beam Loss Monitor based on the Xilinx Zynq UltraScale+ ZU15 FPGA. It integrates the PYNQ framework with custom hardware, PetaLinux BSPs, and a rich set of rootfs customizations.

## Project Structure

-   `Pynq-IMPCAS-ZU15/`: The core board definition directory.
    -   `Pynq-IMPCAS-ZU15.spec`: Board specification for PYNQ image builder.
    -   `base/`: Default hardware overlay (Bitstream, XSA, and Python drivers).
    -   `packages/`: Rootfs customization packages (EPICS, Node.js, Zig, Rust, etc.).
    -   `petalinux_bsp/`: Yocto/PetaLinux recipes and configuration.
-   `pynq/`: Submodule containing the PYNQ library source code.
-   `scripts/`: Utility scripts for flashing SD cards, package verification, and environment setup.
-   `patches/`: Patches applied to the PYNQ framework during build.

## Key Components

### Hardware Overlay (`base`)
Located in `Pynq-IMPCAS-ZU15/base/`, the `BaseOverlay` provides Python APIs for:
-   **GPIO:** LED control, binary counters, and Fiber/User IO interaction.
-   **DMA:** High-speed data transfers using `axi_dma`.
-   **Interrupts:** Handling fabric interrupts via AXI Timers and GPIO.
-   **Management:** Monitoring CMA memory and system health.

### PetaLinux BSP
The `petalinux_bsp` directory contains:
-   **Device Tree:** `system-user.dtsi` for mapping custom PL peripherals.
-   **Kernel Modules:** Recipes for modules like `u-dma-buf`.
-   **FSBL/PMUFW:** Hardware-specific boot firmware configurations.

### Custom Packages
Extensive rootfs customization is handled via `Pynq-IMPCAS-ZU15/packages/`:
-   **Control Systems:** EPICS and `epicspy` integration.
-   **Languages:** Zig, Rust, Node.js, and vcpkg support.
-   **Utilities:** `nng`, `c-periphery`, `pwndbg`, and custom CLI tools.

## Development Workflows

### Image Building
Building the SD card image requires the PYNQ `image_builder` environment.
```bash
# Example build command
cd pynq/sdbuild
make BOARDDIR=../../Pynq-IMPCAS-ZU15
```

### Flashing and Testing
Use the provided scripts for deployment:
-   `scripts/flashsd.sh`: Flash a generated image to an SD card.
-   `scripts/pkgverify.sh`: Verify package installation and environment state.

### Overlay Updates
When modifying the Vivado design:
1.  Export the XSA to `Pynq-IMPCAS-ZU15/base/base.xsa`.
2.  Update `base.bit` and `base.hwh`.
3.  Adjust `Pynq-IMPCAS-ZU15/base/base.py` to reflect hardware changes.

## Conventions

-   **KISS Principle:** Keep implementations simple and maintainable.
-   **Package Scripts:** Each package should contain a `pre.sh` (host-side) and `qemu.sh` (target-side).
-   **Consistency:** Ensure `base.bit`, `base.hwh`, and `base.py` are always synchronized.
