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
        "command": "python3 /Users/andrei/Development/claudeStatus/fetch-usage.py"
      }
    ]
  }
}
```

The status bar will display Claude's current usage percentages for:
- **S**: Current session usage (5-hour window)
- **W**: Weekly usage (7-day window for all models)
- **So**: Sonnet-only usage (7-day window)

### Usage

The `fetch-usage.py` script automatically:
1. Runs the `/usage` command in Claude Code
2. Parses the output to extract usage percentages
3. Caches the data for quick status bar updates
4. Formats the output as `S:X% W:Y% So:Z%`

### Output Format

- `S:92% W:87% So:45%` - Shows all three usage metrics
- Data is cached in `/tmp/claude-usage-cache.json`
- Debug logs available in `/tmp/claude-parse-debug.txt` and `/tmp/claude-fetch-debug.txt`
