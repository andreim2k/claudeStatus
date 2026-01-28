#!/bin/bash
input=$(cat)

# Color codes
RESET=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
BLINK=$'\e[5m'

# Colors
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
MAGENTA=$'\e[35m'
CYAN=$'\e[36m'
WHITE=$'\e[37m'
GRAY=$'\e[90m'

# Bright colors
BRIGHT_RED=$'\e[91m'
BRIGHT_GREEN=$'\e[92m'
BRIGHT_YELLOW=$'\e[93m'
BRIGHT_BLUE=$'\e[94m'
BRIGHT_MAGENTA=$'\e[95m'
BRIGHT_CYAN=$'\e[96m'
BRIGHT_WHITE=$'\e[97m'

# Core fields
MODEL=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
CTX_PERCENT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | awk '{printf "%.0f", $1}')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // ""' | sed "s|$HOME|~|")

# Function to generate progress bar
# Each square = 20%. Fills at 20%, 40%, 60%, 80%, 100%
# Pass "blink" as $2 to make squares blink when >= 95%
progress_bar() {
    local pct=$1
    local blink_mode=$2
    [ "$pct" -gt 100 ] && pct=100

    local blink_prefix=""
    [ "$blink_mode" = "blink" ] && blink_prefix="${BLINK}"

    local bar=""
    for ((i=1; i<=5; i++)); do
        local threshold=$((i * 20))
        if [ "$pct" -ge "$threshold" ]; then
            # Filled square (white bold - matches model color)
            bar="${bar}${blink_prefix}${WHITE}${BOLD}■${RESET}"
        else
            # Empty square (gray)
            bar="${bar}${blink_prefix}${GRAY}□${RESET}"
        fi
    done

    echo "$bar"
}

# Function to colorize percentage based on value with progress bar
# Blinks automatically when >= 95%
color_percentage() {
    local pct=$1
    local blink_arg=""

    # Enable blink for any percentage >= 95%
    if [ "$pct" -ge 95 ]; then
        blink_arg="blink"
    fi

    local bar=$(progress_bar "$pct" "$blink_arg")
    local pct_color=""

    if [ "$pct" -ge 80 ]; then
        pct_color="${BRIGHT_RED}${BOLD}${pct}%${RESET}"
    elif [ "$pct" -ge 60 ]; then
        pct_color="${BRIGHT_YELLOW}${BOLD}${pct}%${RESET}"
    elif [ "$pct" -ge 40 ]; then
        pct_color="${BRIGHT_YELLOW}${pct}%${RESET}"
    else
        pct_color="${BRIGHT_GREEN}${BOLD}${pct}%${RESET}"
    fi

    echo "${pct_color} ${bar}"
}

# Function to colorize time based on urgency
color_time() {
    local time_str=$1
    local window=$2  # "session" or "week"

    if [ -z "$time_str" ]; then
        echo ""
        return
    fi

    if [[ "$time_str" == "soon" ]]; then
        echo "${BRIGHT_RED}${BOLD}soon${RESET}"
        return
    fi

    # Extract numeric values
    if [[ "$time_str" =~ ([0-9]+)d ]]; then
        local days="${BASH_REMATCH[1]}"
        if [ "$window" = "week" ]; then
            if [ "$days" -ge 5 ]; then
                echo "${BRIGHT_GREEN}${time_str}${RESET}"
            elif [ "$days" -ge 2 ]; then
                echo "${BRIGHT_YELLOW}${time_str}${RESET}"
            else
                echo "${BRIGHT_YELLOW}${BOLD}${time_str}${RESET}"
            fi
        else
            echo "${BRIGHT_GREEN}${time_str}${RESET}"
        fi
    elif [[ "$time_str" =~ ([0-9]+)h ]]; then
        local hours="${BASH_REMATCH[1]}"
        if [ "$window" = "session" ]; then
            if [ "$hours" -ge 3 ]; then
                echo "${BRIGHT_GREEN}${time_str}${RESET}"
            elif [ "$hours" -ge 1 ]; then
                echo "${BRIGHT_YELLOW}${time_str}${RESET}"
            else
                echo "${BRIGHT_YELLOW}${BOLD}${time_str}${RESET}"
            fi
        else
            echo "${BRIGHT_YELLOW}${time_str}${RESET}"
        fi
    else
        # Minutes only
        echo "${BRIGHT_YELLOW}${BOLD}${time_str}${RESET}"
    fi
}

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

        # Times are already formatted as "0h25m" or "1d22h"
        SESSION_TIME="$SESSION_RESET_STR"
        WEEK_ALL_TIME="$WEEK_ALL_RESET_STR"
        WEEK_SONNET_TIME="$WEEK_SONNET_RESET_STR"

        # Colorize percentages and times
        SESSION_PCT_COLOR=$(color_percentage "${SESSION_PCT:-0}")
        WEEK_ALL_PCT_COLOR=$(color_percentage "${WEEK_ALL_PCT:-0}")
        WEEK_SONNET_PCT_COLOR=$(color_percentage "${WEEK_SONNET_PCT:-0}")

        SESSION_TIME_COLOR=$(color_time "$SESSION_TIME" "session")
        WEEK_ALL_TIME_COLOR=$(color_time "$WEEK_ALL_TIME" "week")
        WEEK_SONNET_TIME_COLOR=$(color_time "$WEEK_SONNET_TIME" "week")

        USAGE_PART="${BRIGHT_WHITE}${BOLD}S:${RESET} ${SESSION_PCT_COLOR} ${SESSION_TIME_COLOR} ${WHITE}|${RESET} ${BRIGHT_WHITE}${BOLD}W:${RESET} ${WEEK_ALL_PCT_COLOR} ${WEEK_ALL_TIME_COLOR}"

        # Only show Sonnet if model contains "Sonnet"
        if echo "$MODEL" | grep -qi "sonnet"; then
            USAGE_PART="${USAGE_PART} ${WHITE}|${RESET} ${BRIGHT_WHITE}${BOLD}So:${RESET} ${WEEK_SONNET_PCT_COLOR} ${WEEK_SONNET_TIME_COLOR}"
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
        GIT_STATUS="${GIT_STATUS}${BRIGHT_YELLOW}*${RESET}"
    fi
    if ! git --no-optional-locks diff --cached --quiet 2>/dev/null; then
        GIT_STATUS="${GIT_STATUS}${BRIGHT_GREEN}+${RESET}"
    fi
    if [ -n "$(git --no-optional-locks ls-files --others --exclude-standard 2>/dev/null)" ]; then
        GIT_STATUS="${GIT_STATUS}${BRIGHT_RED}?${RESET}"
    fi

    if [ -z "$GIT_STATUS" ]; then
        # Clean repo
        GIT_PART=" ${GRAY}|${RESET} ${BRIGHT_GREEN}${BOLD}${GIT_BRANCH}${RESET}"
    else
        GIT_PART=" ${GRAY}|${RESET} ${BRIGHT_CYAN}${BOLD}${GIT_BRANCH}${RESET}${GIT_STATUS}"
    fi
fi

# Colorize context percentage (blinks at 95%+)
CTX_PCT_COLOR=$(color_percentage "${CTX_PERCENT}")


# Colorize model name (always white, bold)
MODEL_COLOR="${WHITE}${BOLD}${MODEL}${RESET}"

echo "${WHITE}[${RESET}${MODEL_COLOR}${WHITE}]${RESET} ${WHITE}|${RESET} ${BRIGHT_WHITE}${BOLD}Ctx:${RESET} ${CTX_PCT_COLOR} ${WHITE}|${RESET} ${USAGE_PART}"
