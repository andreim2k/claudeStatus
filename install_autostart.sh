#!/bin/bash
# Install LaunchAgent to start Claude Status at login

APP_NAME="Claude Status"
APP_PATH="/Applications/$APP_NAME.app"
PLIST_NAME="com.claude.status.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "Installing auto-start for Claude Status..."

# Check if app is installed
if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_NAME.app not found in /Applications"
    echo "Run ./install.sh first"
    exit 1
fi

# Create LaunchAgents directory if needed
mkdir -p "$LAUNCH_AGENTS_DIR"

# Unload existing if present
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null

# Create plist file
cat > "$LAUNCH_AGENTS_DIR/$PLIST_NAME" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.status</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$APP_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

# Load the launch agent
launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo ""
echo "Auto-start installed!"
echo "Claude Status will now start automatically when you log in."
echo ""
echo "To disable: ./uninstall_autostart.sh"
