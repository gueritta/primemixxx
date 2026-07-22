#!/bin/sh
# CPU Latency Benchmark — cyclictest equivalent using /proc/stat + busy-loop
# Measures worst-case scheduling latency by tracking how long it takes
# for the CPU to return to userspace after a sleep interval.
#
# Method:
#   1. Record /proc/stat CPU idle ticks
#   2. Sleep for a target interval
#   3. On wake, compute actual elapsed time vs expected
#   4. The delta (actual - expected) is the scheduling latency
#   5. Track min, max, avg, and percentile over N iterations
#
# Usage:
#   cpu-latency.sh [target_us] [iterations] [affinity_mask]
#
#   target_us:    target sleep in microseconds (default: 1000 = 1ms)
#   iterations:   number of samples (default: 1000)
#   affinity_mask: CPU affinity in hex, e.g. 0x04 for CPU 2 (default: no change)
#
# Output:
#   Min, max, avg latency in microseconds, plus latency histogram

set -e

TARGET_US=${1:-1000}
ITERATIONS=${2:-1000}
AFFINITY=${3:-}

[ "$AFFINITY" ] && taskset -p "$AFFINITY" $$ > /dev/null 2>&1 || true

# --- BusyBox-compatible microsecond helpers ---

# Check if usleep accepts fractional seconds (BusyBox: usleep takes microseconds)
# We'll use a calibration loop to measure clock resolution

# Get current time in microseconds (from /proc/uptime or monotonic clock)
# /proc/uptime: seconds.centiseconds, we convert to us
clock_us() {
    read -r up idle < /proc/uptime
    local sec=${up%.*}
    local frac=${up#*.}
    frac=${frac%% *}
    # Convert to microseconds: sec*1e6 + centisec*10000
    echo "$(( sec * 1000000 + $(printf "%.6s" "${frac}000000") * 10 ))"
}

# --- Calibration: measure minimum sleep granularity ---
# On PREEMPT_RT with HZ=1000, sleep resolution should be ~1ms
# BusyBox usleep takes microseconds
calibrate_sleep() {
    local total=0
    local loops=100
    local i=0
    while [ $i -lt $loops ]; do
        local t0=$(clock_us)
        usleep 1000 2>/dev/null || sleep 0.001 2>/dev/null || sleep 1
        local t1=$(clock_us)
        local delta=$((t1 - t0))
        total=$((total + delta))
        i=$((i + 1))
    done
    echo $((total / loops))
}

echo "# CPU Latency Benchmark"
echo "# Target: ${TARGET_US} us, Iterations: ${ITERATIONS}"
[ "$AFFINITY" ] && echo "# CPU affinity: $AFFINITY"
CAL=$(calibrate_sleep)
echo "# Sleep calibration (avg 1ms sleep): ${CAL} us"
echo ""

# --- Main measurement loop ---
MIN=999999999
MAX=0
SUM=0
SQR=0
LATENCIES=""

# Pre-allocate latency bucket array (0-50us, 50-100, 100-200, 200-500, 500-1k, 1k-5k, 5k+)
B0=0; B1=0; B2=0; B3=0; B4=0; B5=0; B6=0

i=0
while [ $i -lt "$ITERATIONS" ]; do
    t0=$(clock_us)

    # Sleep for target microseconds
    usleep "$TARGET_US" 2>/dev/null || {
        # Fallback: busy-wait using /proc/uptime polling (wasteful but works)
        local target=$((t0 + TARGET_US))
        while true; do
            local now=$(clock_us)
            [ "$now" -ge "$target" ] && break
        done
    }

    t1=$(clock_us)
    latency=$((t1 - t0 - TARGET_US))

    # Track min/max
    [ "$latency" -lt "$MIN" ] && MIN=$latency
    [ "$latency" -gt "$MAX" ] && MAX=$latency
    SUM=$((SUM + latency))
    SQR=$((SQR + latency * latency))

    # Histogram
    if [ "$latency" -le 50 ]; then B0=$((B0 + 1))
    elif [ "$latency" -le 100 ]; then B1=$((B1 + 1))
    elif [ "$latency" -le 200 ]; then B2=$((B2 + 1))
    elif [ "$latency" -le 500 ]; then B3=$((B3 + 1))
    elif [ "$latency" -le 1000 ]; then B4=$((B4 + 1))
    elif [ "$latency" -le 5000 ]; then B5=$((B5 + 1))
    else B6=$((B6 + 1))
    fi

    # Collect latencies for percentile calculation (sample every 10th)
    if [ $((i % 10)) = 0 ]; then
        LATENCIES="$LATENCIES $latency"
    fi

    # Progress indicator
    [ $((i % 100)) = 0 ] && printf "." >&2

    i=$((i + 1))
done
echo "" >&2

# --- Statistics ---
AVG=$((SUM / ITERATIONS))
# Standard deviation
if [ "$ITERATIONS" -gt 1 ]; then
    VAR=$(( (SQR - SUM * SUM / ITERATIONS) / (ITERATIONS - 1) ))
    [ "$VAR" -lt 0 ] && VAR=0
    # Integer sqrt approximation
    STDDEV=$(awk "BEGIN{printf \"%d\", sqrt($VAR)}")
else
    STDDEV=0
fi

# Percentiles from collected samples
pct() {
    local pct_num=$1
    local sorted=$(echo "$LATENCIES" | tr ' ' '\n' | sort -n)
    local count=$(echo "$sorted" | wc -l)
    [ "$count" = 0 ] && { echo 0; return; }
    local idx=$(( count * pct_num / 100 + 1 ))
    [ "$idx" -gt "$count" ] && idx=$count
    echo "$sorted" | sed -n "${idx}p"
}

P50=$(pct 50)
P90=$(pct 90)
P95=$(pct 95)
P99=$(pct 99)
P999=$(pct 999)

# --- Output ---
echo "=== Results: ${ITERATIONS} iterations, target=${TARGET_US} us ==="
echo ""
echo "  Min:     ${MIN} us"
echo "  Max:     ${MAX} us"
echo "  Avg:     ${AVG} us"
echo "  StdDev:  ${STDDEV} us"
echo ""
echo "  P50:     ${P50} us"
echo "  P90:     ${P90} us"
echo "  P95:     ${P95} us"
echo "  P99:     ${P99} us"
echo "  P99.9:   ${P999} us"
echo ""
echo "  Latency histogram:"
echo "    <= 50us:    $(printf '%5d' "$B0")  $(awk "BEGIN{printf \"%5.1f\", $B0*100/$ITERATIONS}")%"
echo "    51-100us:   $(printf '%5d' "$B1")  $(awk "BEGIN{printf \"%5.1f\", $B1*100/$ITERATIONS}")%"
echo "    101-200us:  $(printf '%5d' "$B2")  $(awk "BEGIN{printf \"%5.1f\", $B2*100/$ITERATIONS}")%"
echo "    201-500us:  $(printf '%5d' "$B3")  $(awk "BEGIN{printf \"%5.1f\", $B3*100/$ITERATIONS}")%"
echo "    501-1000us: $(printf '%5d' "$B4")  $(awk "BEGIN{printf \"%5.1f\", $B4*100/$ITERATIONS}")%"
echo "    1-5ms:      $(printf '%5d' "$B5")  $(awk "BEGIN{printf \"%5.1f\", $B5*100/$ITERATIONS}")%"
echo "    >5ms:       $(printf '%5d' "$B6")  $(awk "BEGIN{printf \"%5.1f\", $B6*100/$ITERATIONS}")%"
echo ""
echo "# Interpret: <100us = excellent, 100-500us = good, 500us-1ms = acceptable, >5ms = problematic for audio"
