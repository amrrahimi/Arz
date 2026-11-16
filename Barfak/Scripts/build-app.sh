#!/bin/bash
# Builds Barfak.app into ./build (requires Xcode or the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."

# BARFAK_BINARY can point at a prebuilt (e.g. universal) binary.
if [ -n "${BARFAK_BINARY:-}" ]; then
    BIN="$BARFAK_BINARY"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/Barfak"
fi

APP="build/Barfak.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Barfak"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Barfak</string>
    <key>CFBundleDisplayName</key><string>Barfak</string>
    <key>CFBundleIdentifier</key><string>local.barfak.app</string>
    <key>CFBundleExecutable</key><string>Barfak</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
