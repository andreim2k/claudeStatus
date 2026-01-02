#!/bin/bash
# Build script for Claude Status native macOS app (without Xcode)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

APP_NAME="Claude Status"
BUNDLE_ID="com.claude.status"

echo "Building Claude Status (native Swift)..."

# Create app bundle structure
rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# Compile Swift files
echo "Compiling Swift..."
swiftc -O \
    -target arm64-apple-macosx13.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    -framework Security \
    -framework SwiftUI \
    ClaudeStatusApp/Models.swift \
    ClaudeStatusApp/StatusPopoverView.swift \
    ClaudeStatusApp/ClaudeStatusApp.swift \
    -o "$APP_NAME.app/Contents/MacOS/ClaudeStatus"

if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

# Create Info.plist
cat > "$APP_NAME.app/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeStatus</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# Copy icon to Resources
cp ClaudeStatusApp/claude-icon@2x.png "$APP_NAME.app/Contents/Resources/"

# Copy to parent directory
cp -r "$APP_NAME.app" "../"

echo ""
echo "Build successful!"
echo "App location: ../$APP_NAME.app"
echo ""
echo "To run: open '../$APP_NAME.app'"
echo "To install: cp -r '../$APP_NAME.app' ~/Applications/"
