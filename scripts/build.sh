#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p work/bin work/module-cache public

echo "Building FnScribe recorder..."
env CLANG_MODULE_CACHE_PATH="$ROOT/work/module-cache" \
  swiftc \
  -module-cache-path "$ROOT/work/module-cache" \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreGraphics \
  Sources/FnScribe/main.swift \
  -o work/bin/fn-scribe

echo "Building FnScribe menu app..."
mkdir -p public/FnScribeMenu.app/Contents/MacOS public/FnScribeMenu.app/Contents/Resources
cp Resources/FnScribeMenu-Info.plist public/FnScribeMenu.app/Contents/Info.plist
env CLANG_MODULE_CACHE_PATH="$ROOT/work/module-cache" \
  swiftc \
  -module-cache-path "$ROOT/work/module-cache" \
  -framework AppKit \
  Sources/FnScribeMenu/main.swift \
  -o public/FnScribeMenu.app/Contents/MacOS/FnScribeMenu

chmod +x work/bin/fn-scribe public/FnScribeMenu.app/Contents/MacOS/FnScribeMenu

# Sign the recorder with a stable identity so its TCC grants (Input Monitoring,
# Microphone) survive rebuilds. Ad-hoc signatures are keyed by cdhash, which
# changes on every build and silently voids the grants.
SIGN_IDENTITY="${FNSCRIBE_SIGN_IDENTITY:-FnScribe Dev}"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$SIGN_IDENTITY" --identifier local.fnscribe.recorder work/bin/fn-scribe
  codesign --force --deep --sign "$SIGN_IDENTITY" --identifier local.fnscribe.menu public/FnScribeMenu.app
else
  echo "Warning: signing identity '$SIGN_IDENTITY' not found; falling back to ad-hoc."
  echo "         Permissions will need re-granting after every build."
  codesign --force --deep --sign - public/FnScribeMenu.app >/dev/null 2>&1 || true
fi

echo "Build complete."
