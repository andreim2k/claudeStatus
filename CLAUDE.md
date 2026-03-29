# Claude Code Configuration

## Status Bar Setup

Displays real-time Claude usage with plan, session, weekly, and extra credit usage.

### Hook Configuration

```json
{
  "hooks": {
    "StatusBar": [
      {
        "type": "command",
        "command": "bash /Users/andrei/.claude/statusline.sh"
      }
    ]
  }
}
```

### How It Works

1. **fetch-usage.py** runs every 60 seconds via launchd agent
2. Calls `https://api.anthropic.com/api/oauth/usage` with OAuth token
3. Caches full API response in `/tmp/claude-usage-cache.json`
4. **statusline.sh** reads cache and formats for display with progress bars
5. Shows: Plan, Session usage (5h window), Weekly usage (7d window), Extra credit usage

### Setup

Run these commands to enable:
```bash
launchctl load /Users/andrei/Library/LaunchAgents/com.claude.fetch-usage.plist
```

Check status:
```bash
launchctl list | grep fetch-usage
tail -f /tmp/claude-fetch-debug.txt
```

## Status Bar Setup

This project uses a custom status bar hook to display Claude usage information.

### Hooks

```json
{
  "description": "Display Claude usage in the status bar",
  "hooks": {
    "StatusBar": [
      {
        "type": "command",
        "command": "bash /Users/andrei/.claude/statusline.sh"
      }
    ]
  }
}
```

The status bar will display Claude's current usage with:
- **Plan & Model**: Shows your plan (Pro/Max) and current model
- **Ses**: Current session usage with progress bar and time until reset
- **Wek**: Weekly usage with progress bar and time until reset
- **Son**: Sonnet-only usage (Max plan only)
- **Blinking indicator**: Shows ⟳ for 5 seconds after fresh data fetch
- **Warning emoji**: Shows ⚠️ when usage is >= 95%

### How It Works

1. `fetch-usage.py` runs periodically, executes `/usage` command, and caches results
2. `statusline.sh` reads the cache and formats with colors, progress bars, and blinking effects
3. The status bar hook calls `statusline.sh` to display the formatted output

### Cache

- Data is cached in `/tmp/claude-usage-cache.json` (updated by `fetch-usage.py`)
- Status line reads cache to avoid running `/usage` on every refresh
- Debug logs available in `/tmp/claude-parse-debug.txt` and `/tmp/claude-fetch-debug.txt`
