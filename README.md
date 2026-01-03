# Claude Status

A native macOS menu bar app that displays your Claude AI usage statistics in real-time.

![Menu Bar](https://img.shields.io/badge/macOS-Menu%20Bar%20App-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)

## Features

- **Real-time usage monitoring** - Shows remaining percentage for:
  - Current 5-hour session
  - Current week (all models)
  - Current week (Sonnet only)
- **Active model indicator** - Displays which model is currently selected (Opus/Sonnet/Haiku)
- **Session countdown** - Shows time remaining until session resets
- **Liquid glass themed popup** - Detailed stats with a modern UI
- **Auto-refresh** - Updates every 5 seconds

## Menu Bar Display

```
Ⓞ 51% >2h · 89% · 95%
```

- `Ⓞ` / `Ⓢ` / `Ⓗ` - Active model (Opus/Sonnet/Haiku)
- First percentage - Session remaining
- Time indicator - Hours until session reset (`>2h`, `<3h`, `45m`)
- Second percentage - Week remaining (all models)
- Third percentage - Week remaining (Sonnet)

## Requirements

- macOS 12.0+
- Claude Code CLI with valid authentication

## Building

```bash
./build.sh
```

## Installation

```bash
./install.sh                # Install to /Applications
./install_autostart.sh      # Start at login (optional)
```

To uninstall auto-start: `./uninstall_autostart.sh`

## How It Works

The app reads your Claude Code OAuth credentials from the macOS Keychain and queries the Anthropic API for usage data. It detects your active model from `~/.claude/settings.json`.

## License

MIT
