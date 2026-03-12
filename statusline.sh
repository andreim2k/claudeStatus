#!/bin/bash

# Color codes - bright and vibrant
RESET=$'\e[0m'
BOLD=$'\e[1m'
# 256-color mode for maximum brightness
BRIGHT_RED=$'\e[38;5;196m'         # Vivid red
BRIGHT_GREEN=$'\e[38;5;46m'        # Vivid green
BRIGHT_YELLOW=$'\e[38;5;226m'      # Vivid yellow
BRIGHT_WHITE=$'\e[38;5;231m'       # Pure white
BRIGHT_CYAN=$'\e[38;5;51m'         # Vivid cyan
BRIGHT_MAGENTA=$'\e[38;5;201m'     # Vivid magenta
WHITE=$'\e[38;5;255m'              # Bright white

# Circle progress bar (5 circles, 20% each)
progress_bar() {
    local pct=$1
    [ "$pct" -gt 100 ] && pct=100

    local bar=""
    for ((i=1; i<=5; i++)); do
        local threshold=$((i * 20))
        if [ "$pct" -ge "$threshold" ]; then
            bar="${bar}${BOLD}${WHITE}●${RESET}"
        else
            bar="${bar}${WHITE}○${RESET}"
        fi
    done
    echo "$bar"
}

# Colorize percentage with circles
color_percentage() {
    local pct=$1
    local bar=$(progress_bar "$pct")
    local alert=""

    if [ "$pct" -ge 95 ]; then
        alert=" ${BRIGHT_RED}⚠️${RESET}"
        echo "${BRIGHT_RED}${BOLD}${pct}%${RESET} ${bar}${alert}"
    elif [ "$pct" -ge 80 ]; then
        echo "${BRIGHT_RED}${BOLD}${pct}%${RESET} ${bar}"
    elif [ "$pct" -ge 60 ]; then
        echo "${BRIGHT_YELLOW}${BOLD}${pct}%${RESET} ${bar}"
    else
        echo "${BRIGHT_GREEN}${BOLD}${pct}%${RESET} ${bar}"
    fi
}

# Get model from session logs
get_model() {
    LATEST_SESSION=$(ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -1)
    if [ -n "$LATEST_SESSION" ]; then
        RAW_MODEL=$(tail -20 "$LATEST_SESSION" 2>/dev/null | grep -o '"model":"[^"]*"' | tail -1 | cut -d'"' -f4)
        if [ -n "$RAW_MODEL" ]; then
            # Extract name and version: "claude-opus-4-6" -> "Opus 4.6", "claude-3-5-sonnet" -> "Sonnet 3.5"
            MODEL_NAME=$(echo "$RAW_MODEL" | sed 's/^claude-//' | sed 's/-[0-9][0-9]*-[0-9][0-9]*[0-9-]*$//' | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
            MODEL_VER=$(echo "$RAW_MODEL" | grep -oE '[0-9]+\.[0-9]+' | head -1)
            # Fall back to dash-separated version if no dot version found
            [ -z "$MODEL_VER" ] && MODEL_VER=$(echo "$RAW_MODEL" | grep -oE '[0-9]+-[0-9]+' | head -1 | tr '-' '.')
            if [ -n "$MODEL_NAME" ] && [ -n "$MODEL_VER" ]; then
                echo "$MODEL_NAME $MODEL_VER"
            fi
        fi
    fi
}

# Read from cache
CACHE="/tmp/claude-usage-cache.json"

if [ -f "$CACHE" ]; then
    # Extract all values in single jq call
    eval "$(jq -r '
      "TIMESTAMP=\(.timestamp // 0)",
      "PLAN=\(.plan // "Unknown")",
      "API_STATUS=\(.api_status // "unknown")",
      "LAST_API_SUCCESS=\(.last_api_success // 0)",
      "SESSION_PCT=\((.five_hour.utilization // null) | if . == null then "NA" else (. | floor | tostring) end)",
      "SESSION_TIME=\(.five_hour.reset_time // "N/A")",
      "WEEK_PCT=\((.seven_day.utilization // null) | if . == null then "NA" else (. | floor | tostring) end)",
      "WEEK_TIME=\(.seven_day.reset_time // "N/A")",
      "EXTRA_PCT=\((.extra_usage.utilization // null) | if . == null then "NA" else (. | floor | tostring) end)",
      "EXTRA_ENABLED=\(.extra_usage.enabled // false)",
      "EXTRA_INFO=\(.extra_usage.info // "N/A")",
      "CTX_PCT=\((.context_usage.utilization // 0) | floor)",
      "CTX_USED=\(.context_usage.tokens_used // 0)",
      "CTX_MAX=\(.context_usage.tokens_max // 200000)"
    ' "$CACHE" 2>/dev/null)"

    # Calculate time since last successful API call (not just fetch)
    CURRENT_TIME=$(date +%s)
    if [ "$LAST_API_SUCCESS" -gt 0 ]; then
      TIME_DIFF=$((CURRENT_TIME - LAST_API_SUCCESS))
    else
      TIME_DIFF=$((CURRENT_TIME - TIMESTAMP))
    fi

    if [ $TIME_DIFF -lt 60 ]; then
      REFRESH_TIME="${TIME_DIFF}s"
    elif [ $TIME_DIFF -lt 3600 ]; then
      REFRESH_TIME="$((TIME_DIFF / 60))m"
    else
      REFRESH_TIME="$((TIME_DIFF / 3600))h"
    fi

    if [ -n "$PLAN" ]; then
        # Get model
        MODEL=$(get_model)

        # Handle N/A values - show N/A when API failed or value is null
        if [ "$API_STATUS" = "error" ] || [ "$SESSION_PCT" = "NA" ]; then
            SESSION_COLOR="${BRIGHT_RED}N/A${RESET}"
        else
            SESSION_COLOR=$(color_percentage "${SESSION_PCT:-0}")
        fi

        if [ "$API_STATUS" = "error" ] || [ "$WEEK_PCT" = "NA" ]; then
            WEEK_COLOR="${BRIGHT_RED}N/A${RESET}"
        else
            WEEK_COLOR=$(color_percentage "${WEEK_PCT:-0}")
        fi

        if [ "$API_STATUS" = "error" ] || [ "$EXTRA_PCT" = "NA" ]; then
            EXTRA_COLOR="${BRIGHT_RED}N/A${RESET}"
        else
            EXTRA_COLOR=$(color_percentage "${EXTRA_PCT:-0}")
        fi

        CTX_COLOR=$(color_percentage "${CTX_PCT:-0}")

        # Build output
        OUTPUT="${BRIGHT_WHITE}${BOLD}[${PLAN}]${RESET}"

        # Add model if available
        if [ -n "$MODEL" ]; then
            OUTPUT="${OUTPUT} ${BRIGHT_CYAN}${MODEL}${RESET}"
        fi

        # Format context tokens in k (e.g., 31k/200k)
        CTX_USED_K=$(( ${CTX_USED:-0} / 1000 ))
        CTX_MAX_K=$(( ${CTX_MAX:-200000} / 1000 ))

        OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_WHITE}Ctx:${RESET} ${CTX_COLOR} ${BRIGHT_CYAN}${CTX_USED_K}k/${CTX_MAX_K}k${RESET}"

        if [ "$API_STATUS" = "error" ]; then
            OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_WHITE}Ses:${RESET} ${SESSION_COLOR}"
        else
            OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_WHITE}Ses:${RESET} ${SESSION_COLOR} ${BRIGHT_GREEN}${SESSION_TIME}${RESET}"
        fi

        if [ "$API_STATUS" = "error" ]; then
            OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_WHITE}Wek:${RESET} ${WEEK_COLOR}"
        else
            OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_WHITE}Wek:${RESET} ${WEEK_COLOR} ${BRIGHT_GREEN}${WEEK_TIME}${RESET}"
        fi

        # Add extra usage if enabled
        if [ "$EXTRA_ENABLED" = "true" ] && [ "$EXTRA_INFO" != "N/A" ] && [ -n "$EXTRA_INFO" ]; then
            OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_MAGENTA}Ext:${RESET} ${EXTRA_COLOR} ${BRIGHT_CYAN}${EXTRA_INFO}${RESET}"
        elif [ "$API_STATUS" = "error" ]; then
            OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_MAGENTA}Ext:${RESET} ${BRIGHT_RED}N/A${RESET}"
        fi

        # Add API status indicator and refresh time
        if [ "$API_STATUS" = "error" ]; then
            OUTPUT="${OUTPUT} ${BRIGHT_RED}⚠${RESET}"
        fi

        # Add refresh indicator - based on last successful API call
        if [ $TIME_DIFF -lt 120 ]; then
            REFRESH_COLOR="${BRIGHT_GREEN}"  # Fresh (< 2min) - API recently succeeded
        elif [ $TIME_DIFF -lt 240 ]; then
            REFRESH_COLOR="${BRIGHT_YELLOW}"  # Waiting (2-4min) - next API call expected
        else
            REFRESH_COLOR="${BRIGHT_RED}"  # Stale (> 4min) - API calls failing
        fi
        OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${REFRESH_COLOR}⟳${RESET} ${WHITE}${REFRESH_TIME}${RESET}"

        echo "$OUTPUT"
    else
        echo "S:? | W:? | E:?"
    fi
else
    echo "S:? | W:? | E:?"
fi
