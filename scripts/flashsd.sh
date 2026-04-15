#!/bin/bash

# Default values
DRY_RUN=false
BS="4M"

# 1. Parse Options
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -n|--dry-run) DRY_RUN=true; shift ;;
        *) break ;;
    esac
done

# 2. Check arguments
if [ "$#" -lt 2 ]; then
    echo "Usage: sudo $0 [-n|--dry-run] <image_path> <device_node> [bs_size]"
    echo "Example: sudo $0 --dry-run ./pynq.img /dev/sdb"
    exit 1
fi

IMG=$1
DEV=$2
BS=${3:-$BS}

# 3. Basic Validation (Always performed)
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root (use sudo)."
   exit 1
fi

if [ ! -f "$IMG" ]; then
    echo "Error: Image file '$IMG' not found."
    exit 1
fi

if [ ! -b "$DEV" ]; then
    echo "Error: Device '$DEV' is not a valid block device."
    exit 1
fi

# 4. Dry Run Header
if [ "$DRY_RUN" = true ]; then
    echo "--- DRY RUN MODE: No data will be written ---"
fi

# 5. DANGER ZONE: User Confirmation
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "  WARNING: DANGEROUS OPERATION"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "Target Device: $DEV"
echo "Source Image:  $IMG"
echo "Block Size:    $BS"
echo "ALL DATA on $DEV will be PERMANENTLY ERASED."
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

if [ "$DRY_RUN" = false ]; then
    read -p "Are you absolutely sure you want to proceed? (type Y to continue): " confirm
    if [[ "$confirm" != "Y" && "$confirm" != "y" ]]; then
        echo "Operation aborted by user."
        exit 0
    fi
else
    echo "[DRY-RUN] Skipping user confirmation prompt."
fi

# 6. Execution / Simulation
execute() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Executing: $@"
    else
        "$@"
    fi
}

echo "--- Step 1: Force Unmounting $DEV* ---"
# We simulate the pipe manually for dry-run clarity
if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Executing: grep -ls '$DEV' /proc/mounts | xargs -r umount -l"
else
    grep -ls "$DEV" /proc/mounts | xargs -r umount -l
fi
execute sync

echo "--- Step 2: Wiping signatures on $DEV ---"
execute wipefs -a "$DEV"

echo "--- Step 3: Writing Image (dd) ---"
execute dd if="$IMG" of="$DEV" bs="$BS" status=progress conv=fsync

echo "--- Step 4: Final hardware synchronization ---"
execute sync

if [ "$DRY_RUN" = true ]; then
    echo "--- DRY RUN COMPLETE: No changes were made. ---"
else
    echo "--- SUCCESS: It is now safe to remove the SD card. ---"
fi
