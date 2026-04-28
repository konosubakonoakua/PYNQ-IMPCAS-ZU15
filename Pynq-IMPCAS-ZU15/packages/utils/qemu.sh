#!/bin/bash

set -e
# set -x

. /etc/environment
for f in /etc/profile.d/*.sh; do source "$f"; done

export HOME=/home/xilinx

LIB="/tmp/stage4/helper.sh"
[[ -f "$LIB" ]] || {
	echo "ERROR: Missing $LIB" >&2
	exit 1
}
source "$LIB"

log "[utils] start"

mkdir -p "${HOME}/.local/bin" "${HOME}/.config"
export PATH="${HOME}/.local/bin:$PATH"

# -------- fzf --------
if [[ ! -d "${HOME}/.fzf" ]]; then
	git_clone_with_retry https://github.com/junegunn/fzf.git --dir "${HOME}/.fzf" --retries 3
	bash "${HOME}/.fzf/install" --all || true
fi

# -------- uv --------
if ! command -v uv >/dev/null 2>&1; then
	mkdir -p "${HOME}/.config/uv"
	cat >"${HOME}/.config/uv/uv.toml" <<'EOF'
index-url = "https://mirrors.bfsu.edu.cn/pypi/web/simple"
EOF
	curl -LsSf https://astral.sh/uv/install.sh | sh || true
fi

# -------- starship --------
if ! command -v starship >/dev/null 2>&1; then
	curl -fsSL https://starship.rs/install.sh | sh -s -- -y
fi

# -------- lazygit --------
if ! command -v lazygit >/dev/null 2>&1; then
	gh_install_exec \
		"jesseduffield/lazygit" \
		"lazygit_{ver}_Linux_arm64.tar.gz" \
		"lazygit" \
		--into "/usr/local/bin/" \
		--version "latest"
fi

# -------- zoxide --------
if ! command -v zoxide >/dev/null 2>&1; then
	gh_install_exec \
		"ajeetdsouza/zoxide" \
		"zoxide-{ver}-aarch64-unknown-linux-musl.tar.gz" \
		"zoxide" \
		--into "/usr/local/bin/"
fi

# -------- fd --------
if ! command -v fd >/dev/null 2>&1; then
	gh_install_exec \
		"sharkdp/fd" \
		"fd-v{ver}-aarch64-unknown-linux-gnu.tar.gz" \
		"fd" \
		--into "/usr/local/bin/"
fi

# -------- bat --------
if ! command -v bat >/dev/null 2>&1; then
	gh_install_exec \
		"sharkdp/bat" \
		"bat-v{ver}-aarch64-unknown-linux-gnu.tar.gz" \
		"bat" \
		--into "/usr/local/bin/"
fi

# -------- yq --------
if ! command -v yq >/dev/null 2>&1; then
	gh_install_exec \
		"mikefarah/yq" \
		"yq_linux_arm64.tar.gz" \
		"yq_linux_arm64" \
		--map "yq_linux_arm64:/usr/local/bin/yq"
fi

# -------- ripgrep --------
if ! command -v rg >/dev/null 2>&1; then
	gh_install_exec \
		"BurntSushi/ripgrep" \
		"ripgrep-{ver}-aarch64-unknown-linux-gnu.tar.gz" \
		"rg" \
		--into "/usr/local/bin/"
fi

# -------- yazi --------
if ! command -v yazi >/dev/null 2>&1; then
	gh_install_exec \
		"sxyazi/yazi" \
		"yazi-aarch64-unknown-linux-musl.zip" \
		"ya yazi" \
		--map "ya:/usr/local/bin/ya" \
		--map "yazi:/usr/local/bin/yazi"
fi

# -------- zellij --------
if ! command -v zellij >/dev/null 2>&1; then
	gh_install_exec \
		"zellij-org/zellij" \
		"zellij-aarch64-unknown-linux-musl.tar.gz" \
		"zellij" \
		--into "/usr/local/bin/"
fi

# -------- television --------
if ! command -v tv >/dev/null 2>&1; then
	gh_install_exec \
		"alexpasmantier/television" \
		"tv-{ver}-aarch64-unknown-linux-gnu.tar.gz" \
		"tv" \
		--into "/usr/local/bin/"
fi

# -------- hl --------
if ! command -v hl >/dev/null 2>&1; then
	gh_install_exec \
		"pamburus/hl" \
		"hl-linux-arm64-gnu.tar.gz" \
		"hl" \
		--into "/usr/local/bin/"
fi

# -------- lnav --------
if ! command -v lnav >/dev/null 2>&1; then
	gh_install_exec \
		"tstack/lnav" \
		"lnav-{ver}-linux-musl-arm64.zip" \
		"lnav" \
		--into "/usr/local/bin/"
fi

# -------- zynq-mkbootimage --------
gh_install_exec \
	"konosubakonoakua/zynq-mkbootimage" \
	"zynq-mkbootimage-aarch64-unknown-linux-gnu.tar.gz" \
	"exbootimage fpgautil mkbootimage" \
	--into "/usr/local/bin/"

cat << 'EOF' >> "${HOME}/.bashrc"

# ===== yazi auto-cd wrapper =====
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}
# ================================

EOF

append_once 'export PATH=$HOME/.local/bin:$PATH' "${HOME}/.bashrc"
append_once 'eval "$(starship init bash)"' "${HOME}/.bashrc"
append_once 'eval "$(zoxide init bash)"' "${HOME}/.bashrc"

# -------- fix privilege --------
chown -R "xilinx:xilinx" "${HOME}"

log "[utils] done"
