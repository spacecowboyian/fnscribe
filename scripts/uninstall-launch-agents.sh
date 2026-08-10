#!/bin/zsh -l
set -euo pipefail

for label in local.fnscribe.recorder local.fnscribe.menu; do
  plist="$HOME/Library/LaunchAgents/$label.plist"
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  rm -f "$plist"
done

echo "FnScribe launch agents removed."
