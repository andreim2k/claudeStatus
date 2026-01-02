#!/bin/bash
# Create macOS .app bundle for Claude Status

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

APP_NAME="Claude Status"
BUNDLE_ID="com.claude.status"
VERSION="1.0.0"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Creating $APP_NAME.app"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if venv exists
if [ ! -d "venv" ]; then
    echo "Running setup first..."
    ./setup.sh
fi

# Create app bundle structure
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
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

# Create launcher script (relocatable - doesn't use hardcoded activate paths)
cat > "$APP_DIR/Contents/MacOS/launcher" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RESOURCES_DIR="$SCRIPT_DIR/../Resources"
cd "$RESOURCES_DIR"

# Set up venv paths directly (avoid hardcoded paths in activate script)
export VIRTUAL_ENV="$RESOURCES_DIR/venv"
export PATH="$VIRTUAL_ENV/bin:$PATH"
unset PYTHONHOME

exec "$VIRTUAL_ENV/bin/python3" claude_status.py
EOF

chmod +x "$APP_DIR/Contents/MacOS/launcher"

# Copy resources
cp -r venv "$APP_DIR/Contents/Resources/"
cp claude_status.py "$APP_DIR/Contents/Resources/"
cp requirements.txt "$APP_DIR/Contents/Resources/"

# Create app icon (simple approach using sips if available)
# For now, create a placeholder - user can replace with custom icon
if [ -f "icon.png" ]; then
    mkdir -p "$APP_DIR/Contents/Resources/AppIcon.iconset"
    sips -z 16 16 icon.png --out "$APP_DIR/Contents/Resources/AppIcon.iconset/icon_16x16.png" 2>/dev/null
    sips -z 32 32 icon.png --out "$APP_DIR/Contents/Resources/AppIcon.iconset/icon_16x16@2x.png" 2>/dev/null
    sips -z 32 32 icon.png --out "$APP_DIR/Contents/Resources/AppIcon.iconset/icon_32x32.png" 2>/dev/null
    sips -z 64 64 icon.png --out "$APP_DIR/Contents/Resources/AppIcon.iconset/icon_32x32@2x.png" 2>/dev/null
    sips -z 128 128 icon.png --out "$APP_DIR/Contents/Resources/AppIcon.iconset/icon_128x128.png" 2>/dev/null
    sips -z 256 256 icon.png --out "$APP_DIR/Contents/Resources/AppIcon.iconset/icon_128x128@2x.png" 2>/dev/null
    sips -z 256 256 icon.png --out "$APP_DIR/Contents/Resources/AppIcon.iconset/icon_256x256.png" 2>/dev/null
    sips -z 512 512 icon.png --out "$APP_DIR/Contents/Resources/AppIcon.iconset/icon_256x256@2x.png" 2>/dev/null
    sips -z 512 512 icon.png --out "$APP_DIR/Contents/Resources/AppIcon.iconset/icon_512x512.png" 2>/dev/null
    sips -z 1024 1024 icon.png --out "$APP_DIR/Contents/Resources/AppIcon.iconset/icon_512x512@2x.png" 2>/dev/null
    iconutil -c icns "$APP_DIR/Contents/Resources/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null
    rm -rf "$APP_DIR/Contents/Resources/AppIcon.iconset"
fi

echo ""
echo "✓ App bundle created: $APP_DIR"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Next steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Double-click '$APP_NAME.app' to run"
echo ""
echo "2. To add to Login Items (start at login):"
echo "   - Open System Settings > General > Login Items"
echo "   - Click '+' and add '$APP_NAME.app'"
echo ""
echo "3. To move to Applications:"
echo "   mv '$APP_NAME.app' /Applications/"
echo ""
