#!/bin/bash
# Builds Claudinho.app into ./build. `./build.sh install` also copies it to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Claudinho.app
TARGET=arm64-apple-macos14.0

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset

swiftc -O -swift-version 5 -target "$TARGET" Sources/*.swift -o "$APP/Contents/MacOS/Claudinho"
cp Resources/Info.plist "$APP/Contents/Info.plist"

swiftc -swift-version 5 -target "$TARGET" tools/makeicon/main.swift Sources/Clawd.swift -o build/makeicon
build/makeicon build/icon-1024.png
for size in 16 32 128 256 512; do
  sips -z $size $size build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x Claudinho 2>/dev/null || true
  rm -rf /Applications/Claudinho.app
  cp -R "$APP" /Applications/
  open /Applications/Claudinho.app
  echo "Installed and launched /Applications/Claudinho.app"
fi
