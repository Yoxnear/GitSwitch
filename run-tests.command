#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
EXE="$(mktemp "${TMPDIR:-/tmp}/gitswitch-core-tests.XXXXXX")"
trap 'rm -f "$EXE"' EXIT
swiftc -O "$ROOT/Sources/GitSwitchCore.swift" "$ROOT/Tests/CoreTests.swift" -o "$EXE"
"$EXE"
