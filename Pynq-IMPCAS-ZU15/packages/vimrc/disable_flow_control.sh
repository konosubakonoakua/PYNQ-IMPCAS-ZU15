# ======================================================================
# Disable Terminal Flow Control (Ctrl+S / Ctrl+Q)
# Allows Vim and other editors to use Ctrl+S for saving instead of freezing.
# ======================================================================

# Check if standard input is attached to a terminal (interactive session)
# This prevents stty errors during non-interactive ssh/scp/rsync commands
if [ -t 0 ]; then
    stty -ixon
fi
