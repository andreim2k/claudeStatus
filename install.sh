#!/bin/bash
# Install Claude Status to Applications

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="Claude Status"

echo "Installing Claude Status..."

# Check if app exists
if [ ! -d "$SCRIPT_DIR/$APP_NAME.app" ]; then
    echo "App not found. Building first..."
    "$SCRIPT_DIR/build.sh"
fi

# Copy to Applications
cp -R "$SCRIPT_DIR/$APP_NAME.app" "/Applications/$APP_NAME.app"

# Refresh icon cache
touch "/Applications/$APP_NAME.app"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "/Applications/$APP_NAME.app" 2>/dev/null || true

echo ""
echo "Installed to /Applications/$APP_NAME.app"
echo ""
echo "To start at login, run: ./install_autostart.sh"
