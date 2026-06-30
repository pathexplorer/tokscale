#!/bin/bash

# Necessary checks for dependencies
if ! command -v tmux &> /dev/null; then
    echo "Error: tmux is not installed."
    exit 1
fi

if ! command -v opencode &> /dev/null; then
    echo "Error: opencode command not found."
    exit 1
fi

SESSION_NAME="opencode_dev_$(date +%s)"

# 1. Determine the current width and height of your real terminal window
REAL_WIDTH=${COLUMNS:-190}
REAL_HEIGHT=${LINES:-45}

# 2. Create a session for the size of the monitor where OpenCode starts (Panel 0)
tmux new-session -d -s "$SESSION_NAME" -x "$REAL_WIDTH" -y "$REAL_HEIGHT" -n "Work" "opencode"

# 3. TRICK: First, cut off 40 columns from the right and run PURE BASH THERE (Panel 1).
# Pure Bash initializes instantly and takes its input stream.
tmux split-window -h -l 40 -t "$SESSION_NAME:0" "/bin/bash"

#4. Now we divide this same RIGHT panel vertically and run tokscale in the UPPER part.
# Thanks to the -b (before) flag, tokscale will be on top, and Bash will be moved down.
# At the same time, the graphical experience of tokscale will remain strictly inside its isolated panel.
tmux split-window -v -b -t "$SESSION_NAME:0.1" "$HOME/mega/scripts/workspace/tokscale/tokscale-loop"
#tmux split-window -v -b -t "$SESSION_NAME:0.1" "$HOME/.local/bin/tokscale-loop"

# 5. Connecting to the ready-made three-window dashboard
tmux attach-session -t "$SESSION_NAME"
