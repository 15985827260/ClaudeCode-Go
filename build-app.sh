#!/bin/bash
set -e

APP_NAME="ClaudeCodeGo"
BUILD_DIR=".build/arm64-apple-macosx/debug"
APP_DIR="${APP_NAME}.app"

cd "$(dirname "$0")"

# Build
swift build

# Clean previous bundle
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/"

# Copy SPM-bundled resources into the .app bundle
SPM_BUNDLE="$BUILD_DIR/ClaudeCodeGo_ClaudeCodeGo.bundle"
if [ -d "$SPM_BUNDLE" ]; then
    cp -R "$SPM_BUNDLE/" "$APP_DIR/Contents/Resources/"
fi

# Generate Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeCodeGo</string>
    <key>CFBundleIdentifier</key>
    <string>com.claudecode.go</string>
    <key>CFBundleName</key>
    <string>ClaudeCode GO</string>
    <key>CFBundleDisplayName</key>
    <string>ClaudeCode GO</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Copy app icon from asset catalog
ICON_SRC="Assets.xcassets/AppIcon.appiconset/icon_1024.png"
if [ -f "$ICON_SRC" ]; then
    ICONSET_DIR="/tmp/${APP_NAME}.iconset"
    mkdir -p "$ICONSET_DIR"
    for size in 16 32 64 128 256 512; do
        sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET_DIR/icon_${size}x${size}.png" &>/dev/null
        if [ "$size" -le 256 ]; then
            sips -z "$((size*2))" "$((size*2))" "$ICON_SRC" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" &>/dev/null
        fi
    done
    sips -z 32 32 "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png" &>/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/$APP_NAME.icns"
    rm -rf "$ICONSET_DIR"

    /usr/libexec/PlistBuddy -c "Add CFBundleIconFile string $APP_NAME" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set CFBundleIconFile $APP_NAME" "$APP_DIR/Contents/Info.plist"
fi

echo "✅ Created $APP_DIR"
echo "   Drag to /Applications to install:"
echo "   cp -R \"$APP_DIR\" /Applications/"
