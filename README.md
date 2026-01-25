# Claude Status

Custom statusline for Claude Code that displays real-time usage information.

## Features

- **Current session usage** (5-hour window) with time until reset
- **Current week usage** (all models) with time until reset
- **Current week Sonnet-only usage** (shown only when Sonnet model is selected)
- **Context percentage**
- **Current directory**
- **Git branch and status** (when in a git repository)

## Files

- `statusline.sh` - Main statusline script that displays usage data
- `fetch-usage.py` - Python script that fetches usage data from Claude CLI
- `com.claude.fetch-usage.plist` - LaunchAgent that runs fetch script every 5 minutes

## Installation

1. Copy `statusline.sh` to `~/.claude/statusline.sh`:
   ```bash
   cp statusline.sh ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Copy `fetch-usage.py` to `~/.claude/fetch-usage.py`:
   ```bash
   cp fetch-usage.py ~/.claude/fetch-usage.py
   chmod +x ~/.claude/fetch-usage.py
   ```

3. Install the LaunchAgent:
   ```bash
   cp com.claude.fetch-usage.plist ~/Library/LaunchAgents/
   launchctl load ~/Library/LaunchAgents/com.claude.fetch-usage.plist
   ```

4. Install pexpect (required for fetch-usage.py):
   ```bash
   pip3 install pexpect
   ```

## How It Works

1. The **LaunchAgent** runs `fetch-usage.py` every 5 minutes
2. `fetch-usage.py` spawns Claude CLI, runs `/usage`, and parses the output
3. Usage data is cached in `/tmp/claude-usage-cache.json`
4. `statusline.sh` reads from the cache and displays the data (called constantly by Claude Code)

## Requirements

- Claude Code CLI installed at `/Users/andrei/.local/bin/claude` (update path in fetch-usage.py if different)
- Python 3 with pexpect library
- macOS (uses launchd)

## Statusline Format

**Without git:**
```
[Model] | S:X% Xh | W:X% XdXh | So:X% XdXh | Ctx: X% | ~/path
```

**With git:**
```
[Model] | S:X% Xh | W:X% XdXh | So:X% XdXh | Ctx: X% | ~/path | branch*+?
```

Where:
- `S:` = Session usage (5-hour window)
- `W:` = Week usage (all models)
- `So:` = Sonnet-only usage (only shown when using Sonnet)
- `*` = Modified files
- `+` = Staged files
- `?` = Untracked files

## License

MIT
