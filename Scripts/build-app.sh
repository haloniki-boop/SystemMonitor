#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export XDG_CACHE_HOME=/private/tmp/systemmonitor-cache
export CLANG_MODULE_CACHE_PATH=/private/tmp/systemmonitor-clang

BUILD_PATH=/private/tmp/systemmonitor-build
STAGING_ROOT="$(mktemp -d /private/tmp/systemmonitor-package.XXXXXX)"
APP="$STAGING_ROOT/SystemMonitor.app"
OUTPUT_APP="$PWD/build/SystemMonitor.app"
OUTPUT_ZIP="$PWD/build/SystemMonitor.zip"
trap 'rm -rf "$STAGING_ROOT"' EXIT

swift build --disable-sandbox --scratch-path "$BUILD_PATH" -c release --product SystemMonitor

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_PATH/release/SystemMonitor" "$APP/Contents/MacOS/SystemMonitor"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
cp Assets/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$PWD/build"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT_ZIP"
mkdir -p "$OUTPUT_APP/Contents/MacOS" "$OUTPUT_APP/Contents/Resources" "$OUTPUT_APP/Contents/_CodeSignature"
cp "$APP/Contents/MacOS/SystemMonitor" "$OUTPUT_APP/Contents/MacOS/SystemMonitor"
cp "$APP/Contents/Info.plist" "$OUTPUT_APP/Contents/Info.plist"
cp "$APP/Contents/Resources/AppIcon.png" "$OUTPUT_APP/Contents/Resources/AppIcon.png"
cp "$APP/Contents/_CodeSignature/CodeResources" "$OUTPUT_APP/Contents/_CodeSignature/CodeResources"

echo "$OUTPUT_APP"
echo "$OUTPUT_ZIP"
