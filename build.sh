#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/cloudTimer.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/CloudTimer" "$APP/Contents/MacOS/CloudTimer"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --deep -s - "$APP"

echo "$(pwd)/$APP"

for arg in "$@"; do
    if [[ "$arg" == "--run" ]]; then
        open "$APP"
    fi
done
