#!/bin/bash
# Install LaunchAgent for auto-start

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLIST_NAME="com.claude.status.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Installing Auto-Start for Claude Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create LaunchAgents directory if it doesn't exist
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
        <string>$SCRIPT_DIR/venv/bin/python3</string>
        <string>$SCRIPT_DIR/claude_status.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/claude-status.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-status-error.log</string>
</dict>
</plist>
EOF

# Load the launch agent
launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo "✓ Auto-start installed!"
echo ""
echo "The app will now start automatically when you log in."
echo ""
echo "To disable auto-start, run:"
echo "  ./uninstall_autostart.sh"
echo ""
