#!/usr/bin/env python3
"""Fetch Claude usage data by running /usage command"""

import pexpect
import json
import re
import sys
import os
import time
import datetime
from datetime import timedelta

CACHE = "/tmp/claude-usage-cache.json"
CLAUDE = "/Users/andrei/.local/bin/claude"
DEBUG = "/tmp/claude-fetch-debug.txt"

def format_time(time_str):
    """Convert reset time like '6pm' or 'Feb 10 at 6pm' to time remaining like '5h59m'"""
    if not time_str:
        return ""

    # Add spaces if concatenated (e.g., "Feb10at10am" -> "Feb 10 at 10am")
    time_str = re.sub(r'([A-Za-z]+)(\d+)(at)(\d+)', r'\1 \2 \3 \4', time_str)

    now = datetime.datetime.now()

    # Handle "Xpm" or "X:XXpm" format (today or next occurrence)
    match = re.match(r'^(\d{1,2}):?(\d{0,2})(am|pm)$', time_str)
    if match:
        hour = int(match.group(1))
        minute = int(match.group(2) or '0')
        ampm = match.group(3)

        if ampm == 'pm' and hour != 12:
            hour += 12
        elif ampm == 'am' and hour == 12:
            hour = 0

        target = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if target <= now:
            target += timedelta(days=1)

        diff = target - now
        hours = diff.seconds // 3600
        minutes = (diff.seconds % 3600) // 60

        if diff.days > 0:
            return f"{diff.days}d{hours}h"
        elif hours > 0:
            return f"{hours}h{minutes}m"
        else:
            return f"{minutes}m"

    # Handle "Mon DD at Xpm" format
    match = re.match(r'^([A-Za-z]+)\s+(\d{1,2})\s+at\s+(\d{1,2}):?(\d{0,2})(am|pm)$', time_str)
    if match:
        month_str = match.group(1)
        day = int(match.group(2))
        hour = int(match.group(3))
        minute = int(match.group(4) or '0')
        ampm = match.group(5)

        if ampm == 'pm' and hour != 12:
            hour += 12
        elif ampm == 'am' and hour == 12:
            hour = 0

        try:
            target = datetime.datetime.strptime(f"{month_str} {day} {hour}:{minute}", "%b %d %H:%M")
            target = target.replace(year=now.year)
            if target <= now:
                target = target.replace(year=now.year + 1)

            diff = target - now
            days = diff.days
            hours = diff.seconds // 3600

            if days > 0:
                return f"{days}d{hours}h"
            elif hours > 0:
                minutes = (diff.seconds % 3600) // 60
                return f"{hours}h{minutes}m"
            else:
                minutes = (diff.seconds % 3600) // 60
                return f"{minutes}m"
        except:
            pass

    return time_str

def fetch_usage():
    all_output = ""
    debug_file = None
    try:
        debug_file = open(DEBUG, 'w')
        os.chdir(os.path.expanduser("~"))

        # Spawn Claude
        child = pexpect.spawn(CLAUDE, timeout=15, encoding='utf-8')
        child.logfile = debug_file

        # Wait for trust dialog then press Enter
        child.expect([pexpect.TIMEOUT], timeout=2)
        all_output += child.before or ''
        child.send('\r')  # Carriage return to accept trust

        # Wait for main screen
        child.expect([pexpect.TIMEOUT], timeout=2)
        all_output += child.before or ''

        # Send /usage command
        child.send('/usage')
        child.expect([pexpect.TIMEOUT], timeout=1)
        all_output += child.before or ''

        # Press Enter to execute
        child.send('\r')

        # Wait for the FULL usage data to load - wait for "Esc to cancel" which appears at the end
        try:
            child.expect(['Esc to cancel', pexpect.TIMEOUT], timeout=5)
            all_output += child.before or ''
            all_output += child.after if child.after != pexpect.TIMEOUT else ''
        except:
            pass

        # Wait just a tiny bit more to ensure everything is rendered
        child.expect([pexpect.TIMEOUT], timeout=1)
        all_output += child.before or ''

        # Exit Claude
        child.sendcontrol('c')
        try:
            child.expect([pexpect.EOF, pexpect.TIMEOUT], timeout=2)
        except:
            pass
        child.close()

        # Close debug file
        if debug_file:
            debug_file.close()
            debug_file = None

        # Strip ANSI codes
        clean = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', all_output)
        clean = re.sub(r'\x1b\[\?[0-9;]*[hl]', '', clean)
        clean = re.sub(r'\x1b\][^\x07]*\x07', '', clean)  # OSC sequences
        clean = re.sub(r'\x1b[<>].*?u', '', clean)  # Other escape sequences

        # Write cleaned output for debugging
        with open('/tmp/claude-parse-debug.txt', 'w') as f:
            f.write(f"=== CLEANED OUTPUT ===\n{clean}\n\n")

        # Parse each section - split by section headers first
        # Handle corrupted text like "Curretsession" or "Current session"
        sections = re.split(r'(Curre[tn]*\s*(?:session|week))', clean)

        s, s_time, w, w_time, so, so_time = 0, "", 0, "", 0, ""
        plan = "Unknown"
        model = "Unknown"

        # Detect plan type (Pro vs Max)
        if "Max" in clean:
            plan = "Max"
        elif "Pro" in clean:
            plan = "Pro"

        # Extract model info (e.g., "Sonnet4.5", "Haiku4.5", "Opus4.6")
        model_match = re.search(r'(Sonnet|Haiku|Opus)\s*(\d+\.?\d*)', clean, re.IGNORECASE)
        if model_match:
            model_name = model_match.group(1).capitalize()
            model_version = model_match.group(2)
            model = f"{model_name} {model_version}"

        with open('/tmp/claude-parse-debug.txt', 'a') as f:
            f.write(f"=== SECTIONS ({len(sections)}) ===\n")
            for i, sec in enumerate(sections):
                f.write(f"Section {i}: {repr(sec[:100])}\n")

        for i in range(len(sections) - 1):
            header = sections[i]
            content = sections[i + 1]

            if "session" in header:
                pct_match = re.search(r'(\d+)%\s*used', content)
                time_match = re.search(r'(?:Resets|Reses|ts)\s*([^(\r\n]+?)\s*\(', content)
                with open('/tmp/claude-parse-debug.txt', 'a') as f:
                    f.write(f"=== SESSION PARSING ===\n")
                    f.write(f"Content: {repr(content[:100])}\n")
                    f.write(f"Pct match: {pct_match.group(1) if pct_match else 'NONE'}\n")
                    f.write(f"Time match: {time_match.group(1).strip() if time_match else 'NONE'}\n")
                if pct_match:
                    s = int(pct_match.group(1))
                if time_match:
                    s_time = time_match.group(1).strip()

            elif "all" in content and "models" in content:
                pct_match = re.search(r'(\d+)%\s*used', content)
                time_match = re.search(r'(?:Resets?|ts)\s*([^(\r\n]+?)\s*\(', content)
                if pct_match:
                    w = int(pct_match.group(1))
                if time_match:
                    w_time = time_match.group(1).strip()

            elif "Sonnet only" in content:
                pct_match = re.search(r'(\d+)%\s*used', content)
                time_match = re.search(r'Resets\s*([^(]+?)\s*\(', content)
                if pct_match:
                    so = int(pct_match.group(1))
                if time_match:
                    so_time = time_match.group(1).strip()

        with open('/tmp/claude-parse-debug.txt', 'a') as f:
            f.write(f"=== FINAL VALUES ===\n")
            f.write(f"s={s}, w={w}, so={so}\n")

        if s >= 0 and w >= 0:
            # Format times as "Xh Ym" or "Xd Yh"
            s_time_formatted = format_time(s_time)
            w_time_formatted = format_time(w_time)
            so_time_formatted = format_time(so_time)

            # Save to cache with timestamp
            import time as time_module
            data = {
                "timestamp": int(time_module.time()),
                "plan": plan,
                "model": model,
                "five_hour": {
                    "utilization": float(s),
                    "reset_time": s_time_formatted
                },
                "seven_day": {
                    "utilization": float(w),
                    "reset_time": w_time_formatted
                },
                "seven_day_sonnet": {
                    "utilization": float(so),
                    "reset_time": so_time_formatted
                }
            }

            with open(CACHE, 'w') as f:
                json.dump(data, f)

            print(f"S:{s}% W:{w}% So:{so}%")
            return True
        else:
            print(f"Could not parse usage data: s={s}, w={w}, so={so}", file=sys.stderr)
            print(f"Sections found: {len(sections)}", file=sys.stderr)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        if debug_file:
            debug_file.close()

    return False

if __name__ == '__main__':
    fetch_usage()
