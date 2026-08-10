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
codesign --force --deep --sign - public/FnScribeMenu.app >/dev/null 2>&1 || true

echo "Build complete."
