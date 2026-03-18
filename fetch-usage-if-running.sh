#!/bin/bash
# Wrapper script that only fetches usage if Claude Code is running

# Check if Claude Code process is running (look for claude CLI process)
if ps aux | grep -E '\sclaude\s*$' | grep -v grep > /dev/null 2>&1; then
    # Claude is running - fetch the usage
    /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 /Users/andrei/.claude/fetch-usage.py
else
    # Claude is not running - skip the fetch
    echo "Claude Code not running, skipping usage fetch" >> /tmp/claude-fetch-debug.txt
fi
