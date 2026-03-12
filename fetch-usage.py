#!/usr/bin/env python3
"""Fetch Claude usage data via Anthropic API and cache it"""

import json
import os
import subprocess
import sys
import time
import datetime

CACHE = "/tmp/claude-usage-cache.json"
DEBUG = "/tmp/claude-fetch-debug.txt"


def get_credentials():
    """Read OAuth credentials from macOS Keychain"""
    result = subprocess.run(
        ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if result.returncode != 0:
        return None

    creds = json.loads(result.stdout.strip())
    oauth = creds.get("claudeAiOauth", {})
    access_token = oauth.get("accessToken")
    if not access_token:
        return None

    return {
        "access_token": access_token,
        "expires_at": oauth.get("expiresAt", 0) / 1000,
        "plan": (oauth.get("subscriptionType") or "free").capitalize(),
    }


def format_reset_time(iso_timestamp):
    """Convert ISO 8601 timestamp to relative time like '3h35m' or '6d15h'"""
    if not iso_timestamp:
        return ""

    ts = iso_timestamp.replace("Z", "+00:00")
    try:
        reset_date = datetime.datetime.fromisoformat(ts)
    except:
        return ""

    now = datetime.datetime.now(datetime.timezone.utc)

    total_seconds = int((reset_date - now).total_seconds())
    if total_seconds <= 0:
        return "0m"

    days = total_seconds // 86400
    hours = (total_seconds % 86400) // 3600
    minutes = (total_seconds % 3600) // 60

    if days > 0:
        return f"{days}d{hours}h"
    elif hours > 0:
        return f"{hours}h{minutes}m"
    else:
        return f"{minutes}m"


def calculate_context_usage():
    """Calculate tokens used in current session"""
    try:
        import glob
        sessions_dir = os.path.expanduser("~/.claude/projects")

        # Find most recently modified .jsonl file
        latest_session = None
        latest_mtime = 0
        for jsonl_file in glob.glob(os.path.join(sessions_dir, "*/*.jsonl")):
            mtime = os.path.getmtime(jsonl_file)
            if mtime > latest_mtime:
                latest_mtime = mtime
                latest_session = jsonl_file

        if not latest_session:
            return 0, 200000

        total_tokens = 0
        with open(latest_session, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    # Check for message with usage data
                    if 'message' in entry and isinstance(entry['message'], dict):
                        msg = entry['message']
                        if 'usage' in msg and isinstance(msg['usage'], dict):
                            usage = msg['usage']
                            # Sum input and output tokens
                            total_tokens += usage.get('input_tokens', 0)
                            total_tokens += usage.get('output_tokens', 0)
                except:
                    pass

        return total_tokens, 200000
    except:
        return 0, 200000


def fetch_usage():
    """Fetch usage data from Anthropic API"""
    debug_lines = []

    try:
        creds = get_credentials()
        if not creds:
            debug_lines.append("No credentials found in Keychain")
            return False

        if time.time() > creds["expires_at"]:
            debug_lines.append("Token expired")
            return False

        plan = creds["plan"] if creds["plan"] in ("Pro", "Max") else "Free"
        debug_lines.append(f"Plan: {plan}")

        # Call API
        result = subprocess.run(
            [
                "curl",
                "-s",
                "--max-time",
                "10",
                "-H",
                f"Authorization: Bearer {creds['access_token']}",
                "-H",
                "anthropic-beta: oauth-2025-04-20",
                "https://api.anthropic.com/api/oauth/usage",
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode != 0:
            debug_lines.append(f"curl failed: {result.stderr}")
            return False

        # Parse JSON
        try:
            api_data = json.loads(result.stdout)
        except json.JSONDecodeError as jde:
            debug_lines.append(f"Failed to parse JSON response: {jde}")
            return False

        debug_lines.append(f"API response: {json.dumps(api_data, indent=2)}")

        # Calculate context usage
        ctx_used, ctx_max = calculate_context_usage()
        debug_lines.append(f"Context: {ctx_used} / {ctx_max} tokens")

        # Extract all relevant data
        five_hour = api_data.get("five_hour") or {}
        seven_day = api_data.get("seven_day") or {}
        extra_usage = api_data.get("extra_usage") or {}

        # Get all model-specific usage (opus, sonnet, etc.)
        model_usage = {}
        for key in ["seven_day_opus", "seven_day_sonnet", "seven_day_cowork"]:
            if api_data.get(key):
                model_usage[key] = api_data[key]

        five_h_util = int(five_hour.get("utilization", 0))
        seven_d_util = int(seven_day.get("utilization", 0))
        extra_util = int(extra_usage.get("utilization", 0)) if extra_usage else 0

        five_h_reset = format_reset_time(five_hour.get("resets_at", ""))
        seven_d_reset = format_reset_time(seven_day.get("resets_at", ""))

        # Format extra usage info
        extra_info = ""
        if extra_usage and extra_usage.get("is_enabled"):
            spent = extra_usage.get("used_credits", 0) / 100  # Convert to dollars
            limit = extra_usage.get("monthly_limit", 0) / 100
            extra_info = f"${spent:.2f} / ${limit:.2f}"

        # Write cache
        ctx_pct = int((ctx_used / ctx_max) * 100) if ctx_max > 0 else 0
        data = {
            "timestamp": int(time.time()),
            "plan": plan,
            "five_hour": {
                "utilization": five_h_util,
                "reset_time": five_h_reset,
            },
            "seven_day": {
                "utilization": seven_d_util,
                "reset_time": seven_d_reset,
            },
            "extra_usage": {
                "utilization": extra_util,
                "enabled": extra_usage.get("is_enabled", False),
                "info": extra_info,
            },
            "context_usage": {
                "utilization": ctx_pct,
                "tokens_used": ctx_used,
                "tokens_max": ctx_max,
            },
            "model_usage": model_usage,
        }

        with open(CACHE, "w") as f:
            json.dump(data, f)

        print(f"S:{five_h_util}% W:{seven_d_util}% E:{extra_util}%")
        return True

    except Exception as e:
        debug_lines.append(f"Error: {e}")
    finally:
        with open(DEBUG, "w") as f:
            f.write("\n".join(debug_lines) + "\n")

    return False


if __name__ == "__main__":
    fetch_usage()
