#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP_PATH="$PWD/dist/MacLaunch.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp .build/release/MacLaunch "$APP_PATH/Contents/MacOS/MacLaunch"
cp scripts/Info.plist "$APP_PATH/Contents/Info.plist"
swift scripts/Icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_PATH"
printf 'Built: %s\n' "$APP_PATH"
