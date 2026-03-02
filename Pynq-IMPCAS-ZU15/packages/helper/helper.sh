#!/bin/bash

set -e
# set -x

. /etc/environment
for f in /etc/profile.d/*.sh; do source $f; done

export HOME=/home/xilinx

# Common helpers for stage4 (root-only scripts)

# ---------------- logging ----------------
log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
err() { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }
die() {
	err "$*"
	exit 1
}

# ---------------- file helpers ----------------
append_once() {
	local line="$1"
	local file="$2"
	mkdir -p "$(dirname "$file")"
	touch "$file"
	grep -Fxq "$line" "$file" || echo "$line" >>"$file"
}

# ---------------- APT helpers ----------------
apt_update() {
	apt-get update
}

apt_install() {
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

# ---------------- git retry clone ----------------
git_clone_with_retry() {
	# Usage:
	#   git_clone_with_retry <repo_url> [options]
	#
	# Options:
	#   --dir <path>          Target directory. If omitted, git uses default name.
	#   --retries <N>         Retry count (default: 2). Total attempts = N + 1.
	#   --                  All remaining args are passed to `git clone` (optional).
	#
	# Anything else after options is treated as extra args for `git clone`.
	#
	# Examples:
	#   git_clone_with_retry https://github.com/xxx/yyy.git
	#   git_clone_with_retry https://github.com/xxx/yyy.git --dir /tmp/yyy
	#   git_clone_with_retry https://github.com/xxx/yyy.git --retries 3 -- --branch dev --single-branch
	#   git_clone_with_retry https://github.com/xxx/yyy.git --dir mydir -- --depth 10
	#
	# Behavior:
	# - Defaults to `--depth 1` unless caller provides --depth/--depth=<n> in clone args.
	# - Does not use positional parameters other than repo_url.

	local repo="${1:-}"
	[[ -n "$repo" ]] || die "git_clone_with_retry: missing <repo_url>"
	shift 1 || true

	local dir=""
	local retries=2
	local clone_args=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--dir)
			dir="${2:-}"
			[[ -n "$dir" ]] || die "git_clone_with_retry: --dir requires a value"
			shift 2
			;;
		--retries)
			retries="${2:-}"
			[[ "$retries" =~ ^[0-9]+$ ]] || die "git_clone_with_retry: --retries must be an integer"
			shift 2
			;;
		--)
			shift
			# Everything after -- goes directly to git clone
			while [[ $# -gt 0 ]]; do
				clone_args+=("$1")
				shift
			done
			;;
		*)
			# Treat as git clone extra args
			clone_args+=("$1")
			shift
			;;
		esac
	done

	local depth_arg_present=0
	for a in "${clone_args[@]}"; do
		case "$a" in
		--depth | --depth=*)
			depth_arg_present=1
			break
			;;
		esac
	done

	local attempt=1
	local max_attempts=$((retries + 1))

	while [[ $attempt -le $max_attempts ]]; do
		if [[ -n "$dir" ]]; then
			log "git clone (attempt $attempt/$max_attempts) $repo → $dir"
			rm -rf "$dir"
		else
			log "git clone (attempt $attempt/$max_attempts) $repo → (default dir)"
		fi

		if [[ "$depth_arg_present" -eq 1 ]]; then
			if [[ -n "$dir" ]]; then
				git clone "${clone_args[@]}" "$repo" "$dir" && return 0
			else
				git clone "${clone_args[@]}" "$repo" && return 0
			fi
		else
			if [[ -n "$dir" ]]; then
				git clone --depth 1 "${clone_args[@]}" "$repo" "$dir" && return 0
			else
				git clone --depth 1 "${clone_args[@]}" "$repo" && return 0
			fi
		fi

		sleep $((attempt * 5))
		attempt=$((attempt + 1))
	done

	die "git clone failed: $repo"
}

# ---- safe temp directory ----
mkdtemp() {
	mktemp -d "/tmp/pynq.XXXXXX"
}

gh_install_exec() {
	# Download a GitHub release asset (tar.* or zip) and install one OR multiple executables from it.
	# - Avoids GitHub API:
	#     - For "latest": follows the redirect on "releases/latest" to discover the version
	#     - For a fixed version: downloads from "releases/download/<tag>/<asset>" directly
	# - Supports assets with or without {ver} in filename.
	# - Supports per-bin target mapping via repeatable --map:
	#       --map "foo:/usr/local/bin/x" --map "bar:/opt/bin/y"
	#       --map "foo:/usr/local/bin"   --map "bar:/opt/bin"   (dir targets OK -> auto append bin name)
	# - Auto-detect tag prefix (tries: v<ver> then <ver>) unless user explicitly provides it.
	# - No traps (no nested traps); manual cleanup.
	#
	# Bin spec forms:
	#   A) Plain bins string (space/comma):
	#        "foo bar"  or  "foo,bar"
	#      Target behavior:
	#        - Use --into <dir> to install all bins into a directory (recommended)
	#        - Without --into, default install dir is /usr/local/bin
	#
	#   B) Per-bin mapping (repeatable --map):
	#        --map "foo:/usr/local/bin/x" --map "bar:/opt/bin/y"
	#        --map "foo:/usr/local/bin"   --map "bar:/opt/bin"
	#
	# Usage:
	#   # single bin, install latest into dir (keeps name)
	#   gh_install_exec "BurntSushi/ripgrep" "ripgrep-{ver}-aarch64-unknown-linux-gnu.tar.gz" "rg" --into "/usr/local/bin/"
	#
	#   # single bin, install fixed version into dir
	#   gh_install_exec "BurntSushi/ripgrep" "ripgrep-{ver}-aarch64-unknown-linux-gnu.tar.gz" "rg" --into "/usr/local/bin/" --version "13.0.0"
	#
	#   # multi bin, install all into dir (latest)
	#   gh_install_exec "owner/repo" "pkg_{ver}_Linux_arm64.tar.gz" "foo bar" --into "/usr/local/bin"
	#
	#   # multi bin, per-bin target mapping (latest)
	#   gh_install_exec "sxyazi/yazi" "yazi-aarch64-unknown-linux-gnu.zip" "ya yazi" \
	#     --map "ya:/usr/local/bin/ya" \
	#     --map "yazi:/opt/bin/yazi"
	#
	#   # per-bin mapping to directories (auto appends bin name)
	#   gh_install_exec "sxyazi/yazi" "yazi-aarch64-unknown-linux-gnu.zip" "ya yazi" \
	#     --map "ya:/usr/local/bin" \
	#     --map "yazi:/opt/bin"
	#
	# Args:
	#   1) repo         owner/name
	#   2) asset_tpl    asset filename template (supports {ver})
	#   3) binspec      plain bins list: "bin1 bin2" or "bin1,bin2"
	#
	# Options:
	#   --into <dir>            Directory to install all bins (default: /usr/local/bin)
	#   --map <bin:target>      Repeatable per-bin override. Target can be:
	#                           - directory (exists or ends with '/'): installs to <target>/<bin>
	#                           - file path: installs to that file path (rename)
	#   --tag-prefix <prefix>   Tag prefix override. If omitted, auto-detect by trying "v" then "".
	#                           Use empty string to force no prefix: --tag-prefix ""
	#   --version <ver>         "latest" (default) or a fixed version ("1.2.3" or "v1.2.3")
	#   --                      End of options
	#
	# Behavior:
	# - Does not use GitHub API (no JSON parsing, no rate limit issues).
	# - Version substitution: {ver} uses numeric version without leading "v".
	# - Tag selection: controlled by --tag-prefix; default auto tries "v" then "".

	local repo="${1:-}"
	local asset_tpl="${2:-}"
	local binspec="${3:-}"
	[[ -n "$repo" && -n "$asset_tpl" && -n "$binspec" ]] || {
		log "Usage: gh_install_exec <owner/repo> <asset_template> <binspec> [--into DIR] [--map bin:target ...] [--tag-prefix P] [--version V]" >&2
		return 2
	}
	shift 3 || true

	local into_dir="/usr/local/bin"
	local tag_prefix="__AUTO__"
	local version="latest"

	local map_specs=()  # raw --map "bin:target"
	declare -A map_target=()  # bin -> target

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--into)
			into_dir="${2:-}"
			[[ -n "$into_dir" ]] || die "gh_install_exec: --into requires a value"
			shift 2
			;;
		--map)
			local m="${2:-}"
			[[ -n "$m" ]] || die "gh_install_exec: --map requires a value (bin:target)"
			map_specs+=("$m")
			shift 2
			;;
		--tag-prefix)
			# Allow explicit empty string: --tag-prefix ""
			tag_prefix="${2-}"
			shift 2
			;;
		--version)
			version="${2:-}"
			[[ -n "$version" ]] || die "gh_install_exec: --version requires a value"
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			die "gh_install_exec: unknown option: $1"
			;;
		esac
	done

	command -v curl >/dev/null 2>&1 || { err "Missing: curl" >&2; return 127; }
	command -v install >/dev/null 2>&1 || { err "Missing: install" >&2; return 127; }
	command -v sed >/dev/null 2>&1 || { err "Missing: sed" >&2; return 127; }
	command -v awk >/dev/null 2>&1 || { err "Missing: awk" >&2; return 127; }
	command -v find >/dev/null 2>&1 || { err "Missing: find" >&2; return 127; }

	# Parse binspec into bins
	binspec="${binspec//,/ }"
	# shellcheck disable=SC2206
	local bins=($binspec)
	[[ "${#bins[@]}" -gt 0 ]] || { err "[gh_install_exec] ERROR: empty binspec" >&2; return 2; }

	# Helper: is a path a directory target?
	_gh__target_is_dir() {
		local p="$1"
		[[ "$p" == */ ]] && return 0
		[[ -d "$p" ]] && return 0
		return 1
	}

	# Normalize and validate --map specs
	# - Enforce format bin:target
	# - Later specs override earlier ones for the same bin
	if [[ "${#map_specs[@]}" -gt 0 ]]; then
		local ms b t
		for ms in "${map_specs[@]}"; do
			[[ "$ms" == *:* ]] || die "gh_install_exec: invalid --map '$ms' (expected bin:target)"
			b="${ms%%:*}"
			t="${ms#*:}"
			[[ -n "$b" && -n "$t" ]] || die "gh_install_exec: invalid --map '$ms' (expected bin:target)"
			map_target["$b"]="$t"
		done
	fi

	# Validate that mapped bins exist in binspec (to catch typos)
	if [[ "${#map_target[@]}" -gt 0 ]]; then
		local k matched
		for k in "${!map_target[@]}"; do
			matched=0
			for b in "${bins[@]}"; do
				if [[ "$b" == "$k" ]]; then
					matched=1
					break
				fi
			done
			[[ "$matched" -eq 1 ]] || die "gh_install_exec: --map refers to unknown bin '$k' (not present in binspec)"
		done
	fi

	# If multiple bins and into_dir looks like a file path, error out early
	if [[ "${#bins[@]}" -gt 1 ]]; then
		if ! _gh__target_is_dir "$into_dir"; then
			# If into_dir does not exist and does not end with '/', treat it as file-like.
			# Multi-bin needs a directory.
			die "gh_install_exec: --into must be a directory for multiple bins (got: $into_dir)"
		fi
	fi

	# Create into_dir if it is intended as a directory
	if _gh__target_is_dir "$into_dir"; then
		mkdir -p "$into_dir" 2>/dev/null || true
	fi

	# ---------------- download + extract asset ----------------
	local tmpd ver asset ext archive
	tmpd="$(mktemp -d "/tmp/gh_install.XXXXXX")" || { err "mktemp failed" >&2; return 1; }
	_gh__cleanup() { rm -rf "$tmpd" >/dev/null 2>&1 || true; }

	# Resolve version without GitHub API:
	# - "latest": follow /releases/latest redirect to extract numeric version from the final tag URL
	# - fixed: accept "1.2.3" or "v1.2.3" and normalize to numeric for {ver} substitution
	if [[ -z "$version" || "$version" == "latest" ]]; then
		ver="$(
			curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" |
				sed -n 's#.*/tag/[^0-9]*##p'
		)"
		if [[ -z "$ver" ]]; then
			err "[gh_install_exec] ERROR: failed to detect latest version for ${repo}" >&2
			_gh__cleanup
			return 1
		fi
	else
		ver="${version#v}"
		if [[ -z "$ver" ]]; then
			err "[gh_install_exec] ERROR: invalid version argument: '$version'" >&2
			_gh__cleanup
			return 1
		fi
	fi

	asset="${asset_tpl//\{ver\}/$ver}"

	ext=""
	case "$asset" in
	*.tar.gz | *.tgz) ext="tar.gz" ;;
	*.tar.xz | *.txz) ext="tar.xz" ;;
	*.tar.bz2 | *.tbz2) ext="tar.bz2" ;;
	*.zip) ext="zip" ;;
	*) ext="" ;;
	esac

	if [[ -z "$ext" ]]; then
		err "[gh_install_exec] ERROR: unsupported asset type: $asset" >&2
		log "[gh_install_exec] Supported: .tar.gz/.tgz .tar.xz/.txz .tar.bz2/.tbz2 .zip" >&2
		_gh__cleanup
		return 1
	fi

	archive="$tmpd/asset.$ext"

	# -------- Auto-detect tag prefix --------
	# If user provided --tag-prefix (even empty), use it exactly.
	# Else, try "v" first, then "".
	local tried=()
	local ok=0
	local url=""
	local prefix_list=()

	if [[ "$tag_prefix" == "__AUTO__" ]]; then
		prefix_list=("v" "")
	else
		prefix_list=("$tag_prefix")
	fi

	local prefix tag
	for prefix in "${prefix_list[@]}"; do
		tag="${prefix}${ver}"
		url="https://github.com/${repo}/releases/download/${tag}/${asset}"
		tried+=("$url")
		log "[gh_install_exec] repo=${repo} ver=${ver} tag=${tag} asset=${asset}" >&2
		if curl -fsSL --retry 3 --retry-delay 2 -o "$archive" "$url"; then
			ok=1
			break
		fi
	done

	if [[ "$ok" -ne 1 ]]; then
		err "[gh_install_exec] ERROR: failed to download asset (tried ${#tried[@]} url(s))" >&2
		for u in "${tried[@]}"; do
			log "  - $u" >&2
		done
		_gh__cleanup
		return 1
	fi

	# -------- Extract once --------
	case "$ext" in
	tar.gz | tar.xz | tar.bz2)
		command -v tar >/dev/null 2>&1 || { err "Missing: tar" >&2; _gh__cleanup; return 127; }
		tar -C "$tmpd" -xf "$archive" || { err "[gh_install_exec] ERROR: failed to extract tar archive" >&2; _gh__cleanup; return 1; }
		;;
	zip)
		command -v unzip >/dev/null 2>&1 || { err "Missing: unzip" >&2; _gh__cleanup; return 127; }
		unzip -q "$archive" -d "$tmpd" || { err "[gh_install_exec] ERROR: failed to unzip archive" >&2; _gh__cleanup; return 1; }
		;;
	esac

	# ---------------- locate + install ----------------
	local b found t dst

	for b in "${bins[@]}"; do
		found="$(find "$tmpd" -type f -name "$b" -perm -u+x 2>/dev/null | head -n1 || true)"
		[[ -n "$found" ]] || found="$(find "$tmpd" -type f -name "$b" 2>/dev/null | head -n1 || true)"

		if [[ -z "$found" ]]; then
			err "[gh_install_exec] ERROR: '${b}' not found in extracted archive" >&2
			log "[gh_install_exec] Hint: list files under tmp dir: $tmpd" >&2
			_gh__cleanup
			return 1
		fi

		# Determine destination:
		# - If mapped: use map_target[bin]
		# - Else: use --into directory (or default)
		if [[ -n "${map_target[$b]:-}" ]]; then
			t="${map_target[$b]}"
			if _gh__target_is_dir "$t"; then
				mkdir -p "$t" 2>/dev/null || true
				dst="${t%/}/${b}"
			else
				mkdir -p "$(dirname "$t")" 2>/dev/null || true
				dst="$t"
			fi
		else
			t="$into_dir"
			if _gh__target_is_dir "$t"; then
				mkdir -p "$t" 2>/dev/null || true
				dst="${t%/}/${b}"
			else
				# Only allowed if there is exactly one bin
				if [[ "${#bins[@]}" -ne 1 ]]; then
					err "[gh_install_exec] ERROR: --into must be a directory for multiple bins (got: $t)" >&2
					_gh__cleanup
					return 2
				fi
				mkdir -p "$(dirname "$t")" 2>/dev/null || true
				dst="$t"
			fi
		fi

		if ! install -m 0755 "$found" "$dst"; then
			err "[gh_install_exec] ERROR: failed to install '${b}' to '${dst}' (need permission?)" >&2
			_gh__cleanup
			return 1
		fi

		log "[gh_install_exec] Installed: ${dst}" >&2
	done

	_gh__cleanup
	return 0
}

gh_download_release() {
	# Download a GitHub release asset only (optionally rename, optionally extract).
	# - No GitHub API
	# - "latest": follows /releases/latest redirect to infer version
	# - fixed version supported: "1.2.3" or "v1.2.3"
	# - asset template supports {ver} (numeric ver without leading 'v')
	# - optional extract (.tar.gz/.tgz/.tar.xz/.txz/.tar.bz2/.tbz2/.zip)
	#
	# Usage:
	#   gh_download_release "owner/repo" "pkg-{ver}-linux-arm64.tar.gz"
	#   gh_download_release "owner/repo" "pkg-{ver}.zip" --version 1.2.3
	#   gh_download_release "owner/repo" "tool_{ver}_Linux_arm64.tar.gz" --output /tmp/tool.tar.gz
	#   gh_download_release "owner/repo" "tool_{ver}_Linux_arm64.tar.gz" --into /opt/tool --extract
	#   gh_download_release "owner/repo" "asset.zip" --tag-prefix "" --extract --into /opt/x
	#
	# Args:
	#   1) repo       owner/name
	#   2) asset_tpl  asset filename (supports {ver})
	#
	# Options:
	#   --version <ver|latest>   Default: latest
	#   --tag-prefix <prefix>    Default: auto try "v" then ""
	#                            Use empty string to force no prefix: --tag-prefix ""
	#   --output <path>          Save downloaded file as this path (rename). If omitted, saves into --into (or cwd).
	#   --into <dir>             Directory to place downloaded file (or extracted contents). Default: .
	#   --extract                Extract archive into --into (or cwd). Keeps archive only if --keep-archive.
	#   --keep-archive           Keep downloaded archive when --extract is used.
	#   --retries <N>            Download retry count (curl --retry uses its own retry too). Default: 2

	local repo="${1:-}"
	local asset_tpl="${2:-}"
	[[ -n "$repo" && -n "$asset_tpl" ]] || {
		err "Usage: gh_download_release <owner/repo> <asset_template> [--version V] [--tag-prefix P] [--output PATH] [--into DIR] [--extract] [--keep-archive] [--retries N]"
		return 2
	}
	shift 2 || true

	local version="latest"
	local tag_prefix="__AUTO__"
	local out_path=""
	local into_dir="."
	local do_extract=0
	local keep_archive=0
	local retries=2

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--version)
			version="${2:-}"
			[[ -n "$version" ]] || die "gh_download_release: --version requires a value"
			shift 2
			;;
		--tag-prefix)
			tag_prefix="${2-}"  # allow empty string
			shift 2
			;;
		--output)
			out_path="${2:-}"
			[[ -n "$out_path" ]] || die "gh_download_release: --output requires a value"
			shift 2
			;;
		--into)
			into_dir="${2:-}"
			[[ -n "$into_dir" ]] || die "gh_download_release: --into requires a value"
			shift 2
			;;
		--extract)
			do_extract=1
			shift
			;;
		--keep-archive)
			keep_archive=1
			shift
			;;
		--retries)
			retries="${2:-}"
			[[ "$retries" =~ ^[0-9]+$ ]] || die "gh_download_release: --retries must be an integer"
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			die "gh_download_release: unknown option: $1"
			;;
		esac
	done

	command -v curl >/dev/null 2>&1 || { err "Missing: curl"; return 127; }
	command -v sed  >/dev/null 2>&1 || { err "Missing: sed"; return 127; }

	# Resolve version (numeric) without GitHub API
	local ver=""
	if [[ -z "$version" || "$version" == "latest" ]]; then
		ver="$(
			curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" |
				sed -n 's#.*/tag/[^0-9]*##p'
		)"
		[[ -n "$ver" ]] || { err "[gh_download_release] ERROR: failed to detect latest version for ${repo}"; return 1; }
	else
		ver="${version#v}"
		[[ -n "$ver" ]] || { err "[gh_download_release] ERROR: invalid version argument: '$version'"; return 1; }
	fi

	local asset="${asset_tpl//\{ver\}/$ver}"

	# Determine archive type (for --extract)
	local ext=""
	case "$asset" in
	*.tar.gz|*.tgz)   ext="tar.gz" ;;
	*.tar.xz|*.txz)   ext="tar.xz" ;;
	*.tar.bz2|*.tbz2) ext="tar.bz2" ;;
	*.zip)            ext="zip" ;;
	*)                ext="" ;;
	esac

	if [[ "$do_extract" -eq 1 && -z "$ext" ]]; then
		err "[gh_download_release] ERROR: --extract requires an archive type (.tar.gz/.tgz .tar.xz/.txz .tar.bz2/.tbz2 .zip). Got: $asset"
		return 1
	fi

	# Prepare destination
	mkdir -p "$into_dir" 2>/dev/null || true

	local filename="$asset"
	if [[ -n "$out_path" ]]; then
		# user chooses final filename (rename)
		filename="$(basename "$out_path")"
	fi

	local dest_archive=""
	if [[ -n "$out_path" ]]; then
		dest_archive="$out_path"
	else
		dest_archive="${into_dir%/}/${filename}"
	fi

	# Download with tag-prefix auto-detect
	local prefix_list=()
	if [[ "$tag_prefix" == "__AUTO__" ]]; then
		prefix_list=("v" "")
	else
		prefix_list=("$tag_prefix")
	fi

	local ok=0
	local tried=()
	local prefix tag url

	# download to temp first to avoid partial file at final path
	local tmpd
	tmpd="$(mktemp -d "/tmp/gh_download.XXXXXX")" || { err "mktemp failed"; return 1; }
	local tmp_archive="${tmpd}/${filename}"

	_ghdl_cleanup() { rm -rf "$tmpd" >/dev/null 2>&1 || true; }

	for prefix in "${prefix_list[@]}"; do
		tag="${prefix}${ver}"
		url="https://github.com/${repo}/releases/download/${tag}/${asset}"
		tried+=("$url")
		log "[gh_download_release] repo=${repo} ver=${ver} tag=${tag} asset=${asset}"
		if curl -fsSL --retry 3 --retry-delay 2 -o "$tmp_archive" "$url"; then
			ok=1
			break
		fi
	done

	if [[ "$ok" -ne 1 ]]; then
		err "[gh_download_release] ERROR: failed to download asset (tried ${#tried[@]} url(s))"
		for url in "${tried[@]}"; do
			log "  - $url" >&2
		done
		_ghdl_cleanup
		return 1
	fi

	# Move to destination (rename if needed)
	mkdir -p "$(dirname "$dest_archive")" 2>/dev/null || true
	rm -f "$dest_archive" 2>/dev/null || true
	if ! mv -f "$tmp_archive" "$dest_archive"; then
		err "[gh_download_release] ERROR: failed to move archive to $dest_archive"
		_ghdl_cleanup
		return 1
	fi

	if [[ "$do_extract" -eq 0 ]]; then
		log "[gh_download_release] Downloaded: $dest_archive"
		_ghdl_cleanup
		return 0
	fi

	# Extract into into_dir (or cwd)
	case "$ext" in
	tar.gz|tar.xz|tar.bz2)
		command -v tar >/dev/null 2>&1 || { err "Missing: tar"; _ghdl_cleanup; return 127; }
		tar -C "$into_dir" -xf "$dest_archive" || { err "[gh_download_release] ERROR: failed to extract tar archive"; _ghdl_cleanup; return 1; }
		;;
	zip)
		command -v unzip >/dev/null 2>&1 || { err "Missing: unzip"; _ghdl_cleanup; return 127; }
		unzip -q "$dest_archive" -d "$into_dir" || { err "[gh_download_release] ERROR: failed to unzip archive"; _ghdl_cleanup; return 1; }
		;;
	esac

	log "[gh_download_release] Extracted into: ${into_dir}"
	if [[ "$keep_archive" -eq 0 ]]; then
		rm -f "$dest_archive" 2>/dev/null || true
		log "[gh_download_release] Removed archive: ${dest_archive}"
	else
		log "[gh_download_release] Kept archive: ${dest_archive}"
	fi

	_ghdl_cleanup
	return 0
}
