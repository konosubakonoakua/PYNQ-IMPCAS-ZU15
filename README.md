## Build PYNQ SD Image for Pynq-IMPCAS-ZU15

* [codeberg.org/RafaelRen/PYNQ-IMPCAS-ZU15](https://codeberg.org/RafaelRen/PYNQ-IMPCAS-ZU15) (mirror)
* [github.com/konosubakonoakua/PYNQ-IMPCAS-ZU15](https://github.com/konosubakonoakua/PYNQ-IMPCAS-ZU15) (latest)
* [gitee.com/impcas_beam_diagnosis/PYNQ-IMPCAS-ZU15](https://gitee.com/impcas_beam_diagnosis/PYNQ-IMPCAS-ZU15) (no LFS support)

### Prerequisites

```
* Open https://petalinux.xilinx.com/ in a web browser. this makes sure we have a good connection to the yocto downloads.
* Set "Defaults:username timestamp_timeout=120" in the sudoers file for a 120-minute password-free session.
```

**Required tools:**

* Ubuntu 22.04 LTS 64-bit host PC
* Passwordless SUDO privilege for the building user
* Roughly 35GB of free space (build process only, not accounting for Xilinx tools)
* At least 8GB of RAM (more is better)
* AMD PetaLinux 2024.1 and Vivado 2024.1

You can find the instructions to setup the environment here [https://pynq.readthedocs.io/en/latest/pynq_sd_card.html#prepare-the-building-environment](https://pynq.readthedocs.io/en/latest/pynq_sd_card.html#prepare-the-building-environment)

Retrieve the `Pynq-IMPCAS-ZU15` board git into a NEW directory.

```shell
git clone https://github.com/konosubakonoakua/PYNQ-IMPCAS-ZU15.git <LOCAL_PYNQ-IMPCAS-ZU15_REPO>
cd <LOCAL_PYNQ-IMPCAS-ZU15_REPO> && git submodule init && git submodule update
```

---

### Git Proxy Patch (pynq_proxy.patch)

For users in **network-restricted regions** (e.g. GitHub access via HTTP/HTTPS proxy), this repository provides a patch:

```
patches/pynq_proxy.patch
```

**Purpose**

This patch is applied to the **official PYNQ repository (submodule)** and mainly:

* Adds support for **Git HTTP/HTTPS proxy configuration** during the PYNQ build process
* Ensures submodules such as `Xilinx/embeddedsw` can be cloned successfully when direct access to GitHub is blocked
* Avoids manual intervention during `make all` when `git clone` is invoked by PYNQ build scripts

**When you need it**

You likely need this patch if:

* `make checkenv` or `make all` fails while cloning `Xilinx/embeddedsw`
* `git ls-remote https://github.com/Xilinx/embeddedsw.git` times out or fails
* You must rely on an HTTP/HTTPS proxy to access GitHub

**How to apply manually (if not auto-applied)**

From the repository root directory:

```bash
cd pynq
patch -p1 < ../patches/pynq_proxy.patch
```

After applying the patch, continue with the normal build steps.

> Note: If you already configured a global Git proxy (`git config --global http.proxy ...`), this patch may not be strictly required, but it provides a more robust and reproducible solution for automated builds.

---

### Build SD Image

PYNQ is a submodule and it points to the corresponding branch.

Configure and install build tools, this will take some effort and will be an iterative process. Install on your own any missing tools.

Inside the `<LOCAL_PYNQ-IMPCAS-ZU15_REPO>/` execute

```shell
source /tools/Xilinx/Vivado/2024.1/settings64.sh
source /tools/Petalinux/2024.1/settings.sh
cd pynq/sdbuild
make checkenv
```

If you are in a github restricted region, try the following command first to test connectivity.

```bash
git ls-remote https://github.com/Xilinx/embeddedsw.git | grep master
```

If you have a working proxy, set proxy environment variables in `qemu/pre.sh`:

```bash
export http_proxy=http://192.168.138.254:7897
export https_proxy=http://192.168.138.254:7897
```

Or, pass it to makefile:
```bash
PYNQ_PROXY_URL="http://192.168.138.254:7897" make ...
```

If you still encounter git proxy issue when cloning `Xilinx/embeddedsw`, you can clone it manually:

```bash
export http_proxy=http://192.168.138.254:7897
export https_proxy=http://192.168.138.254:7897
cd pynq/sdbuild/build/PYNQ && git submodule init && git submodule update
```

Or, use git global configuration instead of exporting HTTP PROXY:

```bash
git config --global http.proxy "http://192.168.138.254:7897"
git config --global https.proxy "http://192.168.138.254:7897"
```

In the root directory (`<LOCAL_PYNQ-IMPCAS-ZU15_REPO>/`) run `make`.

```shell
taskset -c 0,1,2,3 make all 2>&1 | tee "pynq_build_$(date +%Y%m%d_%H%M%S).log"
```

Once the build has completed, if successful a SD card image will be available under the directory `<LOCAL_PYNQ-IMPCAS-ZU15_REPO>/sdbuild/output/Pynq-IMPCAS-ZU15-3.1.2.img`.

Use Etcher or Win32DiskImager or Rufus to write this image to an SD card.

---

## Create new designs for PYNQ

All we need finally is a **XSA** file.

### PS presets

After adding the Processing System (PS) to the block design, the `base/ps.tcl`script should be applied. This script handles fundamental configurations such as **DDR**, **clock**, **SD-CARD**, **UART**, and **Ethernet**. You should definitely NOT to modify them.

### Custom Device Tree Overlay

* [https://discuss.pynq.io/t/device-tree-overlay-example/543](https://discuss.pynq.io/t/device-tree-overlay-example/543)
* [https://github.com/konosubakonoakua/PYNQ-PRIO](https://github.com/konosubakonoakua/PYNQ-PRIO)

## Trouble shooting

### Stuck at `Starting kernel ...` after boot

A clean build is the life saver, IDKY.

```bash
sudo make clean
taskset -c 0,1,2,3 make all 2>&1 | tee "pynq_build_$(date +%Y%m%d_%H%M%S).log"
```

Or try to delete petalinux artifacts before rebuild:

```bash
rm -rf pynq/sdbuild/build/Pynq-IMPCAS-ZU15
```
