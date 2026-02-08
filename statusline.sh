#!/bin/bash

# Color codes
RESET=$'\e[0m'
BOLD=$'\e[1m'
BLINK=$'\e[5m'
NOBLINK=$'\e[25m'

# Bright colors
BRIGHT_RED=$'\e[91m'
BRIGHT_GREEN=$'\e[92m'
BRIGHT_YELLOW=$'\e[93m'
BRIGHT_WHITE=$'\e[97m'
WHITE=$'\e[37m'

# Function to generate progress bar with circles
progress_bar() {
    local pct=$1
    [ "$pct" -gt 100 ] && pct=100

    local bar=""
    for ((i=1; i<=5; i++)); do
        local threshold=$((i * 20))
        if [ "$pct" -ge "$threshold" ]; then
            bar="${bar}${WHITE}●${RESET}"
        else
            bar="${bar}${WHITE}○${RESET}"
        fi
    done
    echo "$bar"
}

# Function to colorize percentage with warning at 95%+
color_percentage() {
    local pct=$1
    local bar=$(progress_bar "$pct")
    local alert=""

    # Add warning indicator if >= 95%
    if [ "$pct" -ge 95 ]; then
        alert=" ${BRIGHT_RED}⚠️${RESET}"
    fi

    if [ "$pct" -ge 80 ]; then
        echo "${BRIGHT_RED}${BOLD}${pct}%${RESET} ${bar}${alert}"
    elif [ "$pct" -ge 60 ]; then
        echo "${BRIGHT_YELLOW}${BOLD}${pct}%${RESET} ${bar}${alert}"
    elif [ "$pct" -ge 40 ]; then
        echo "${BRIGHT_YELLOW}${pct}%${RESET} ${bar}${alert}"
    else
        echo "${BRIGHT_GREEN}${BOLD}${pct}%${RESET} ${bar}${alert}"
    fi
}

# Function to colorize time
color_time() {
    local time_str=$1
    local window=$2

    if [ -z "$time_str" ]; then
        return
    fi

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
        echo "${BRIGHT_YELLOW}${BOLD}${time_str}${RESET}"
    fi
}


# Read from cache
CACHE="/tmp/claude-usage-cache.json"
REFRESH_INDICATOR=""

if [ -f "$CACHE" ]; then
    # Check if cache was updated recently (within 5 seconds)
    TIMESTAMP=$(jq -r '.timestamp // 0' "$CACHE" 2>/dev/null)
    NOW=$(date +%s)
    TIME_DIFF=$((NOW - TIMESTAMP))

    if [ "$TIME_DIFF" -lt 5 ]; then
        REFRESH_INDICATOR="${BRIGHT_GREEN}🔄${RESET} "
    fi

    PLAN=$(jq -r '.plan // "Unknown"' "$CACHE" 2>/dev/null)
    MODEL_DISPLAY=$(jq -r '.model // "Unknown"' "$CACHE" 2>/dev/null)

    SESSION_PCT=$(jq -r '.five_hour.utilization // 0' "$CACHE" 2>/dev/null | cut -d. -f1)
    SESSION_TIME=$(jq -r '.five_hour.reset_time // ""' "$CACHE" 2>/dev/null)

    WEEK_ALL_PCT=$(jq -r '.seven_day.utilization // 0' "$CACHE" 2>/dev/null | cut -d. -f1)
    WEEK_ALL_TIME=$(jq -r '.seven_day.reset_time // ""' "$CACHE" 2>/dev/null)

    WEEK_SONNET_PCT=$(jq -r '.seven_day_sonnet.utilization // 0' "$CACHE" 2>/dev/null | cut -d. -f1)
    WEEK_SONNET_TIME=$(jq -r '.seven_day_sonnet.reset_time // ""' "$CACHE" 2>/dev/null)

    # Colorize
    SESSION_PCT_COLOR=$(color_percentage "${SESSION_PCT:-0}")
    WEEK_ALL_PCT_COLOR=$(color_percentage "${WEEK_ALL_PCT:-0}")
    WEEK_SONNET_PCT_COLOR=$(color_percentage "${WEEK_SONNET_PCT:-0}")

    SESSION_TIME_COLOR=$(color_time "$SESSION_TIME" "session")
    WEEK_ALL_TIME_COLOR=$(color_time "$WEEK_ALL_TIME" "week")
    WEEK_SONNET_TIME_COLOR=$(color_time "$WEEK_SONNET_TIME" "week")

    # Output with refresh indicator, plan and model
    USAGE="${REFRESH_INDICATOR}${WHITE}[${RESET}${BRIGHT_WHITE}${BOLD}${PLAN}${RESET}${WHITE}]${RESET} ${WHITE}[${RESET}${BRIGHT_CYAN}${BOLD}${MODEL_DISPLAY}${RESET}${WHITE}]${RESET} ${WHITE}|${RESET} ${BRIGHT_WHITE}${BOLD}Ses:${RESET} ${SESSION_PCT_COLOR} ${SESSION_TIME_COLOR} ${WHITE}|${RESET} ${BRIGHT_WHITE}${BOLD}Wek:${RESET} ${WEEK_ALL_PCT_COLOR} ${WEEK_ALL_TIME_COLOR}"

    # Show Sonnet usage only when:
    # 1. Sonnet model is active AND
    # 2. There's actual Sonnet data (Plan is Max)
    if echo "$MODEL_DISPLAY" | grep -qi "sonnet"; then
        if [ "$PLAN" = "Max" ] && [ -n "$WEEK_SONNET_TIME" ]; then
            USAGE="${USAGE} ${WHITE}|${RESET} ${BRIGHT_WHITE}${BOLD}Son:${RESET} ${WEEK_SONNET_PCT_COLOR} ${WEEK_SONNET_TIME_COLOR}"
        fi
    fi

    echo "$USAGE"
else
    echo "S:? | W:? | So:?"
fi
