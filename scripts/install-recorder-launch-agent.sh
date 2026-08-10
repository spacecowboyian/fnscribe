#!/bin/zsh -l
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$HOME/Library/LaunchAgents/local.fnscribe.recorder.plist"

mkdir -p "$HOME/Library/LaunchAgents" "$ROOT/work"
"$ROOT/scripts/build.sh"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.fnscribe.recorder</string>
  <key>ProgramArguments</key>
  <array>
    <string>$ROOT/scripts/run.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$ROOT/work/fn-scribe-launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$ROOT/work/fn-scribe-launchd.err.log</string>
  <key>WorkingDirectory</key>
  <string>$ROOT</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/local.fnscribe.recorder"
launchctl kickstart -k "gui/$(id -u)/local.fnscribe.recorder"

echo "FnScribe recorder installed at login."
