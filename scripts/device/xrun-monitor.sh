#!/bin/sh
# ALSA Xrun Monitor — watch audio dropouts in real time
# Polls /proc/asound for xrun counters and prints deltas.
#
# Usage:
#   xrun-monitor.sh [interval_s] [duration_s]
#
#   interval_s: polling interval (default: 5)
#   duration_s: total run time, 0 = forever (default: 0)
#
# Output: timestamp, card, pcm, subdev, overrun_delta, underrun_delta, state

set -e

INTERVAL=${1:-5}
DURATION=${2:-0}

ts() { date +%s.%N 2>/dev/null || awk 'BEGIN{printf "%.6f", systime()}' 2>/dev/null || date +%s; }

# Build initial snapshot of xrun counters
declare_snapshot() {
    local prefix=$1
    for statusf in /proc/asound/card*/pcm*/sub*/status; do
        [ -f "$statusf" ] || continue
        local overrun=$(awk '/overrun/ {print $2}' "$statusf" 2>/dev/null || echo "0")
        local underrun=$(awk '/underrun/ {print $2}' "$statusf" 2>/dev/null || echo "0")
        eval "${prefix}_overrun_${statusf}=$overrun"
        eval "${prefix}_underrun_${statusf}=$underrun"
    done
}

echo "# Xrun Monitor — interval=${INTERVAL}s, duration=${DURATION}s (0=forever)"
echo "# Format: timestamp card pcm overrun_delta underrun_delta state"
echo "#"

start_ts=$(ts)
declare_snapshot prev

while true; do
    sleep "$INTERVAL"
    now=$(ts)

    printf "%.3f " "$now"
    sep=""

    for statusf in /proc/asound/card*/pcm*/sub*/status; do
        [ -f "$statusf" ] || continue

        local card=$(echo "$statusf" | sed 's|.*/card\([0-9]*\)/.*|\1|')
        local pcm=$(echo "$statusf" | sed 's|.*/pcm\([0-9a-zA-Z]*\)/.*|\1|')
        local sub=$(echo "$statusf" | sed 's|.*/sub\([0-9]*\)/.*|\1|')

        local orun1=$(awk '/overrun/ {print $2}' "$statusf" 2>/dev/null || echo "0")
        local urun1=$(awk '/underrun/ {print $2}' "$statusf" 2>/dev/null || echo "0")
        local state=$(awk '/state/ {print $2}' "$statusf" 2>/dev/null || echo "?")

        eval local orun0=\$prev_overrun_${statusf}
        eval local urun0=\$prev_underrun_${statusf}
        orun0=${orun0:-0}
        urun0=${urun0:-0}

        local od=$((orun1 - orun0))
        local ud=$((urun1 - urun0))

        if [ "$od" -gt 0 ] 2>/dev/null || [ "$ud" -gt 0 ] 2>/dev/null; then
            printf "${sep}card${card}/${pcm}/sub${sub}: overrun+%d underrun+%d [%s]" "$od" "$ud" "$state"
            sep=" | "
        fi

        eval "prev_overrun_${statusf}=$orun1"
        eval "prev_underrun_${statusf}=$urun1"
    done

    [ -z "$sep" ] && printf "no xruns"
    printf "\n"

    # Check duration
    [ "$DURATION" -gt 0 ] 2>/dev/null && {
        elapsed=$(awk "BEGIN{printf \"%d\", $now - $start_ts}")
        [ "$elapsed" -ge "$DURATION" ] && break
    }
done
