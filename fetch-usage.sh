#!/bin/bash
# Fetch usage by running claude /usage command

CACHE="/tmp/claude-usage-cache.json"
OUT="/tmp/claude-usage-output.txt"
DEBUG="/tmp/claude-parse-debug.txt"
LOCK="/tmp/claude-fetch-usage.lock"

# Prevent overlapping runs
if [ -f "$LOCK" ]; then
    pid=$(cat "$LOCK")
    if kill -0 "$pid" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$LOCK"
trap "rm -f $LOCK" EXIT

cd "$HOME"

# Format time: "5pm" or "5:30pm" -> "Xh Ym", "Jan 28 at 5pm" -> "Xd Yh"
format_time() {
    local t="$1"
    local now_ts=$(date +%s)

    # Handle "X:XXpm" or "Xpm" format (today)
    if [[ "$t" =~ ^([0-9]+):?([0-9]*)(am|pm)$ ]]; then
        local hour="${BASH_REMATCH[1]}"
        local min="${BASH_REMATCH[2]:-0}"
        local ampm="${BASH_REMATCH[3]}"
        [[ "$ampm" == "pm" && "$hour" != "12" ]] && hour=$((hour + 12))
        [[ "$ampm" == "am" && "$hour" == "12" ]] && hour=0

        local target_ts=$(date -v${hour}H -v${min}M -v0S +%s 2>/dev/null)
        [[ "$target_ts" -le "$now_ts" ]] && target_ts=$((target_ts + 86400))

        local diff=$((target_ts - now_ts))
        local hours=$((diff / 3600))
        local mins=$(((diff % 3600) / 60))
        echo "${hours}h${mins}m"
        return
    fi

    # Handle "Mon DD at X:XXpm" format
    if [[ "$t" =~ ^([A-Za-z]+)\ +([0-9]+)\ +at\ +([0-9]+):?([0-9]*)(am|pm)$ ]]; then
        local month="${BASH_REMATCH[1]}"
        local day="${BASH_REMATCH[2]}"
        local hour="${BASH_REMATCH[3]}"
        local min="${BASH_REMATCH[4]:-0}"
        local ampm="${BASH_REMATCH[5]}"

        [[ "$ampm" == "pm" && "$hour" != "12" ]] && hour=$((hour + 12))
        [[ "$ampm" == "am" && "$hour" == "12" ]] && hour=0

        local target_ts=$(date -j -f "%b %d %H %M" "$month $day $hour $min" +%s 2>/dev/null)
        [[ -z "$target_ts" ]] && { echo "$t"; return; }
        [[ "$target_ts" -le "$now_ts" ]] && target_ts=$(date -j -v+1y -f "%b %d %H %M" "$month $day $hour $min" +%s 2>/dev/null)

        local diff=$((target_ts - now_ts))
        local total_hours=$((diff / 3600))
        local days=$((total_hours / 24))
        local hours=$((total_hours % 24))

        if [[ "$days" -gt 0 ]]; then
            echo "${days}d${hours}h"
        else
            local mins=$(((diff % 3600) / 60))
            echo "${hours}h${mins}m"
        fi
        return
    fi

    echo "$t"
}

# Run claude with /usage command via expect
expect << 'EXP' > "$OUT" 2>&1
log_user 1
set timeout 15
spawn /Users/andrei/.local/bin/claude --dangerously-skip-permissions
expect "Try"
sleep 0.5
send "/usage"
sleep 0.5
send "\r"
expect {
    "Loading" {
        set timeout 10
        expect {
            "Sonnet only" {
                expect {
                    "Esc to cancel" { }
                    timeout { }
                }
            }
            timeout { }
        }
    }
    "Sonnet only" { sleep 2 }
    timeout { }
}
exec kill -9 [exp_pid]
EXP

# Parse output
if [ -f "$OUT" ]; then
    # Strip ANSI codes
    clean=$(cat "$OUT" | sed $'s/\x1b\[[0-9;]*[a-zA-Z]//g' | sed $'s/\x1b\[[?0-9;]*[hl]//g')

    echo "=== CLEANED ===" > "$DEBUG"
    echo "$clean" >> "$DEBUG"

    # Get percentages from "X% used" or "X%used" (space optional)
    pcts=$(echo "$clean" | grep -oE "[0-9]+%\s*used")
    s=$(echo "$pcts" | sed -n 1p | grep -oE "^[0-9]+")
    w=$(echo "$pcts" | sed -n 2p | grep -oE "^[0-9]+")
    so=$(echo "$pcts" | sed -n 3p | grep -oE "^[0-9]+")

    # Get reset times - handles all formats:
    # "Reses8pm", "Resets 5:30pm", "Resets Feb 1 at 8:59am", etc.
    # Pattern: Rese(s/ts) followed by optional space, then time or "Mon DD at time"
    all_resets=$(echo "$clean" | grep -oE "Rese[ts]*\s*([A-Z][a-z]+\s+[0-9]+\s+at\s+)?[0-9]+:?[0-9]*(am|pm)" | sed 's/Rese[ts]* *//')

    # Session (1st), Week all (2nd), Sonnet (3rd)
    s_raw=$(echo "$all_resets" | sed -n 1p)
    w_raw=$(echo "$all_resets" | sed -n 2p)
    so_raw=$(echo "$all_resets" | sed -n 3p)

    s_time=$(format_time "$s_raw")
    w_time=$(format_time "$w_raw")
    so_time=$(format_time "$so_raw")

    echo "" >> "$DEBUG"
    echo "=== PARSED ===" >> "$DEBUG"
    echo "S:${s:-0}% ($s_time) W:${w:-0}% ($w_time) So:${so:-0}% ($so_time)" >> "$DEBUG"

    if [ -n "$s" ] || [ -n "$w" ]; then
        cat > "$CACHE" << EOF
{"five_hour":{"utilization":${s:-0}.0,"reset_time":"$s_time"},"seven_day":{"utilization":${w:-0}.0,"reset_time":"$w_time"},"seven_day_sonnet":{"utilization":${so:-0}.0,"reset_time":"$so_time"}}
EOF
        echo "S:${s:-0}% ($s_time) | W:${w:-0}% ($w_time) | So:${so:-0}% ($so_time)"
        exit 0
    fi
fi

echo "Failed to parse" >&2
exit 1
