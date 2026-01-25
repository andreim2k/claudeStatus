#!/usr/bin/env python3
"""Fetch Claude usage data by running /usage command"""

import pexpect
import json
import re
import sys
import os

CACHE = "/tmp/claude-usage-cache.json"
CLAUDE = "/Users/andrei/.local/bin/claude"
DEBUG = "/tmp/claude-fetch-debug.txt"

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

            elif "all models" in content:
                pct_match = re.search(r'(\d+)%\s*used', content)
                time_match = re.search(r'Resets\s*([^(]+?)\s*\(', content)
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
            # Save to cache
            data = {
                "five_hour": {
                    "utilization": float(s),
                    "reset_time": s_time
                },
                "seven_day": {
                    "utilization": float(w),
                    "reset_time": w_time
                },
                "seven_day_sonnet": {
                    "utilization": float(so),
                    "reset_time": so_time
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
