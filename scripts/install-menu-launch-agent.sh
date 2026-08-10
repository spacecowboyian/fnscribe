#!/bin/zsh -l
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${FNSCRIBE_MENU_APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/FnScribeMenu.app"
PLIST="$HOME/Library/LaunchAgents/local.fnscribe.menu.plist"

mkdir -p "$HOME/Library/LaunchAgents" "$ROOT/work" "$APP_DIR"
"$ROOT/scripts/build.sh"
ditto "$ROOT/public/FnScribeMenu.app" "$APP"

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
    <key>FNSCRIBE_UI_PORT</key>
    <string>${FNSCRIBE_UI_PORT:-8765}</string>
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
