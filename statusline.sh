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
            # Extract name and version: "claude-opus-4-6" -> "Opus 4.6"
            MODEL_NAME=$(echo "$RAW_MODEL" | sed 's/^claude-//' | sed 's/-[0-9].*//' | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
            MODEL_VER=$(echo "$RAW_MODEL" | grep -oE '[0-9]+-[0-9]+' | head -1 | tr '-' '.')
            if [ -n "$MODEL_NAME" ] && [ -n "$MODEL_VER" ]; then
                echo "$MODEL_NAME $MODEL_VER"
            fi
        fi
    fi
}

# Get context window for model
get_context_window() {
    local model=$1
    case "$model" in
        *Opus*)
            echo "200k"
            ;;
        *Sonnet*)
            echo "200k"
            ;;
        *Haiku*)
            echo "200k"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Read from cache
CACHE="/tmp/claude-usage-cache.json"

if [ -f "$CACHE" ]; then
    CACHE_DATA=$(jq -r '
        .timestamp // 0,
        .plan // "Unknown",
        .five_hour.utilization // 0,
        .five_hour.reset_time // "",
        .seven_day.utilization // 0,
        .seven_day.reset_time // "",
        .extra_usage.utilization // 0,
        .extra_usage.enabled // false,
        .extra_usage.info // "",
        .context_usage.utilization // 0,
        .context_usage.tokens_used // 0,
        .context_usage.tokens_max // 200000
    ' "$CACHE" 2>/dev/null)

    if [ $? -eq 0 ]; then
        TIMESTAMP=$(echo "$CACHE_DATA" | sed -n '1p')
        PLAN=$(echo "$CACHE_DATA" | sed -n '2p')
        SESSION_PCT=$(echo "$CACHE_DATA" | sed -n '3p' | cut -d. -f1)
        SESSION_TIME=$(echo "$CACHE_DATA" | sed -n '4p')
        WEEK_PCT=$(echo "$CACHE_DATA" | sed -n '5p' | cut -d. -f1)
        WEEK_TIME=$(echo "$CACHE_DATA" | sed -n '6p')
        EXTRA_PCT=$(echo "$CACHE_DATA" | sed -n '7p' | cut -d. -f1)
        EXTRA_ENABLED=$(echo "$CACHE_DATA" | sed -n '8p')
        EXTRA_INFO=$(echo "$CACHE_DATA" | sed -n '9p')
        CTX_PCT=$(echo "$CACHE_DATA" | sed -n '10p' | cut -d. -f1)
        CTX_USED=$(echo "$CACHE_DATA" | sed -n '11p')
        CTX_MAX=$(echo "$CACHE_DATA" | sed -n '12p')

        # Get model and context window
        MODEL=$(get_model)
        CTX=""
        if [ -n "$MODEL" ]; then
            CTX=$(get_context_window "$MODEL")
        fi

        # Color percentages
        SESSION_COLOR=$(color_percentage "${SESSION_PCT:-0}")
        WEEK_COLOR=$(color_percentage "${WEEK_PCT:-0}")
        EXTRA_COLOR=$(color_percentage "${EXTRA_PCT:-0}")
        CTX_COLOR=$(color_percentage "${CTX_PCT:-0}")

        # Build output
        OUTPUT="${BRIGHT_WHITE}${BOLD}[${PLAN}]${RESET}"

        # Add model if available
        if [ -n "$MODEL" ]; then
            OUTPUT="${OUTPUT} ${BRIGHT_CYAN}${MODEL}${RESET}"
        fi

        # Format context tokens in k (e.g., 31k/200k)
        CTX_USED_K=$((CTX_USED / 1000))
        CTX_MAX_K=$((CTX_MAX / 1000))

        OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_WHITE}Ctx:${RESET} ${CTX_COLOR} ${BRIGHT_CYAN}${CTX_USED_K}k/${CTX_MAX_K}k${RESET}"
        OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_WHITE}Ses:${RESET} ${SESSION_COLOR} ${BRIGHT_GREEN}${SESSION_TIME}${RESET}"
        OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_WHITE}Wek:${RESET} ${WEEK_COLOR} ${BRIGHT_GREEN}${WEEK_TIME}${RESET}"

        # Add extra usage if enabled
        if [ "$EXTRA_ENABLED" = "true" ] && [ -n "$EXTRA_INFO" ]; then
            OUTPUT="${OUTPUT} ${WHITE}|${RESET} ${BRIGHT_MAGENTA}Ext:${RESET} ${EXTRA_COLOR} ${BRIGHT_CYAN}${EXTRA_INFO}${RESET}"
        fi

        echo "$OUTPUT"
    else
        echo "S:? | W:? | E:?"
    fi
else
    echo "S:? | W:? | E:?"
fi
