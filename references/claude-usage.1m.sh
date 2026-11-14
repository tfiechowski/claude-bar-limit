#!/bin/bash

# SwiftBar may have a more limited PATH than your normal terminal.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.claude/bin"

CLAUDE_BIN="$(command -v claude)"

if [ -z "$CLAUDE_BIN" ]; then
  echo "C: ?%"
  echo "---"
  echo "claude executable not found"
  echo "PATH: $PATH"
  exit 0
fi

OUTPUT="$("$CLAUDE_BIN" -p "/usage" 2>&1)"

SESSION_LINE="$(echo "$OUTPUT" | grep -m1 '^Current session:')"

if [ -z "$SESSION_LINE" ]; then
  echo "C: ?%"
  echo "---"
  echo "Could not read Claude usage"
  echo "---"
  echo "Refresh | refresh=true"
  exit 0
fi

PERCENT="$(echo "$SESSION_LINE" | sed -E 's/^Current session: ([0-9]+)% used.*/\1/')"
RESET="$(echo "$SESSION_LINE" | sed -E 's/^Current session: [0-9]+% used · resets //')"

echo "C: ${PERCENT}%"
echo "---"
echo "Current session: ${PERCENT}%"
echo "Resets: ${RESET}"
echo "---"
echo "Refresh | refresh=true"