# Claude Code Configuration

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
        "command": "bash /Users/andrei/Development/claudeStatus/statusline.sh"
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
