#!/usr/bin/env bash
set -e
# set -x

# Resolve script directory (so .verify.env is found no matter where you run the script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load optional env file (does not override already-exported env vars)
if [[ -f "$SCRIPT_DIR/.pkgverify.env" ]]; then
	set -a
	# shellcheck disable=SC1090
	source "$SCRIPT_DIR/.pkgverify.env"
	set +a
fi

###############################################################################
# pkgverify.sh
#
# Verify packages under <your_board>/packages/
#
# Package script convention (PYNQ sdbuild style):
#   pre.sh  : host side, BEFORE chroot, expects target rootfs as $1
#   qemu.sh : inside rootfs (aarch64) via qemu-aarch64-static + chroot
#   post.sh : host side, AFTER chroot, expects target rootfs as $1
#
# Host: Ubuntu 22
# Target rootfs: Ubuntu 22 aarch64
#
# Features:
#   --mode clean|reuse
#   --reset-rootfs (reuse mode)
#   --pkgs supports "space-separated" or "comma-separated"
#   Inject PYNQ env vars into both host scripts and chroot scripts
#   Construct /etc/resolv.conf in rootfs with DNS 114.114.114.114
#
# Interactive debugging:
#   --enter-on-fail[=any|pre|qemu|post]  Enter interactive chroot on failure
#   --enter-chroot                       Prepare rootfs and enter chroot directly
#   --continue-on-fail                   Continue running remaining packages after failure
###############################################################################

# ------------------- PYNQ-like env defaults -------------------
: "${PYNQ_BOARD:=Pynq-IMPCAS-ZU15}"
: "${PYNQ_JUPYTER_NOTEBOOKS:=/home/xilinx/jupyter_notebooks}"
: "${PYNQ_PYTHON:=python3.10}"
: "${PYNQ_VERSION:=3.1.2}"
: "${PYNQ_PROXY_URL:=}"

: "${DEFAULT_PACKAGES_DIR:=../${PYNQ_BOARD}/packages}"
: "${DEFAULT_ROOTFS_TAR:=../pynq/sdbuild/prebuilt/pynq_rootfs.aarch64.tar.gz}"

# Only set PACKAGES_DIR/ROOTFS_TAR from defaults if not already set (and can be overridden by CLI)
PACKAGES_DIR="${PACKAGES_DIR:-$DEFAULT_PACKAGES_DIR}"
ROOTFS_TAR="${ROOTFS_TAR:-$DEFAULT_ROOTFS_TAR}"

# Mode control
MODE="clean" # clean | reuse
RESET_ROOTFS=0
NO_CLEANUP=0
KEEP_WORKDIR=0

# Work paths
WORKDIR=""
ROOTFS_DIR=""
RUN_ID=""
LOG_DIR=""
META_FILE=""

# UI actions
DO_LIST=0
DO_STATUS=0

# Packages to run
PKG_LIST=()

# In-rootfs build root
BUILD_ROOT_IN_ROOTFS="/build"

# ------------------- Interactive options -------------------
ENTER_CHROOT=0
ENTER_ON_FAIL=0
ENTER_ON_FAIL_STAGE="any" # any | pre | qemu | post
CONTINUE_ON_FAIL=0
FAIL_COUNT=0

# ------------------- Output helpers -------------------
red() { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
info() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
err() { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }
die() {
	err "$*"
	exit 1
}

usage() {
	cat <<EOF
Usage:
  $0 [options]

Core options:
  --packages-dir <dir>     Packages directory to verify
                           default: ${DEFAULT_PACKAGES_DIR}

  --rootfs-tar <path>      Rootfs tar.gz path (aarch64 Ubuntu22)
                           default: ${DEFAULT_ROOTFS_TAR}

  --pkgs <...>             Only verify selected packages
                           Supports:
                             --pkgs p1 p2 p3
                             --pkgs p1,p2,p3
                           Default: verify all packages in packages-dir

Mode options:
  --mode <clean|reuse>     clean: fresh rootfs each run (default)
                           reuse: reuse rootfs under --workdir (fast, stateful)

  --reset-rootfs           In reuse mode, wipe+re-extract rootfs from --rootfs-tar
                           Keeps workdir/logs but rootfs becomes clean.

  --workdir <dir>          Work directory
                           - clean mode: optional
                           - reuse mode: REQUIRED

  --keep-workdir           Do not delete workdir at end (clean mode only)
  --no-cleanup             Do not remove /tmp/pkg_verify copied files in rootfs

PYNQ env injection:
  --board <name>           PYNQ_BOARD (default: ${PYNQ_BOARD})
  --python <bin>           PYNQ_PYTHON (default: ${PYNQ_PYTHON})
  --jupyter <path>         PYNQ_JUPYTER_NOTEBOOKS (default: ${PYNQ_JUPYTER_NOTEBOOKS})
  --pynq-version <ver>     PYNQ_VERSION (default: ${PYNQ_VERSION})
  --proxy <url>            PYNQ_PROXY_URL (default: empty)

Interactive debugging:
  --enter-chroot           Prepare rootfs and enter interactive aarch64 chroot shell; do not run packages
  --enter-on-fail[=stage]  Enter interactive chroot shell when a step fails.
                           stage: any | pre | qemu | post (default: any)
  --continue-on-fail       Do not stop at first failure; continue remaining packages.
                           (Still returns non-zero if any failure occurred.)

Utility:
  --list                   List all packages and exit
  --status                 Show workdir/rootfs status and exit (requires --workdir)

  -h, --help               Show help

Examples:
  # Clean verify all packages (fresh rootfs each time)
  $0

  # Reuse workdir but reset rootfs to clean state (keeps logs)
  $0 --mode reuse --workdir /tmp/pynq_verify --reset-rootfs --pkgs helper apt

  # Enter chroot directly
  $0 --mode reuse --workdir /tmp/pynq_verify --reset-rootfs --enter-chroot

  # Enter chroot only when qemu.sh fails
  $0 --mode reuse --workdir /tmp/pynq_verify --reset-rootfs --enter-on-fail=qemu --pkgs pwndbg
EOF
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		err "Missing required command: $1"
		exit 1
	}
}

check_prereqs() {
	need_cmd tar
	need_cmd rsync
	need_cmd sudo
	need_cmd find
	need_cmd sed
	need_cmd awk
	need_cmd tee

	if ! command -v qemu-aarch64-static >/dev/null 2>&1; then
		err "qemu-aarch64-static not found. Install:"
		echo "  sudo apt-get update && sudo apt-get install -y qemu-user-static"
		exit 1
	fi

	if [[ ! -d "$PACKAGES_DIR" ]]; then
		err "Packages dir not found: $PACKAGES_DIR"
		exit 1
	fi

	if [[ ! -f "$ROOTFS_TAR" ]]; then
		err "Rootfs tar not found: $ROOTFS_TAR"
		exit 1
	fi

	if [[ "$MODE" != "clean" && "$MODE" != "reuse" ]]; then
		err "--mode must be clean or reuse"
		exit 1
	fi

	if [[ "$MODE" == "reuse" && -z "$WORKDIR" && "$DO_LIST" -eq 0 && "$DO_STATUS" -eq 0 ]]; then
		err "In reuse mode, --workdir is REQUIRED."
		exit 1
	fi

	if [[ "$DO_STATUS" -eq 1 && -z "$WORKDIR" ]]; then
		err "--status requires --workdir"
		exit 1
	fi

	if [[ "$ENTER_ON_FAIL" -eq 1 ]]; then
		case "$ENTER_ON_FAIL_STAGE" in
		any | pre | qemu | post) ;;
		*)
			err "--enter-on-fail stage must be: any|pre|qemu|post"
			exit 1
			;;
		esac
	fi
}

discover_packages() {
	if [[ "${#PKG_LIST[@]}" -gt 0 ]]; then
		return
	fi
	mapfile -t PKG_LIST < <(find "$PACKAGES_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort)
	if [[ "${#PKG_LIST[@]}" -eq 0 ]]; then
		err "No packages found under: $PACKAGES_DIR"
		exit 1
	fi
}

list_packages() {
	discover_packages
	echo "Packages under $PACKAGES_DIR:"
	for p in "${PKG_LIST[@]}"; do
		echo "  - $p"
	done
}

init_paths_from_workdir() {
	ROOTFS_DIR="$WORKDIR/rootfs"
	META_FILE="$WORKDIR/.rootfs_meta"
	RUN_ID="$(date +%Y%m%d_%H%M%S)"
	LOG_DIR="$WORKDIR/logs/$RUN_ID"
	mkdir -p "$ROOTFS_DIR" "$LOG_DIR"
}

make_workdir() {
	if [[ "$MODE" == "clean" ]]; then
		if [[ -z "$WORKDIR" ]]; then
			WORKDIR="/tmp/pynq_pkg_verify_$(date +%Y%m%d_%H%M%S)"
		fi
	fi

	mkdir -p "$WORKDIR"
	init_paths_from_workdir

	info "Mode   : $MODE"
	info "Workdir: $WORKDIR"
	info "Rootfs : $ROOTFS_DIR"
	info "Logs   : $LOG_DIR"
	info "PYNQ_BOARD=$PYNQ_BOARD, PYNQ_PYTHON=$PYNQ_PYTHON, NOTEBOOKS=$PYNQ_JUPYTER_NOTEBOOKS"
}

write_meta() {
	sudo bash -lc "cat > '$META_FILE' <<EOF
rootfs_tar=$ROOTFS_TAR
extracted_at=$(date -Is)
mode=$MODE
pynq_board=$PYNQ_BOARD
pynq_python=$PYNQ_PYTHON
pynq_jupyter_notebooks=$PYNQ_JUPYTER_NOTEBOOKS
pynq_version=$PYNQ_VERSION
pynq_proxy_url=$PYNQ_PROXY_URL
EOF"
}

show_status() {
	echo "Workdir: $WORKDIR"
	echo "Rootfs : $WORKDIR/rootfs"
	if [[ -f "$WORKDIR/.rootfs_meta" ]]; then
		echo "------ meta ------"
		cat "$WORKDIR/.rootfs_meta"
		echo "------------------"
	else
		echo "Meta: (none)"
	fi
	if [[ -d "$WORKDIR/rootfs" ]]; then
		local count
		count="$(sudo ls -1A "$WORKDIR/rootfs" 2>/dev/null | wc -l | tr -d ' ')"
		echo "Rootfs entries: $count"
	else
		echo "Rootfs missing"
	fi
	if [[ -d "$WORKDIR/logs" ]]; then
		echo "Recent runs:"
		ls -1 "$WORKDIR/logs" 2>/dev/null | tail -n 8 || true
	fi
}

teardown_chroot_env() {
	local m

	info "Tearing down chroot mounts..."

	# Unmount in correct order (child before parent)
	for m in dev/pts dev proc sys; do
		local mp="$ROOTFS_DIR/$m"

		if sudo mountpoint -q "$mp"; then
			info "umount -lf $mp"
			if ! sudo umount -lf "$mp"; then
				warn "Failed to umount $mp (ignored)"
			fi
		else
			info "not mounted: $mp"
		fi
	done

	if [[ "$NO_CLEANUP" -eq 0 ]]; then
		if [[ -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static" ]]; then
			info "Removing $ROOTFS_DIR/usr/bin/qemu-aarch64-static"
			sudo rm -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static" || true
		fi
	fi
}

wipe_rootfs_dir() {
	info "Wiping existing rootfs directory: $ROOTFS_DIR"
	teardown_chroot_env || true
	sudo rm -rf "$ROOTFS_DIR"
	sudo mkdir -p "$ROOTFS_DIR"
}

extract_rootfs() {
	info "Extracting rootfs tar: $ROOTFS_TAR"
	sudo tar -xpf "$ROOTFS_TAR" -C "$ROOTFS_DIR"

	# flatten if tarball contains a single top-level root directory
	local top_entries
	top_entries="$(sudo ls -1A "$ROOTFS_DIR" | wc -l | tr -d ' ')"
	if [[ "$top_entries" -eq 1 ]]; then
		local only
		only="$(sudo ls -1A "$ROOTFS_DIR")"
		if [[ -d "$ROOTFS_DIR/$only" ]]; then
			if sudo test -d "$ROOTFS_DIR/$only/etc" && sudo test -d "$ROOTFS_DIR/$only/usr"; then
				info "Rootfs tar contains a top-level dir ($only). Flattening..."
				sudo rsync -a "$ROOTFS_DIR/$only/" "$ROOTFS_DIR/"
				sudo rm -rf "$ROOTFS_DIR/$only"
			fi
		fi
	fi

	write_meta
}

ensure_rootfs_present() {
	if [[ "$MODE" == "clean" ]]; then
		wipe_rootfs_dir
		extract_rootfs
		return
	fi

	local need_extract=0
	if [[ ! -d "$ROOTFS_DIR" ]]; then
		need_extract=1
	else
		local count
		count="$(sudo ls -1A "$ROOTFS_DIR" 2>/dev/null | wc -l | tr -d ' ')"
		[[ "$count" -eq 0 ]] && need_extract=1
	fi

	[[ "$RESET_ROOTFS" -eq 1 ]] && need_extract=1

	if [[ "$need_extract" -eq 1 ]]; then
		info "Rootfs not present/empty or --reset-rootfs set; extracting..."
		wipe_rootfs_dir
		extract_rootfs
	else
		warn "Reusing existing rootfs (stateful). Previous runs may affect results."
		[[ -f "$META_FILE" ]] && sed 's/^/[META] /' "$META_FILE" || true
	fi
}

setup_chroot_env() {
	info "Setting up chroot env (qemu, resolv.conf, mounts)..."

	sudo install -m 0755 "$(command -v qemu-aarch64-static)" "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"

	# DNS: construct resolv.conf with 114.114.114.114 and remove dangling symlink
	sudo mkdir -p "$ROOTFS_DIR/etc"
	sudo rm -f "$ROOTFS_DIR/etc/resolv.conf"
	sudo tee "$ROOTFS_DIR/etc/resolv.conf" >/dev/null <<'EOF'
nameserver 114.114.114.114
options timeout:2 attempts:3 rotate
EOF

	sudo mount --bind /dev "$ROOTFS_DIR/dev"
	sudo mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
	sudo mount --bind /proc "$ROOTFS_DIR/proc"
	sudo mount --bind /sys "$ROOTFS_DIR/sys"
}

enter_interactive_chroot() {
	local reason="${1:-unknown}"
	local pkg="${2:-unknown}"
	local stage="${3:-unknown}"

	echo
	yellow "==================== ENTER CHROOT ===================="
	echo "[FAIL] reason: $reason"
	echo "[FAIL] pkg   : $pkg"
	echo "[FAIL] stage : $stage"
	echo "[INFO] rootfs: $ROOTFS_DIR"
	echo "[INFO] logs : $LOG_DIR"
	echo "[INFO] hints:"
	echo "  - pkg scripts copied at: /tmp/pkg_verify/<pkg>"
	echo "  - helper staging maybe: /tmp/stage4"
	echo "  - check dns: cat /etc/resolv.conf"
	echo "  - check env: env | grep -E 'PYNQ_|BUILD_ROOT|DEBIAN_FRONTEND'"
	echo "[INFO] Exit shell to return to host..."
	yellow "======================================================"
	echo

	# Ensure mounts exist (ignore errors if already mounted)
	sudo mountpoint -q "$ROOTFS_DIR/dev" || sudo mount --bind /dev "$ROOTFS_DIR/dev" || true
	sudo mountpoint -q "$ROOTFS_DIR/dev/pts" || sudo mount --bind /dev/pts "$ROOTFS_DIR/dev/pts" || true
	sudo mountpoint -q "$ROOTFS_DIR/proc" || sudo mount --bind /proc "$ROOTFS_DIR/proc" || true
	sudo mountpoint -q "$ROOTFS_DIR/sys" || sudo mount --bind /sys "$ROOTFS_DIR/sys" || true

	# Ensure qemu exists
	if [[ ! -x "$ROOTFS_DIR/usr/bin/qemu-aarch64-static" ]]; then
		sudo install -m 0755 "$(command -v qemu-aarch64-static)" "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"
	fi

	# Enter interactive shell
	sudo chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64-static /bin/bash -l
}

should_enter_on_fail() {
	local stage="$1" # pre|qemu|post
	if [[ "$ENTER_ON_FAIL" -ne 1 ]]; then
		return 1
	fi
	if [[ "$ENTER_ON_FAIL_STAGE" == "any" ]]; then
		return 0
	fi
	[[ "$ENTER_ON_FAIL_STAGE" == "$stage" ]]
}

handle_failure() {
	local rc="$1"
	local pkg="$2"
	local stage="$3"
	local log="$4"

	FAIL_COUNT=$((FAIL_COUNT + 1))

	err "[$pkg] FAILED stage=$stage rc=$rc"
	err "[$pkg] Log: $log"

	if should_enter_on_fail "$stage"; then
		enter_interactive_chroot "step-failed" "$pkg" "$stage"
	fi

	if [[ "$CONTINUE_ON_FAIL" -eq 1 ]]; then
		warn "[$pkg] continue-on-fail enabled; continuing..."
		return 0
	fi

	return "$rc"
}

# Host-side scripts: pass ROOTFS_DIR as $1 (target) and inject env vars
run_host_script() {
	local pkg="$1"
	local script="$2" # pre.sh or post.sh
	local stage="$3"  # pre or post
	local pkg_dir="$PACKAGES_DIR/$pkg"
	local log="$LOG_DIR/${pkg}_${script}.log"

	[[ -f "$pkg_dir/$script" ]] || return 0

	info "[$pkg] Running host script: $script"
	(
		set -euo pipefail
		cd "$pkg_dir"

		# Provide both env vars and the positional $1 target path (PYNQ convention)
		export ROOTFS="$ROOTFS_DIR"
		export PYNQ_ROOTFS="$ROOTFS_DIR"
		export PYNQ_BOARD="$PYNQ_BOARD"
		export PYNQ_JUPYTER_NOTEBOOKS="$PYNQ_JUPYTER_NOTEBOOKS"
		export PYNQ_PYTHON="$PYNQ_PYTHON"
		export PYNQ_VERSION="$PYNQ_VERSION"
		export PYNQ_PROXY_URL="$PYNQ_PROXY_URL"

		# Many scripts may use BUILD_ROOT; keep it inside rootfs directory tree to avoid host pollution
		export BUILD_ROOT="$ROOTFS_DIR/build"

		export DEBIAN_FRONTEND=noninteractive
		export LANG=C.UTF-8
		export LC_ALL=C.UTF-8

		bash "./$script" "$ROOTFS_DIR"
	) 2>&1 | tee "$log"

	local rc="${PIPESTATUS[0]}"
	if [[ "$rc" -ne 0 ]]; then
		handle_failure "$rc" "$pkg" "$stage" "$log" || return "$rc"
	fi
	return 0
}

# Chroot scripts: copy pkg into /tmp/pkg_verify/<pkg> then run qemu.sh with injected env vars
run_chroot_script() {
	local pkg="$1"
	local script="qemu.sh"
	local stage="qemu"
	local pkg_dir="$PACKAGES_DIR/$pkg"
	local log="$LOG_DIR/${pkg}_${script}.log"

	[[ -f "$pkg_dir/$script" ]] || return 0

	info "[$pkg] Running chroot script: $script"

	local dst="/tmp/pkg_verify/$pkg"

	sudo mkdir -p "$ROOTFS_DIR/tmp/pkg_verify"
	sudo rm -rf "$ROOTFS_DIR/$dst" 2>/dev/null || true
	sudo rsync -a --delete "$pkg_dir/" "$ROOTFS_DIR/$dst/"
	sudo chmod +x "$ROOTFS_DIR/$dst/$script" || true

	# Inject PYNQ-like env vars into rootfs execution environment
	sudo chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64-static /bin/bash -lc \
		"set -euo pipefail
     export PYNQ_BOARD='$PYNQ_BOARD'
     export PYNQ_JUPYTER_NOTEBOOKS='$PYNQ_JUPYTER_NOTEBOOKS'
     export PYNQ_PYTHON='$PYNQ_PYTHON'
     export PYNQ_VERSION='$PYNQ_VERSION'
     export BUILD_ROOT='$BUILD_ROOT_IN_ROOTFS'
     export DEBIAN_FRONTEND=noninteractive
     export LANG=C.UTF-8
     export LC_ALL=C.UTF-8
     export HOME=/home/xilinx
     mkdir -p '$BUILD_ROOT_IN_ROOTFS'
     export PKG_NAME='$pkg'
     cd '$dst'
     bash './$script'" \
		2>&1 | tee "$log"

	local rc="${PIPESTATUS[0]}"
	if [[ "$rc" -ne 0 ]]; then
		handle_failure "$rc" "$pkg" "$stage" "$log" || return "$rc"
	fi

	if [[ "$NO_CLEANUP" -eq 0 ]]; then
		sudo rm -rf "$ROOTFS_DIR/$dst" 2>/dev/null || true
	fi

	return 0
}

verify_one_package() {
	local pkg="$1"
	local pkg_dir="$PACKAGES_DIR/$pkg"

	if [[ ! -d "$pkg_dir" ]]; then
		err "Package not found: $pkg_dir"
		return 2
	fi

	local has_any=0
	[[ -f "$pkg_dir/pre.sh" ]] && has_any=1
	[[ -f "$pkg_dir/qemu.sh" ]] && has_any=1
	[[ -f "$pkg_dir/post.sh" ]] && has_any=1

	if [[ "$has_any" -eq 0 ]]; then
		warn "[$pkg] No pre.sh/qemu.sh/post.sh found; skipping."
		return 0
	fi

	run_host_script "$pkg" "pre.sh" "pre" || return $?
	run_chroot_script "$pkg" || return $?
	run_host_script "$pkg" "post.sh" "post" || return $?

	return 0
}

summarize_results() {
	echo
	echo "==================== Summary ===================="
	echo "Mode     : $MODE"
	echo "Workdir  : $WORKDIR"
	echo "Rootfs   : $ROOTFS_DIR"
	echo "Logs     : $LOG_DIR"
	echo "Packages : ${PKG_LIST[*]}"
	echo "Failures : $FAIL_COUNT"
	echo "PYNQ_BOARD=$PYNQ_BOARD, PYNQ_PYTHON=$PYNQ_PYTHON"
	echo "================================================="
}

cleanup() {
	set +e
	teardown_chroot_env

	if [[ "$MODE" == "clean" ]]; then
		if [[ "$KEEP_WORKDIR" -eq 0 ]]; then
			info "Removing workdir: $WORKDIR"
			sudo rm -rf "$WORKDIR"
		else
			info "Keeping workdir: $WORKDIR"
		fi
	else
		info "Reuse mode: workdir kept: $WORKDIR"
	fi
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--packages-dir)
			PACKAGES_DIR="$2"
			shift 2
			;;
		--rootfs-tar)
			ROOTFS_TAR="$2"
			shift 2
			;;

		--mode)
			MODE="$2"
			shift 2
			;;
		--reset-rootfs)
			RESET_ROOTFS=1
			shift 1
			;;
		--workdir)
			WORKDIR="$2"
			shift 2
			;;
		--keep-workdir)
			KEEP_WORKDIR=1
			shift 1
			;;
		--no-cleanup)
			NO_CLEANUP=1
			shift 1
			;;

		--board)
			PYNQ_BOARD="$2"
			shift 2
			;;
		--python)
			PYNQ_PYTHON="$2"
			shift 2
			;;
		--jupyter)
			PYNQ_JUPYTER_NOTEBOOKS="$2"
			shift 2
			;;
		--pynq-version)
			PYNQ_VERSION="$2"
			shift 2
			;;
		--proxy)
			PYNQ_PROXY_URL="$2"
			shift 2
			;;

		--enter-chroot)
			ENTER_CHROOT=1
			shift 1
			;;
		--enter-on-fail)
			ENTER_ON_FAIL=1
			ENTER_ON_FAIL_STAGE="any"
			shift 1
			;;
		--enter-on-fail=*)
			ENTER_ON_FAIL=1
			ENTER_ON_FAIL_STAGE="${1#--enter-on-fail=}"
			shift 1
			;;
		--continue-on-fail)
			CONTINUE_ON_FAIL=1
			shift 1
			;;

		--list)
			DO_LIST=1
			shift 1
			;;
		--status)
			DO_STATUS=1
			shift 1
			;;

		--pkgs)
			shift 1
			while [[ $# -gt 0 && "$1" != --* ]]; do
				if [[ "$1" == *,* ]]; then
					IFS=',' read -r -a tmp <<<"$1"
					for t in "${tmp[@]}"; do
						[[ -n "$t" ]] && PKG_LIST+=("$t")
					done
				else
					PKG_LIST+=("$1")
				fi
				shift 1
			done
			;;

		-h | --help)
			usage
			exit 0
			;;
		*)
			err "Unknown option: $1"
			usage
			exit 1
			;;
		esac
	done
}

main() {
	parse_args "$@"

	if [[ "$DO_LIST" -eq 1 ]]; then
		if [[ ! -d "$PACKAGES_DIR" ]]; then
			err "Packages dir not found: $PACKAGES_DIR"
			exit 1
		fi
		discover_packages
		list_packages
		exit 0
	fi

	if [[ "$DO_STATUS" -eq 1 ]]; then
		show_status
		exit 0
	fi

	check_prereqs
	make_workdir
	trap cleanup EXIT

	ensure_rootfs_present
	setup_chroot_env

	if [[ "$ENTER_CHROOT" -eq 1 ]]; then
		enter_interactive_chroot "enter-chroot" "manual" "manual"
		exit 0
	fi

	if [[ "${#PKG_LIST[@]}" -eq 0 ]]; then
		discover_packages
	fi

	info "Starting verification (run_id=$RUN_ID)..."
	for pkg in "${PKG_LIST[@]}"; do
		echo
		yellow "==================== [$pkg] ===================="
		if ! verify_one_package "$pkg"; then
			# verify_one_package already handled interactive + counting
			# If continue-on-fail is disabled, it will return non-zero and we stop here
			if [[ "$CONTINUE_ON_FAIL" -eq 0 ]]; then
				err "Stopping due to failure."
				break
			fi
		fi
		green "==================== [$pkg] DONE ===================="
	done

	summarize_results

	if [[ "$FAIL_COUNT" -ne 0 ]]; then
		exit 1
	fi
	exit 0
}

main "$@"
