#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_CONFIG="${1:-release}"
APP_DIR="$ROOT_DIR/UsageBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

cd "$ROOT_DIR"
SWIFT_BUILD_ARGS=(-c "$BUILD_CONFIG")
if [[ "${USAGEBAR_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  SWIFT_BUILD_ARGS+=(--disable-sandbox)
fi
swift build "${SWIFT_BUILD_ARGS[@]}"

mkdir -p "$MACOS_DIR"
cp ".build/$BUILD_CONFIG/UsageBar" "$MACOS_DIR/UsageBar"
cp "$ROOT_DIR/scripts/Info.plist" "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
