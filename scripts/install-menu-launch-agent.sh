#!/bin/zsh -l
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/public/FnScribeMenu.app"
PLIST="$HOME/Library/LaunchAgents/local.fnscribe.menu.plist"

mkdir -p "$HOME/Library/LaunchAgents" "$ROOT/work"
"$ROOT/scripts/build.sh"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.fnscribe.menu</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP/Contents/MacOS/FnScribeMenu</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>FNSCRIBE_PROJECT_ROOT</key>
    <string>$ROOT</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$ROOT/work/fn-scribe-menu.out.log</string>
  <key>StandardErrorPath</key>
  <string>$ROOT/work/fn-scribe-menu.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/local.fnscribe.menu"
launchctl kickstart -k "gui/$(id -u)/local.fnscribe.menu"

echo "FnScribe menu app installed at login."
