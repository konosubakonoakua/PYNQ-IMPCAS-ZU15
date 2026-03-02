#!/bin/bash

set -e
# set -x

. /etc/environment
for f in /etc/profile.d/*.sh; do source $f; done

export HOME=/home/xilinx


# Load common lib
LIB=/tmp/stage4/helper.sh
[[ -f "$LIB" ]] || { echo "Missing $LIB"; exit 1; }
source "$LIB"

log "[vcpkg] begin installation"

VCPKG_DIR="/opt/vcpkg"
VCPKG_REPO="https://github.com/microsoft/vcpkg.git"

# ---------------------------------------------------------
# Remove old installation (optional but safer)
# ---------------------------------------------------------
if [[ -d "$VCPKG_DIR" ]]; then
    log "[vcpkg] removing previous installation"
    rm -rf "$VCPKG_DIR"
fi

mkdir -p "$VCPKG_DIR"

# ---------------------------------------------------------
# Clone vcpkg repository
# ---------------------------------------------------------
git_clone_with_retry "$VCPKG_REPO" --dir "$VCPKG_DIR" --retries 3

# ---------------------------------------------------------
# bootstrap vcpkg
# ---------------------------------------------------------
log "[vcpkg] bootstrapping"

(
    cd "$VCPKG_DIR"
    ./bootstrap-vcpkg.sh
)

# ---------------------------------------------------------
# Optional: Setup default triplet for aarch64-linux
# ---------------------------------------------------------
log "[vcpkg] creating default aarch64 triplet"

cat > "$VCPKG_DIR/triplets/community/arm64-linux.cmake" <<'EOF'
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
EOF

# ---------------------------------------------------------
# Add environment script (bashrc)
# ---------------------------------------------------------
PROFILED="/etc/profile.d/vcpkg.sh"

cat > "$PROFILED" <<EOF
export VCPKG_ROOT="$VCPKG_DIR"
export PATH="\$VCPKG_ROOT:\$PATH"
EOF

chmod 644 "$PROFILED"

# ---------------------------------------------------------
# Fix permissions
# ---------------------------------------------------------
chown -R "xilinx:xilinx" "$VCPKG_DIR"

log "[vcpkg] installation complete"
