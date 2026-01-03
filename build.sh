#!/bin/bash
# Build Claude Status native macOS app

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

APP_NAME="Claude Status"
BUNDLE_ID="com.claude.status"
VERSION="1.0.0"

echo "Building Claude Status..."
echo ""

# Build the Swift app
cd ClaudeStatusApp
./build.sh
cd ..

# Download and set the Claude icon if not present
if [ ! -f "$APP_NAME.app/Contents/Resources/AppIcon.icns" ]; then
    echo "Setting up app icon..."

    # Download Claude icon
    curl -s -L "https://claude.ai/apple-touch-icon.png" -o /tmp/claude_icon.png

    # Create iconset
    mkdir -p /tmp/AppIcon.iconset
    sips -z 16 16 /tmp/claude_icon.png --out /tmp/AppIcon.iconset/icon_16x16.png 2>/dev/null
    sips -z 32 32 /tmp/claude_icon.png --out /tmp/AppIcon.iconset/icon_16x16@2x.png 2>/dev/null
    sips -z 32 32 /tmp/claude_icon.png --out /tmp/AppIcon.iconset/icon_32x32.png 2>/dev/null
    sips -z 64 64 /tmp/claude_icon.png --out /tmp/AppIcon.iconset/icon_32x32@2x.png 2>/dev/null
    sips -z 128 128 /tmp/claude_icon.png --out /tmp/AppIcon.iconset/icon_128x128.png 2>/dev/null
    sips -z 256 256 /tmp/claude_icon.png --out /tmp/AppIcon.iconset/icon_128x128@2x.png 2>/dev/null
    sips -z 256 256 /tmp/claude_icon.png --out /tmp/AppIcon.iconset/icon_256x256.png 2>/dev/null
    sips -z 512 512 /tmp/claude_icon.png --out /tmp/AppIcon.iconset/icon_256x256@2x.png 2>/dev/null
    sips -z 512 512 /tmp/claude_icon.png --out /tmp/AppIcon.iconset/icon_512x512.png 2>/dev/null
    sips -z 1024 1024 /tmp/claude_icon.png --out /tmp/AppIcon.iconset/icon_512x512@2x.png 2>/dev/null

    # Convert to icns
    iconutil -c icns /tmp/AppIcon.iconset -o "$APP_NAME.app/Contents/Resources/AppIcon.icns"

    # Cleanup
    rm -rf /tmp/AppIcon.iconset /tmp/claude_icon.png

    echo "App icon set!"
fi

echo ""
echo "Build complete: $APP_NAME.app"
echo ""
echo "To run:     open '$APP_NAME.app'"
echo "To install: ./install.sh"
