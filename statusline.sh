#!/bin/bash
input=$(cat)

# Core fields
MODEL=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
CTX_PERCENT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // ""' | sed "s|$HOME|~|")

# Parse human-readable reset time to epoch
parse_reset_time() {
    local reset_str="$1"
    if [ -z "$reset_str" ]; then return; fi

    local now_epoch=$(date +%s)
    local year=$(date +%Y)

    # Handle "2pm" or "11pm" or "1:59pm" format (time only, assume today or next occurrence)
    if [[ "$reset_str" =~ ^([0-9]+):?([0-9]*)(am|pm)$ ]]; then
        local hour="${BASH_REMATCH[1]}"
        local min="${BASH_REMATCH[2]:-0}"
        local ampm="${BASH_REMATCH[3]}"

        # Convert to 24-hour
        if [ "$ampm" = "pm" ] && [ "$hour" -ne 12 ]; then
            hour=$((hour + 12))
        elif [ "$ampm" = "am" ] && [ "$hour" -eq 12 ]; then
            hour=0
        fi

        # Try today first
        local today=$(date +%Y-%m-%d)
        local reset_epoch=$(date -j -f "%Y-%m-%d %H:%M" "$today $hour:$min" +%s 2>/dev/null)

        # If it's in the past, try tomorrow
        if [ -n "$reset_epoch" ] && [ "$reset_epoch" -le "$now_epoch" ]; then
            reset_epoch=$(date -j -v+1d -f "%Y-%m-%d %H:%M" "$today $hour:$min" +%s 2>/dev/null)
        fi

        echo "$reset_epoch"
        return
    fi

    # Handle "Jan 29 at 5pm" or "Jan 29 at 4:59pm" format
    if [[ "$reset_str" =~ ^([A-Za-z]+)\ ([0-9]+)\ at\ ([0-9]+):?([0-9]*)(am|pm)$ ]]; then
        local month="${BASH_REMATCH[1]}"
        local day="${BASH_REMATCH[2]}"
        local hour="${BASH_REMATCH[3]}"
        local min="${BASH_REMATCH[4]:-0}"
        local ampm="${BASH_REMATCH[5]}"

        # Convert to 24-hour
        if [ "$ampm" = "pm" ] && [ "$hour" -ne 12 ]; then
            hour=$((hour + 12))
        elif [ "$ampm" = "am" ] && [ "$hour" -eq 12 ]; then
            hour=0
        fi

        local reset_epoch=$(date -j -f "%b %d %Y %H:%M" "$month $day $year $hour:$min" +%s 2>/dev/null)
        echo "$reset_epoch"
        return
    fi
}

# Calculate time until epoch
time_until() {
    local reset_epoch="$1"
    if [ -z "$reset_epoch" ] || [ "$reset_epoch" = "0" ]; then return; fi

    local now_epoch=$(date +%s)
    local diff=$((reset_epoch - now_epoch))

    if [ $diff -le 0 ]; then
        echo "soon"
        return
    fi

    local days=$((diff / 86400))
    local hours=$(((diff % 86400) / 3600))
    local mins=$(((diff % 3600) / 60))

    if [ $days -gt 0 ]; then
        echo "${days}d${hours}h"
    elif [ $hours -gt 0 ]; then
        echo "${hours}h${mins}m"
    else
        echo "${mins}m"
    fi
}

# Usage data from cache
USAGE_PART=""
for CACHE in "/tmp/claude-usage-cache.json" "$HOME/.claude/usage-cache.json"; do
    if [ -f "$CACHE" ]; then
        SESSION_PCT=$(jq -r '.five_hour.utilization // 0' "$CACHE" 2>/dev/null | cut -d. -f1)
        SESSION_RESET_STR=$(jq -r '.five_hour.reset_time // ""' "$CACHE" 2>/dev/null)

        WEEK_ALL_PCT=$(jq -r '.seven_day.utilization // 0' "$CACHE" 2>/dev/null | cut -d. -f1)
        WEEK_ALL_RESET_STR=$(jq -r '.seven_day.reset_time // ""' "$CACHE" 2>/dev/null)

        WEEK_SONNET_PCT=$(jq -r '.seven_day_sonnet.utilization // 0' "$CACHE" 2>/dev/null | cut -d. -f1)
        WEEK_SONNET_RESET_STR=$(jq -r '.seven_day_sonnet.reset_time // ""' "$CACHE" 2>/dev/null)

        SESSION_RESET=$(parse_reset_time "$SESSION_RESET_STR")
        WEEK_ALL_RESET=$(parse_reset_time "$WEEK_ALL_RESET_STR")
        WEEK_SONNET_RESET=$(parse_reset_time "$WEEK_SONNET_RESET_STR")

        SESSION_TIME=$(time_until "$SESSION_RESET")
        WEEK_ALL_TIME=$(time_until "$WEEK_ALL_RESET")
        WEEK_SONNET_TIME=$(time_until "$WEEK_SONNET_RESET")

        USAGE_PART="S:${SESSION_PCT:-0}% ${SESSION_TIME} | W:${WEEK_ALL_PCT:-0}% ${WEEK_ALL_TIME}"

        # Only show Sonnet if model contains "Sonnet"
        if echo "$MODEL" | grep -qi "sonnet"; then
            USAGE_PART="${USAGE_PART} | So:${WEEK_SONNET_PCT:-0}% ${WEEK_SONNET_TIME}"
        fi

        break
    fi
done

# Git awareness
cd "$CURRENT_DIR" 2>/dev/null
GIT_PART=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    GIT_BRANCH=$(git --no-optional-locks branch --show-current 2>/dev/null)
    GIT_STATUS=""

    if ! git --no-optional-locks diff --quiet 2>/dev/null; then
        GIT_STATUS="${GIT_STATUS}*"
    fi
    if ! git --no-optional-locks diff --cached --quiet 2>/dev/null; then
        GIT_STATUS="${GIT_STATUS}+"
    fi
    if [ -n "$(git --no-optional-locks ls-files --others --exclude-standard 2>/dev/null)" ]; then
        GIT_STATUS="${GIT_STATUS}?"
    fi

    GIT_PART=" | ${GIT_BRANCH}${GIT_STATUS}"
fi

echo "[$MODEL] | $USAGE_PART | Ctx: ${CTX_PERCENT}% | $CURRENT_DIR$GIT_PART"
