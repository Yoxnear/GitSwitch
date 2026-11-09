#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Git Identity Switcher.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
ICONSET="$ROOT/Assets/AppIcon.iconset"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This app must be compiled on a Mac (macOS 13 or newer)."
  exit 1
fi
if ! command -v xcrun >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Run: xcode-select --install"
  exit 1
fi

mkdir -p "$MACOS" "$RESOURCES"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>GitSwitch</string>
  <key>CFBundleDisplayName</key><string>GitSwitch</string>
  <key>CFBundleIdentifier</key><string>dev.local.gitidentityswitcher</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>CFBundleShortVersionString</key><string>3.0</string>
  <key>CFBundleExecutable</key><string>GitSwitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
fi

echo "Compiling GitSwitch 3.0…"
xcrun swiftc -parse-as-library -O \
  -framework SwiftUI -framework AppKit \
  "$ROOT/Sources/GitSwitchCore.swift" \
  "$ROOT/Sources/GitSwitchApp.swift" \
  -o "$MACOS/GitSwitch"
chmod +x "$MACOS/GitSwitch"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP"
fi

printf '\nBuilt: %s\n' "$APP"
if [[ "${1:-}" != "--no-open" ]]; then open "$APP"; fi
