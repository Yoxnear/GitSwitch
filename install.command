#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/build.command" --no-open
SOURCE="$ROOT/Git Identity Switcher.app"
TARGET="/Applications/Git Identity Switcher.app"

# Do not silently replace an app whose bundle identifier differs from GitSwitch.
if [[ -e "$TARGET" ]]; then
  ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$ID" != "dev.local.gitidentityswitcher" ]]; then
    echo "A different app exists at $TARGET. Installation stopped."
    exit 1
  fi
fi

if [[ ! -w /Applications ]]; then
  echo "Finder may need to authorize the install. Drag the newly built app into Applications and choose Replace:"
  echo "$SOURCE"
  open "$ROOT"
  exit 0
fi

if [[ -d "$TARGET" ]]; then
  BACKUP="$HOME/Desktop/GitSwitch-v2-backup-$(date +%Y%m%d-%H%M%S).app"
  echo "Backing up currently installed app: $BACKUP"
  ditto "$TARGET" "$BACKUP"
  rm -rf "$TARGET"
fi

ditto "$SOURCE" "$TARGET"
touch "$TARGET"
echo "Installed in /Applications. Find it as GitSwitch in Spotlight or Launchpad."
open "$TARGET"
