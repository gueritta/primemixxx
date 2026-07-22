#!/bin/sh
# Device Profiler — Measurement toolkit for Denon Prime Go
# Uses only /proc and /sys interfaces + BusyBox tools.
# No external packages required.
#
# Usage:
#   profiler.sh cpu [interval_s] [samples]     — CPU utilization per core
#   profiler.sh irq [interval_s] [samples]     — IRQ rate per IRQ per CPU
#   profiler.sh sched [interval_s] [samples]   — Scheduler run_delay per CPU
#   profiler.sh threads <pid> [interval_s] [samples]  — Per-thread stats
#   profiler.sh xruns [interval_s] [samples]   — ALSA xrun counts
#   profiler.sh pressure [interval_s] [samples] — PSI pressure stalls
#   profiler.sh all [interval_s] [samples]     — All of the above

set -e

INTERVAL=${2:-1}
SAMPLES=${3:-10}
PID=${4:-}
CSV_MODE=0

usage() {
    echo "Usage: profiler.sh <mode> [interval_s] [samples] [pid]"
    echo "Modes: cpu | irq | sched | threads | xruns | pressure | all"
    echo "  cpu         CPU utilization per core (%)"
    echo "  irq         IRQ rate per interrupt per CPU (irqs/s)"
    echo "  sched       Scheduler run_delay per CPU (ns)"
    echo "  threads     Per-thread context-switch rate for PID"
    echo "  xruns       ALSA xrun/underrun counts"
    echo "  pressure    PSI pressure stall information"
    echo "  all         All of the above"
    exit 1
}
[ $# -lt 1 ] && usage

# --- Helpers ---

ts() { date +%s.%N 2>/dev/null || awk 'BEGIN{printf "%.6f", systime()}' 2>/dev/null || date +%s; }

# Read a file, return 0 if empty/missing
read_file() { cat "$1" 2>/dev/null || true; }

# CSV header printer
csv_hdr() { shift; printf "timestamp,%s\n" "$*"; }
csv_row() { local ts="$1"; shift; printf "%.3f,%s\n" "$ts" "$*"; }

# --- CPU profiler ---
profile_cpu() {
    local i ts idle0 iowait0 user0 sys0 irq0 sirq0 steal0
    [ "$CSV_MODE" = 1 ] && csv_hdr "cpu,user,system,iowait,irq,softirq,steal,idle"

    # Read initial snapshot: sum across all CPUs
    local line=$(grep "^cpu " /proc/stat)
    set -- $line; shift
    user0=$1; nice0=$2; sys0=$3; idle0=$4; iowait0=$5; irq0=$6; sirq0=$7; steal0=$8
    user0=$((user0 + nice0))

    i=0
    while [ $i -lt "$SAMPLES" ]; do
        sleep "$INTERVAL"
        line=$(grep "^cpu " /proc/stat)
        set -- $line; shift
        local user1=$1 nice1=$2 sys1=$3 idle1=$4 iowait1=$5 irq1=$6 sirq1=$7 steal1=$8
        user1=$((user1 + nice1))

        local total_delta=$(( (user1 + sys1 + idle1 + iowait1 + irq1 + sirq1 + steal1) - (user0 + sys0 + idle0 + iowait0 + irq0 + sirq0 + steal0) ))
        [ "$total_delta" = 0 ] && total_delta=1

        local user_pct=$(( 100 * (user1 - user0) / total_delta ))
        local sys_pct=$(( 100 * (sys1 - sys0) / total_delta ))
        local iowait_pct=$(( 100 * (iowait1 - iowait0) / total_delta ))
        local irq_pct=$(( 100 * (irq1 - irq0) / total_delta ))
        local sirq_pct=$(( 100 * (sirq1 - sirq0) / total_delta ))
        local steal_pct=$(( 100 * (steal1 - steal0) / total_delta ))
        local idle_pct=$(( 100 * (idle1 - idle0) / total_delta ))
        local total_pct=$(( 100 - idle_pct ))

        if [ "$CSV_MODE" = 1 ]; then
            csv_row "$(ts)" "all,$total_pct,$user_pct,$sys_pct,$iowait_pct,$irq_pct,$sirq_pct,$steal_pct,$idle_pct"
        else
            printf "[cpu] total=%3d%% user=%2d%% sys=%2d%% iowait=%2d%% irq=%2d%% sirq=%2d%% steal=%2d%% idle=%2d%%\n" \
                "$total_pct" "$user_pct" "$sys_pct" "$iowait_pct" "$irq_pct" "$sirq_pct" "$steal_pct" "$idle_pct"
        fi

        user0=$user1; nice0=$nice1; sys0=$sys1; idle0=$idle1; iowait0=$iowait1; irq0=$irq1; sirq0=$sirq1; steal0=$steal1
        i=$((i + 1))
    done
}

# --- IRQ profiler ---
profile_irq() {
    [ "$CSV_MODE" = 1 ] && csv_hdr "irq,desc,cpu_count,irqs_per_sec,per_cpu"

    # Take snapshot of /proc/interrupts — store as associative arrays via temp files
    local tmp0=/tmp/profiler-irq-0.$$ tmp1=/tmp/profiler-irq-1.$$ ts_start ts_end
    cp /proc/interrupts "$tmp0"

    local i=0
    while [ $i -lt "$SAMPLES" ]; do
        sleep "$INTERVAL"
        ts_end=$(ts)
        cp /proc/interrupts "$tmp1"

        # Parse both files and compute deltas
        # Format: IRQ_NUM: CPU0 CPU1 CPU2 CPU3  TYPE  DEVICE
        while read -r line0; do
            echo "$line0" | grep -qE '^[[:space:]]*[0-9]+:' || continue
            local irq=$(echo "$line0" | awk '{print $1}' | tr -d ':')
            local line1=$(grep "^[[:space:]]*${irq}:" "$tmp1" 2>/dev/null || true)
            [ -z "$line1" ] && continue

            # Count CPUs by number of numeric columns before the type field
            local cpus0=$(echo "$line0" | awk '{for(i=2;i<=NF;i++){if($i~/^[0-9]+$/){printf "%d ",$i}else{break}}}')
            local cpus1=$(echo "$line1" | awk '{for(i=2;i<=NF;i++){if($i~/^[0-9]+$/){printf "%d ",$i}else{break}}}')
            local desc=$(echo "$line0" | awk '{for(i=2;i<=NF;i++){if($i!~/^[0-9]+$/){print substr($0, index($0,$i)); break}}}')

            # Sum across CPUs and compute delta
            local sum0=0 sum1=0
            for v in $cpus0; do sum0=$((sum0 + v)); done
            for v in $cpus1; do sum1=$((sum1 + v)); done
            local delta=$((sum1 - sum0))

            if [ "$delta" -gt 0 ] 2>/dev/null; then
                local rate=$(( delta / INTERVAL ))
                if [ "$CSV_MODE" = 1 ]; then
                    csv_row "$ts_end" "$irq,\"$desc\",$rate"
                else
                    printf "[irq] IRQ%3s rate=%6d/s  %s\n" "$irq" "$rate" "$desc"
                fi
            fi
        done < "$tmp0" | sort -t= -k2 -nr | head -15

        mv "$tmp1" "$tmp0"
        i=$((i + 1))
    done
    rm -f "$tmp0" "$tmp1"
}

# --- Scheduler profiler ---
# /proc/schedstat format (first line per CPU):
# cpu0 YYY ZZZ AAA BBB CCC DDD EEE FFF GGG
#   YYY = sched_yield count
#   ZZZ = not used
#   AAA = run_delay total (ns)
#   BBB = pcount (number of tasks run)
profile_sched() {
    [ "$CSV_MODE" = 1 ] && csv_hdr "cpu,run_delay_ns,pcount,avg_delay_ns"
    # /proc/schedstat may not exist on all kernels
    [ -f /proc/schedstat ] || { echo "ERROR: /proc/schedstat not found"; exit 1; }

    cp /proc/schedstat /tmp/profiler-sched-0.$$

    local i=0
    while [ $i -lt "$SAMPLES" ]; do
        sleep "$INTERVAL"
        local ts_now=$(ts)
        cp /proc/schedstat /tmp/profiler-sched-1.$$

        grep "^cpu[0-9]" /tmp/profiler-sched-0.$$ | while read -r line0; do
            local cpu=$(echo "$line0" | awk '{print $1}')
            set -- $line0
            local delay0=$4 pcount0=$5

            local line1=$(grep "^$cpu " /tmp/profiler-sched-1.$$ 2>/dev/null)
            [ -z "$line1" ] && continue
            set -- $line1
            local delay1=$4 pcount1=$5

            local delay_d=$((delay1 - delay0))
            local pcount_d=$((pcount1 - pcount0))
            local avg=0
            [ "$pcount_d" -gt 0 ] 2>/dev/null && avg=$((delay_d / pcount_d))

            if [ "$CSV_MODE" = 1 ]; then
                csv_row "$ts_now" "$cpu,$delay_d,$pcount_d,$avg"
            else
                printf "[sched] %s run_delay=%10d ns  pcount=%5d  avg_delay=%7d ns\n" "$cpu" "$delay_d" "$pcount_d" "$avg"
            fi
        done

        mv /tmp/profiler-sched-1.$$ /tmp/profiler-sched-0.$$
        i=$((i + 1))
    done
    rm -f /tmp/profiler-sched-0.$$
}

# --- Thread profiler ---
# For a given PID, track voluntary/involuntary context switches per thread
profile_threads() {
    [ -z "$PID" ] && { echo "ERROR: PID required for threads mode"; exit 1; }
    [ -d "/proc/$PID" ] || { echo "ERROR: PID $PID not found"; exit 1; }

    [ "$CSV_MODE" = 1 ] && csv_hdr "tid,comm,vol_csw,nvcsw,total_csw,policy,prio"

    local i=0
    while [ $i -lt "$SAMPLES" ]; do
        local ts0=$(ts)
        # Snapshot all threads: tid, vol_csw, nvcsw
        local tmp0=/tmp/profiler-threads-0.$$
        for tdir in /proc/$PID/task/*/; do
            [ -d "$tdir" ] || continue
            local tid=$(basename "$tdir")
            local comm=$(read_file "$tdir/comm")
            local vol=$(awk '/voluntary_ctxt_switches/ {print $2}' "$tdir/status" 2>/dev/null)
            local nvcsw=$(awk '/nonvoluntary_ctxt_switches/ {print $2}' "$tdir/status" 2>/dev/null)
            echo "$tid $comm $vol $nvcsw"
        done > "$tmp0"

        sleep "$INTERVAL"
        local ts1=$(ts)

        local tmp1=/tmp/profiler-threads-1.$$
        for tdir in /proc/$PID/task/*/; do
            [ -d "$tdir" ] || continue
            local tid=$(basename "$tdir")
            local comm=$(read_file "$tdir/comm")
            local vol=$(awk '/voluntary_ctxt_switches/ {print $2}' "$tdir/status" 2>/dev/null)
            local nvcsw=$(awk '/nonvoluntary_ctxt_switches/ {print $2}' "$tdir/status" 2>/dev/null)
            echo "$tid $comm $vol $nvcsw"
        done > "$tmp1"

        # Diff
        while read -r line1; do
            set -- $line1
            local tid=$1 comm=$2 vol1=$3 nvcsw1=$4
            local line0=$(grep "^$tid " "$tmp0" 2>/dev/null || true)
            [ -z "$line0" ] && continue
            set -- $line0
            local vol0=$3 nvcsw0=$4

            local vol_d=$((vol1 - vol0))
            local nvcsw_d=$((nvcsw1 - nvcsw0))
            local total_d=$((vol_d + nvcsw_d))
            # Get scheduler policy
            local policy=$(awk '/policy/ {print $2}' "/proc/$PID/task/$tid/sched" 2>/dev/null)
            local prio=$(awk '/prio/ {print $2}' "/proc/$PID/task/$tid/sched" 2>/dev/null)

            if [ "$total_d" -gt 0 ] 2>/dev/null; then
                local rate=$((total_d / INTERVAL))
                if [ "$CSV_MODE" = 1 ]; then
                    csv_row "$ts1" "$tid,$comm,$vol_d,$nvcsw_d,$total_d,$policy,$prio"
                else
                    printf "[thread] TID=%6s %-25s vol=%4d nvcsw=%4d total=%4d csw/s=%4d pol=%s prio=%s\n" \
                        "$tid" "$comm" "$vol_d" "$nvcsw_d" "$total_d" "$rate" "$policy" "$prio"
                fi
            fi
        done < "$tmp1" | sort -t= -k5 -nr | head -20

        mv "$tmp1" "$tmp0"
        i=$((i + 1))
    done
    rm -f /tmp/profiler-threads-0.$$ /tmp/profiler-threads-1.$$
}

# --- ALSA xrun profiler ---
profile_xruns() {
    [ "$CSV_MODE" = 1 ] && csv_hdr "card,pcm,subdev,direction,overrun,underrun"

    # Find all ALSA PCM status files
    local i=0
    while [ $i -lt "$SAMPLES" ]; do
        sleep "$INTERVAL"
        local ts_now=$(ts)
        local found=0

        for statusf in /proc/asound/card*/pcm*/sub*/status; do
            [ -f "$statusf" ] || continue
            found=1
            local card=$(echo "$statusf" | sed 's|.*/card\([0-9]*\)/.*|\1|')
            local pcm=$(echo "$statusf" | sed 's|.*/pcm\([0-9a-zA-Z]*\)/.*|\1|')
            local sub=$(echo "$statusf" | sed 's|.*/sub\([0-9]*\)/.*|\1|')
            local dir="playback"
            echo "$pcm" | grep -q "c" && dir="capture"

            local overrun=$(awk '/overrun/ {print $2}' "$statusf" 2>/dev/null || echo "N/A")
            local underrun=$(awk '/underrun/ {print $2}' "$statusf" 2>/dev/null || echo "N/A")
            local state=$(awk '/state/ {print $2}' "$statusf" 2>/dev/null || echo "?")

            if [ "$CSV_MODE" = 1 ]; then
                csv_row "$ts_now" "card$card,$pcm,$sub,$dir,$overrun,$underrun"
            else
                printf "[xrun] card%s %-8s sub=%s %-10s overrun=%s underrun=%s state=%s\n" \
                    "$card" "$pcm" "$sub" "$dir" "$overrun" "$underrun" "$state"
            fi
        done

        [ "$found" = 0 ] && { echo "No ALSA PCM status files found (audio not active?)"; break; }
        i=$((i + 1))
    done
}

# --- PSI pressure profiler ---
profile_pressure() {
    [ "$CSV_MODE" = 1 ] && csv_hdr "resource,avg10,avg60,avg300,total"

    local i=0
    while [ $i -lt "$SAMPLES" ]; do
        sleep "$INTERVAL"
        local ts_now=$(ts)
        local found=0

        for res in cpu io memory; do
            local pf="/proc/pressure/$res"
            [ -f "$pf" ] || continue
            found=1
            # Format: some avg10=0.00 avg60=0.00 avg300=0.00 total=12345
            #         full avg10=0.00 avg60=0.00 avg300=0.00 total=12345
            local line=$(head -1 "$pf" 2>/dev/null)
            local avg10=$(echo "$line" | awk '{for(i=1;i<=NF;i++){if($i~/avg10=/){print $i}}}' | cut -d= -f2)
            local avg60=$(echo "$line" | awk '{for(i=1;i<=NF;i++){if($i~/avg60=/){print $i}}}' | cut -d= -f2)
            local avg300=$(echo "$line" | awk '{for(i=1;i<=NF;i++){if($i~/avg300=/){print $i}}}' | cut -d= -f2)
            local total=$(echo "$line" | awk '{for(i=1;i<=NF;i++){if($i~/total=/){print $i}}}' | cut -d= -f2)

            if [ "$CSV_MODE" = 1 ]; then
                csv_row "$ts_now" "$res,$avg10,$avg60,$avg300,$total"
            else
                printf "[psi] %-6s some: avg10=%-6s avg60=%-6s avg300=%-6s total=%s\n" \
                    "$res" "$avg10" "$avg60" "$avg300" "$total"
            fi
        done

        [ "$found" = 0 ] && { echo "PSI not available (CONFIG_PSI not enabled in kernel)"; break; }
        i=$((i + 1))
    done
}

# --- RUN ALL ---
profile_all() {
    echo "=== CPU Utilization ==="
    CSV_MODE=0 profile_cpu "$INTERVAL" "$SAMPLES"
    echo ""
    echo "=== Top IRQs by Rate ==="
    profile_irq "$INTERVAL" "$SAMPLES"
    echo ""
    echo "=== Scheduler Latency ==="
    profile_sched "$INTERVAL" "$SAMPLES"
    echo ""
    if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
        echo "=== Thread Stats for PID $PID ==="
        profile_threads "$INTERVAL" "$SAMPLES"
        echo ""
    fi
    echo "=== ALSA Xruns ==="
    profile_xruns "$INTERVAL" "$SAMPLES"
    echo ""
    echo "=== PSI Pressure ==="
    profile_pressure "$INTERVAL" "$SAMPLES"
}

# --- Dispatch ---
MODE=$1
INTERVAL=${2:-1}
SAMPLES=${3:-10}
PID=${4:-}
CSV_MODE=${CSV:-0}

# Auto-detect MIXXX PID if in threads/all mode and no PID given
if [ "$MODE" = "threads" ] || [ "$MODE" = "all" ]; then
    if [ -z "$PID" ]; then
        PID=$(pidof mixxx 2>/dev/null | awk '{print $1}')
        [ -n "$PID" ] && echo "# Auto-detected MIXXX PID: $PID" >&2
    fi
fi

case "$MODE" in
    cpu)       profile_cpu ;;
    irq)       profile_irq ;;
    sched)     profile_sched ;;
    threads)   profile_threads ;;
    xruns)     profile_xruns ;;
    pressure)  profile_pressure ;;
    all)       profile_all ;;
    *)         usage ;;
esac
