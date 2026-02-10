#!/usr/bin/env python3
"""Fetch Claude usage data via Anthropic API"""

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
        capture_output=True, text=True, timeout=5
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


def get_model():
    """Read active model from Claude settings"""
    model_map = {
        "opus": "Opus 4.6",
        "sonnet": "Sonnet 4.5",
        "haiku": "Haiku 4.5",
    }
    settings_path = os.path.expanduser("~/.claude/settings.json")
    try:
        with open(settings_path) as f:
            model = json.load(f).get("model", "sonnet")
        return model_map.get(model.lower(), model.capitalize())
    except Exception:
        return "Sonnet 4.5"


def format_reset_time(iso_timestamp):
    """Convert ISO 8601 timestamp to relative time like '3h35m' or '6d15h'"""
    if not iso_timestamp:
        return ""

    ts = iso_timestamp.replace("Z", "+00:00")
    reset_date = datetime.datetime.fromisoformat(ts)
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
        model = get_model()
        debug_lines.append(f"Plan: {plan}, Model: {model}")

        # Call API via curl (avoids Python SSL cert issues on macOS)
        result = subprocess.run(
            ["curl", "-s", "--max-time", "10",
             "-H", f"Authorization: Bearer {creds['access_token']}",
             "-H", "anthropic-beta: oauth-2025-04-20",
             "https://api.anthropic.com/api/oauth/usage"],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode != 0:
            debug_lines.append(f"curl failed: {result.stderr}")
            return False

        api_data = json.loads(result.stdout)

        debug_lines.append(f"API response: {json.dumps(api_data, indent=2)}")

        # Parse response
        five_hour = api_data.get("five_hour") or {}
        seven_day = api_data.get("seven_day") or {}
        seven_day_sonnet = api_data.get("seven_day_sonnet") or {}

        s = int(five_hour.get("utilization", 0))
        w = int(seven_day.get("utilization", 0))
        so = int(seven_day_sonnet.get("utilization", 0))

        s_time = format_reset_time(five_hour.get("resets_at"))
        w_time = format_reset_time(seven_day.get("resets_at"))
        so_time = format_reset_time(seven_day_sonnet.get("resets_at"))

        # Write cache
        data = {
            "timestamp": int(time.time()),
            "plan": plan,
            "model": model,
            "five_hour": {
                "utilization": float(s),
                "reset_time": s_time,
            },
            "seven_day": {
                "utilization": float(w),
                "reset_time": w_time,
            },
            "seven_day_sonnet": {
                "utilization": float(so),
                "reset_time": so_time,
            },
        }

        with open(CACHE, "w") as f:
            json.dump(data, f)

        print(f"S:{s}% W:{w}% So:{so}%")
        return True

    except Exception as e:
        debug_lines.append(f"Error: {e}")
    finally:
        with open(DEBUG, "w") as f:
            f.write("\n".join(debug_lines) + "\n")

    return False


if __name__ == "__main__":
    fetch_usage()
