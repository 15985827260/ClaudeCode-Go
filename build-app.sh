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

echo "✅ Created $APP_DIR"
echo "   Drag to /Applications to install:"
echo "   cp -R \"$APP_DIR\" /Applications/"
