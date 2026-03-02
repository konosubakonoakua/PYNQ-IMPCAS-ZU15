#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Colorized logging
# ============================================================
if [[ -t 1 ]]; then
  C_RESET="\033[0m"
  C_RED="\033[31m"
  C_GREEN="\033[32m"
  C_YELLOW="\033[33m"
  C_BLUE="\033[34m"
else
  C_RESET="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
fi

log_info()  { echo -e "${C_BLUE}[*]${C_RESET} $*"; }
log_ok()    { echo -e "${C_GREEN}[+]${C_RESET} $*"; }
log_warn()  { echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
log_err()   { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; }

# ============================================================
# Help
# ============================================================
print_help() {
  cat <<'EOF'
Usage:
  imgshell.sh [options] <image> <selector>

Description:
  Mount a partition from a disk image and allow free modification.
  Supports optional chroot with automatic architecture handling.

Options:
  -h, --help, help   Show this help and exit
  --dry-run          Only resolve the target partition, do not mount
  --no-shell         Mount and wait (Ctrl+C) instead of opening a shell
  --ro               Mount read-only (safe mode)
  --chroot           Enter chroot (ONLY valid with selector=root)
  --backup           Always create a backup before writable mount

Selector:
  boot               First FAT/vfat partition
  root               First ext* partition
  pN                 Partition number (e.g. p1, p2)
  label=LABEL        Filesystem label
  uuid=UUID          Filesystem UUID

Examples:
  sudo imgshell.sh pynq.img boot
  sudo imgshell.sh pynq.img root
  sudo imgshell.sh --backup pynq.img root
  sudo imgshell.sh --chroot pynq.img root
  sudo imgshell.sh --ro pynq.img root
  sudo imgshell.sh --dry-run pynq.qcow2 root

Notes:
  - Never modify an image while it is used by a running VM.
  - Backup is strongly recommended before writable mount.
EOF
}

# ============================================================
# Argument parsing
# ============================================================
DRY_RUN=0
NO_SHELL=0
MOUNT_RO=0
USE_CHROOT=0
FORCE_BACKUP=0
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help|help) print_help; exit 0 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --no-shell) NO_SHELL=1; shift ;;
    --ro)       MOUNT_RO=1; shift ;;
    --chroot)   USE_CHROOT=1; shift ;;
    --backup)   FORCE_BACKUP=1; shift ;;
    --) shift; ARGS+=("$@"); break ;;
    -*)
      log_err "Unknown option: $1"
      log_err "Run with -h for help."
      exit 1
      ;;
    *)
      ARGS+=("$1"); shift ;;
  esac
done

if [[ "${#ARGS[@]}" -lt 2 ]]; then
  log_err "Missing required arguments."
  echo
  print_help
  exit 1
fi

IMG="${ARGS[0]}"
SEL="${ARGS[1]}"

[[ -f "$IMG" ]] || { log_err "Image not found: $IMG"; exit 1; }

if [[ "$USE_CHROOT" -eq 1 && "$SEL" != "root" ]]; then
  log_err "--chroot is only valid with selector=root"
  exit 1
fi

# ============================================================
# Backup logic (BEFORE any mount)
# ============================================================
do_backup() {
  local ts backup
  ts="$(date +%Y%m%d_%H%M%S)"
  backup="${IMG}.bak.${ts}"
  log_warn "Creating backup: $backup"
  cp --reflink=auto "$IMG" "$backup"
  log_ok "Backup created"
}

if [[ "$DRY_RUN" -eq 0 && "$MOUNT_RO" -eq 0 ]]; then
  if [[ "$FORCE_BACKUP" -eq 1 ]]; then
    do_backup
  elif [[ -t 0 ]]; then
    read -rp "Create a backup before modifying the image? [y/N] " ans
    case "$ans" in
      y|Y|yes|YES) do_backup ;;
      *) log_warn "Proceeding without backup" ;;
    esac
  fi
fi

# ============================================================
# Dependencies
# ============================================================
need_cmd() { command -v "$1" >/dev/null 2>&1; }

for c in kpartx losetup blkid mount umount lsblk fuser file; do
  need_cmd "$c" || { log_err "Missing command: $c"; exit 1; }
done

# ============================================================
# Workspace & cleanup
# ============================================================
WORKDIR="$(mktemp -d)"
MNT="$WORKDIR/mnt"
mkdir -p "$MNT"

MAPDEV="" LOOPDEV="" NBDDEV=""

cleanup() {
  set +e
  cd / >/dev/null 2>&1 || true

  if mountpoint -q "$MNT"; then
    log_info "Unmounting $MNT"
    umount "$MNT" 2>/dev/null || {
      log_warn "Unmount failed: target is busy"
      fuser -vm "$MNT" || true
    }
  fi

  [[ -n "$MAPDEV"  ]] && kpartx -d "$MAPDEV"  >/dev/null 2>&1 || true
  [[ -n "$LOOPDEV" ]] && losetup -d "$LOOPDEV" >/dev/null 2>&1 || true
  [[ -n "$NBDDEV"  ]] && qemu-nbd -d "$NBDDEV" >/dev/null 2>&1 || true

  rm -rf "$WORKDIR"
}
trap cleanup EXIT

log_info "Image: $IMG"
log_info "Selector: $SEL"
log_info "Options: dry_run=$DRY_RUN no_shell=$NO_SHELL ro=$MOUNT_RO chroot=$USE_CHROOT backup=$FORCE_BACKUP"

# ============================================================
# Map image to block device
# ============================================================
EXT="${IMG##*.}"

if [[ "$EXT" == "qcow2" ]]; then
  need_cmd qemu-nbd || { log_err "qemu-nbd not found (install qemu-utils)"; exit 1; }
  modprobe nbd max_part=16

  for d in /dev/nbd{0..15}; do
    if ! fuser "$d" >/dev/null 2>&1; then
      NBDDEV="$d"
      break
    fi
  done
  [[ -z "$NBDDEV" ]] && { log_err "No free /dev/nbdX"; exit 1; }

  log_info "Attaching qcow2 -> $NBDDEV"
  qemu-nbd -c "$NBDDEV" "$IMG"
  MAPDEV="$NBDDEV"
else
  log_info "Attaching image via loop device"
  LOOPDEV="$(losetup --find --show -P "$IMG")"
  MAPDEV="$LOOPDEV"
fi

# ============================================================
# Create partition mappings
# ============================================================
log_info "Creating partition mappings"
kpartx -a "$MAPDEV" >/dev/null

BASE="$(basename "$MAPDEV")"
PARTS=()
for i in {1..16}; do
  p="/dev/mapper/${BASE}p${i}"
  [[ -e "$p" ]] && PARTS+=("$p")
done

[[ "${#PARTS[@]}" -gt 0 ]] || { log_err "No partitions found"; exit 1; }
lsblk -f "$MAPDEV"

# ============================================================
# Select target partition
# ============================================================
TARGET_PART=""

select_boot() { for p in "${PARTS[@]}"; do [[ "$(blkid -o value -s TYPE "$p")" =~ ^(vfat|fat) ]] && TARGET_PART="$p" && return; done; }
select_root() { for p in "${PARTS[@]}"; do [[ "$(blkid -o value -s TYPE "$p")" =~ ^ext ]] && TARGET_PART="$p" && return; done; }

case "$SEL" in
  boot) select_boot ;;
  root) select_root ;;
  p[0-9]*) [[ -e "/dev/mapper/${BASE}${SEL}" ]] && TARGET_PART="/dev/mapper/${BASE}${SEL}" ;;
  label=*) for p in "${PARTS[@]}"; do [[ "$(blkid -o value -s LABEL "$p")" == "${SEL#label=}" ]] && TARGET_PART="$p" && break; done ;;
  uuid=*)  for p in "${PARTS[@]}"; do [[ "$(blkid -o value -s UUID  "$p")" == "${SEL#uuid=}"  ]] && TARGET_PART="$p" && break; done ;;
  *) log_err "Unknown selector: $SEL"; exit 1 ;;
esac

[[ -n "$TARGET_PART" ]] || { log_err "Failed to resolve selector"; exit 1; }
log_ok "Selected partition: $TARGET_PART"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log_ok "Dry-run mode, exiting."
  exit 0
fi

# ============================================================
# Mount
# ============================================================
MOUNT_OPTS=""
[[ "$MOUNT_RO" -eq 1 ]] && MOUNT_OPTS="-o ro"

log_info "Mounting $TARGET_PART -> $MNT"
mount $MOUNT_OPTS "$TARGET_PART" "$MNT"

# ============================================================
# Shell / chroot
# ============================================================
if [[ "$USE_CHROOT" -eq 1 ]]; then
  log_info "Preparing chroot environment"

  # Detect guest architecture
  GUEST_ARCH="$(file -b "$MNT/bin/bash" | awk '{print $1,$2,$3,$4}')"
  log_info "Guest /bin/bash: $GUEST_ARCH"

  # Bind mounts
  mount --bind /dev       "$MNT/dev"
  mount --bind /dev/pts  "$MNT/dev/pts"
  mount -t proc /proc    "$MNT/proc"
  mount -t sysfs /sys    "$MNT/sys"
  mount --bind /run      "$MNT/run" 2>/dev/null || true

  log_info "Entering chroot (exit to leave)"
  chroot "$MNT" /bin/bash

elif [[ "$NO_SHELL" -eq 1 ]]; then
  log_info "Mounted. Press Ctrl+C to exit."
  while true; do sleep 1; done
else
  log_info "Entering interactive shell at $MNT"
  log_info "Exit shell to sync & cleanup."
  (
    cd "$MNT"
    export HOME="$MNT"
    export PS1="(IMG:${SEL}) \\w # "
    alias ll='ls -alF'
    exec bash --noprofile --norc
  )
fi

# ============================================================
# Finalize
# ============================================================
cd /
[[ "$MOUNT_RO" -eq 0 ]] && { log_info "Syncing changes"; sync; }
log_ok "Done"
