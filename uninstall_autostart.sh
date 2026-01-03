#!/bin/bash
# Remove Claude Status auto-start

PLIST_NAME="com.claude.status.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "Removing auto-start for Claude Status..."

# Unload the launch agent
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null

# Remove the plist file
rm -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo "Auto-start removed."
