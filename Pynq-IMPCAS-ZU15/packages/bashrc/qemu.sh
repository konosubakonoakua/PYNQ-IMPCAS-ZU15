#!/bin/bash

set -e
# set -x

LIB=/tmp/stage4/helper.sh
[[ -f "$LIB" ]] || { echo "Missing $LIB (did helper package run first?)" >&2 ; exit 1; }
source "$LIB"

log "[bashrc] customizing .bashrc for xilinx"

# The target .bashrc
BASHRC="${HOME}/.bashrc"

BEGIN_MARK="# >>> PYNQ custom bashrc >>>"
END_MARK="# <<< PYNQ custom bashrc <<<"

sed -i "/$BEGIN_MARK/,/$END_MARK/d" "$BASHRC"

cat >> "$BASHRC" <<EOF

$BEGIN_MARK
# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
export HISTCONTROL=ignoreboth:erasedups
export PROMPT_COMMAND="history -n; history -w; history -c; history -r"
[ ! -f "\$HISTFILE" ] && touch "\$HISTFILE" && chmod 600 "\$HISTFILE"
tac "\$HISTFILE" | awk '!x[\$0]++' > /tmp/bash_history  && tac /tmp/bash_history > "\$HISTFILE"
rm -f /tmp/bash_history
HISTIGNORE='pwd:exit:fg:bg:top:clear:history:ls:uptime:df:btop:htop:lazygit:fvim:nvim:vim:vi:tmux:zellij:screen:ll:zi:sync:mount:lsblk:[A'

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=-1
HISTFILESIZE=-1
$END_MARK

EOF

chown "xilinx:xilinx" "$BASHRC"

log "[bashrc] done"
