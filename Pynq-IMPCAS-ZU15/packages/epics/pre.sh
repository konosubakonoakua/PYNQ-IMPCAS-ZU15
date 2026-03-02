#!/usr/bin/bash

set -e
# set -x

target=$1
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ---------------------------------------------------------
# EPICS prebuilt package definitions
# ---------------------------------------------------------
PREBUILT_DIR="${script_dir}/../../../pynq/sdbuild/prebuilt/"

mkdir -p "$PREBUILT_DIR"

EPICS_BASE_URL="https://github.com/konosubakonoakua/epics-prebuilt/releases/download/epics_base-7.0.9_synApps-R6-3/base-7.0.9_prebuilt_aarch64.tgz"
EPICS_BASE_TGZ="${PREBUILT_DIR}/base-7.0.9_prebuilt_aarch64.tgz"

EPICS_SYNAPPS_URL="https://github.com/konosubakonoakua/epics-prebuilt/releases/download/epics_base-7.0.9_synApps-R6-3/epics_synApps-R6-3_prebuilt_aarch64.tgz"
EPICS_SYNAPPS_TGZ="${PREBUILT_DIR}/epics_synApps-R6-3_prebuilt_aarch64.tgz"

EPICS_PYTHON_URL="https://github.com/konosubakonoakua/epics-prebuilt/releases/download/epics_base-7.0.9_synApps-R6-3/epics_python-3.12_venv_aarch64_full.tgz"
EPICS_PYTHON_TGZ="${PREBUILT_DIR}/epics_python-3.12_venv_aarch64_full.tgz"

# ---------------------------------------------------------
# Function: safe_download() with proxy + mktemp + retry
# ---------------------------------------------------------
safe_download() {
    local url="$1"
    local outfile="$2"

    if [[ -f "$outfile" ]]; then
        echo "[epics] Using cached: $outfile"
        return 0
    fi

    echo "[epics] Downloading $url ..."

    local tmpd
    tmpd="$(mktemp -d '/tmp/pynq.XXXXXX')"
    curl -fSL "$url" -o "${tmpd}/pkg.tgz"
    mv "${tmpd}/pkg.tgz" "$outfile"
    rm -rf "$tmpd"

    echo "[epics] Saved to $outfile"
}


# ---------------------------------------------------------
# Download (or use cache)
# ---------------------------------------------------------

safe_download "$EPICS_BASE_URL"    "$EPICS_BASE_TGZ"
safe_download "$EPICS_PYTHON_URL"  "$EPICS_PYTHON_TGZ"
safe_download "$EPICS_SYNAPPS_URL" "$EPICS_SYNAPPS_TGZ"

# ---------------------------------------------------------
# Install EPICS into rootfs: /opt/epics
# ---------------------------------------------------------
EPICS_ROOT="$target/opt/epics"

sudo mkdir -p "$EPICS_ROOT"

echo "[epics] Extracting EPICS packages to $EPICS_ROOT"

sudo tar -xf "$EPICS_BASE_TGZ"    -C "$EPICS_ROOT"
sudo tar -xf "$EPICS_SYNAPPS_TGZ" -C "$EPICS_ROOT"
sudo tar -xf "$EPICS_PYTHON_TGZ"  -C "$EPICS_ROOT"

echo "[epics] EPICS packages installation complete."

sudo cp $script_dir/epics.sh $target/etc/profile.d/epics.sh
sudo chmod 0644 $target/etc/profile.d/epics.sh

echo "[epics] EPICS env setup complete."

