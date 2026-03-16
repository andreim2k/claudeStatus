#!/usr/bin/env python3
"""Fetch Claude usage data via Anthropic API and cache it"""

import json
import os
import subprocess
import time
import datetime
import glob

CACHE = "/tmp/claude-usage-cache.json"
DEBUG = "/tmp/claude-fetch-debug.txt"

# Model context windows
# Haiku = 200k, all others (Sonnet/Opus) = 1M
MODEL_CONTEXT_WINDOWS = {
    "claude-haiku": 200000,          # All Haiku variants: 200k
}


def get_model_from_session():
    """Get the current model from the latest session log.
    Only reads model from entries with real usage data to avoid
    picking up model names from system/environment metadata.
    """
    try:
        sessions_dir = os.path.expanduser("~/.claude/projects")
        latest_session = max(
            glob.glob(os.path.join(sessions_dir, "*/*.jsonl")),
            key=os.path.getmtime,
            default=None
        )
        if not latest_session:
            return None

        with open(latest_session, 'r') as f:
            for line in reversed(list(f)):
                try:
                    entry = json.loads(line)
                    msg = entry.get('message')
                    if not isinstance(msg, dict):
                        continue
                    # Only trust model from entries with real usage data
                    if 'model' in msg and 'usage' in msg and isinstance(msg['usage'], dict):
                        return msg['model']
                except Exception:
                    pass
    except Exception:
        pass
    return None



def get_context_window():
    """Get context window size for the current model.
    Haiku = 200k, everything else (Sonnet/Opus) = 1M.
    """
    model = get_model_from_session()
    if not model:
        return 1000000  # Default: 1M

    # Haiku is the only model with 200k context
    if "haiku" in model.lower():
        return 200000

    return 1000000  # Sonnet, Opus and all others: 1M


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

    try:
        creds = json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        return None
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
    except Exception:
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
    ctx_max = get_context_window()

    try:
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
            return 0, ctx_max

        last_total_tokens = 0
        with open(latest_session, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    # Check for message with usage data
                    if 'message' in entry and isinstance(entry['message'], dict):
                        msg = entry['message']
                        if 'usage' in msg and isinstance(msg['usage'], dict):
                            usage = msg['usage']
                            # Sum all token types: input + cache read + cache creation + output
                            total = usage.get('input_tokens', 0)
                            total += usage.get('cache_read_input_tokens', 0)
                            total += usage.get('cache_creation_input_tokens', 0)
                            total += usage.get('output_tokens', 0)
                            last_total_tokens = total
                except Exception:
                    pass

        return last_total_tokens, ctx_max
    except Exception:
        return 0, ctx_max


def fetch_usage():
    """Fetch usage data from Anthropic API"""
    debug_lines = []
    api_success = False

    try:
        creds = get_credentials()
        if not creds:
            debug_lines.append("No credentials found in Keychain")
        elif creds["expires_at"] > 0 and time.time() > creds["expires_at"]:
            debug_lines.append("Token expired")
        else:
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
            if result.returncode == 0:
                try:
                    api_data = json.loads(result.stdout)
                    if "error" not in api_data:
                        debug_lines.append("API success")
                        api_success = True
                    else:
                        debug_lines.append(f"API error: {api_data['error']}")
                except json.JSONDecodeError as jde:
                    debug_lines.append(f"JSON parse error: {jde}")
            else:
                debug_lines.append(f"curl failed: {result.stderr}")

        # Always calculate context (local, not API-dependent)
        ctx_used, ctx_max = calculate_context_usage()
        # If tokens exceed detected max, it must be a 1M context model
        if ctx_used > ctx_max:
            ctx_max = 1000000

        # Load existing cache to preserve old values
        old_data = {}
        if os.path.exists(CACHE):
            try:
                with open(CACHE, "r") as f:
                    old_data = json.load(f)
            except Exception:
                pass

        # Add API data if successful, otherwise use N/A markers
        if api_success:
            five_hour = api_data.get("five_hour") or {}
            seven_day = api_data.get("seven_day") or {}
            extra_usage = api_data.get("extra_usage") or {}

            # Check if API response includes context_max — done BEFORE building cache
            if "context_max" in api_data:
                ctx_max = api_data["context_max"]
            elif "max_context_tokens" in api_data:
                ctx_max = api_data["max_context_tokens"]

        # Calculate ctx_pct AFTER ctx_max may have been updated by API
        ctx_pct = int((ctx_used / ctx_max) * 100) if ctx_max > 0 else 0
        debug_lines.append(f"Context: {ctx_used} / {ctx_max} tokens ({ctx_pct}%)")

        # Build new cache data — ctx_max is now final
        data = {
            "timestamp": int(time.time()),
            "plan": old_data.get("plan", "Unknown"),
            "last_api_success": int(time.time()) if api_success else old_data.get("last_api_success", 0),
            "api_status": "success" if api_success else "error",
            "context_usage": {
                "utilization": ctx_pct,
                "tokens_used": ctx_used,
                "tokens_max": ctx_max,
            },
        }

        if api_success:
            five_h_util = int(five_hour.get("utilization", 0))
            seven_d_util = int(seven_day.get("utilization", 0))
            extra_util = int(extra_usage.get("utilization", 0)) if extra_usage else 0

            five_h_reset = format_reset_time(five_hour.get("resets_at", ""))
            seven_d_reset = format_reset_time(seven_day.get("resets_at", ""))

            extra_info = ""
            if extra_usage and extra_usage.get("is_enabled"):
                spent = extra_usage.get("used_credits", 0) / 100
                limit = extra_usage.get("monthly_limit", 0) / 100
                extra_info = f"${spent:.2f} / ${limit:.2f}"

            data["plan"] = plan
            data["five_hour"] = {
                "utilization": five_h_util,
                "reset_time": five_h_reset,
            }
            data["seven_day"] = {
                "utilization": seven_d_util,
                "reset_time": seven_d_reset,
            }
            data["extra_usage"] = {
                "utilization": extra_util,
                "enabled": extra_usage.get("is_enabled", False),
                "info": extra_info,
            }
        else:
            # API failed - preserve old values or mark as N/A
            data["five_hour"] = old_data.get("five_hour", {
                "utilization": None,
                "reset_time": "N/A",
            })
            data["seven_day"] = old_data.get("seven_day", {
                "utilization": None,
                "reset_time": "N/A",
            })
            data["extra_usage"] = old_data.get("extra_usage", {
                "utilization": None,
                "enabled": False,
                "info": "N/A",
            })

        # Write cache
        with open(CACHE, "w") as f:
            json.dump(data, f)

        return api_success

    except Exception as e:
        debug_lines.append(f"Error: {e}")
    finally:
        with open(DEBUG, "a") as f:
            f.write(f"[{datetime.datetime.now():%Y-%m-%d %H:%M:%S}]\n")
            f.write("\n".join(debug_lines) + "\n")

    return False


if __name__ == "__main__":
    fetch_usage()
