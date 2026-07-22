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
#   profiler.sh gpu [interval_s] [samples]     — Mali GPU freq, mem, governor
#   profiler.sh flash [interval_s] [samples]   — SD card wear, block stats
#   profiler.sh temp [interval_s] [samples]    — Thermal zone temperatures
#   profiler.sh jitter [interval_s] [samples]  — Timer jitter (approximates frame budget variance)
#   profiler.sh all [interval_s] [samples]     — All of the above

set -e

INTERVAL=${2:-1}
SAMPLES=${3:-10}
PID=${4:-}
CSV_MODE=0

usage() {
    echo "Usage: profiler.sh <mode> [interval_s] [samples] [pid]"
    echo "Modes: cpu | irq | sched | threads | xruns | pressure | gpu | flash | temp | jitter | all"
    echo "  cpu         CPU utilization per core (%)"
    echo "  irq         IRQ rate per interrupt per CPU (irqs/s)"
    echo "  sched       Scheduler run_delay per CPU (ns)"
    echo "  threads     Per-thread context-switch rate for PID"
    echo "  xruns       ALSA xrun/underrun counts"
    echo "  pressure    PSI pressure stall information"
    echo "  gpu         Mali GPU frequency, memory, governor"
    echo "  flash       SD card wear level, block I/O stats"
    echo "  temp        Thermal zone temperatures"
    echo "  jitter      Timer jitter (approximates frame budget variance)"
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

# --- GPU profiler (Mali) ---
profile_gpu() {
    [ "$CSV_MODE" = 1 ] && csv_hdr "gpu_freq_mhz,gpu_mem_mb,gpu_governor,gpu_util_pct,vsync_on_pan"

    local i=0
    while [ $i -lt "$SAMPLES" ]; do
        local ts_now=$(ts)

        # Mali GPU frequency (multiple possible paths)
        local gpu_freq="N/A"
        for p in /sys/class/devfreq/*gpu*/cur_freq /sys/bus/platform/devices/*gpu*/devfreq/*/cur_freq /sys/kernel/debug/mali/clock 2>/dev/null; do
            [ -f "$p" ] && { gpu_freq=$(cat "$p" 2>/dev/null); break; }
        done
        # Convert to MHz if in Hz (values > 1000000)
        if [ "$gpu_freq" != "N/A" ] && [ "$gpu_freq" -gt 1000000 ] 2>/dev/null; then
            gpu_freq=$((gpu_freq / 1000000))
        fi

        # GPU governor
        local gpu_gov="N/A"
        for p in /sys/class/devfreq/*gpu*/governor /sys/bus/platform/devices/*gpu*/devfreq/*/governor 2>/dev/null; do
            [ -f "$p" ] && { gpu_gov=$(cat "$p" 2>/dev/null); break; }
        done

        # GPU utilization (load)
        local gpu_load="N/A"
        for p in /sys/class/devfreq/*gpu*/load /sys/bus/platform/devices/*gpu*/devfreq/*/load 2>/dev/null; do
            [ -f "$p" ] && { gpu_load=$(cat "$p" 2>/dev/null | awk '{print $1}'); break; }
        done

        # Mali GPU memory (from debug or sysfs)
        local gpu_mem="N/A"
        for p in /sys/kernel/debug/mali/memory_usage /sys/class/misc/mali*/device/mem 2>/dev/null; do
            [ -f "$p" ] && { gpu_mem=$(cat "$p" 2>/dev/null | head -1 | awk '{print $1}'); break; }
        done

        # Vsync state (fb0 vsync_on_pan)
        local vsync="N/A"
        [ -f "/sys/class/graphics/fb0/vsync_on_pan" ] && vsync=$(cat "/sys/class/graphics/fb0/vsync_on_pan" 2>/dev/null)

        if [ "$CSV_MODE" = 1 ]; then
            csv_row "$ts_now" "$gpu_freq,$gpu_mem,$gpu_gov,$gpu_load,$vsync"
        else
            printf "[gpu] freq=%-8s MHz  mem=%-12s gov=%-12s load=%-6s vsync=%s\n" \
                "$gpu_freq" "$gpu_mem" "$gpu_gov" "$gpu_load" "$vsync"
        fi

        [ "$SAMPLES" -gt 1 ] && sleep "$INTERVAL"
        i=$((i + 1))
    done
}

# --- Flash wear profiler ---
profile_flash() {
    [ "$CSV_MODE" = 1 ] && csv_hdr "device,size_mb,read_mb,write_mb,slc_life_pct,mlc_life_pct,iostats"

    local i=0
    while [ $i -lt "$SAMPLES" ]; do
        local ts_now=$(ts)

        # Find mmcblk devices with lifetime info (eMMC/SD only)
        for dev in /sys/block/mmcblk*/device/life_time; do
            [ -f "$dev" ] || continue
            local blkdev=$(echo "$dev" | sed 's|/sys/block/\([^/]*\)/.*|\1|')
            local lta=$(awk '{print $1}' "$dev" 2>/dev/null)
            local ltb=$(awk '{print $2}' "$dev" 2>/dev/null)

            # SLC: life_time A, MLC: life_time B. Values 0x01-0x0B = 10%-100% in 10% steps
            local slc_pct="N/A"
            local mlc_pct="N/A"
            if [ -n "$lta" ] && [ "$lta" != "0x00" ]; then
                slc_pct=$(( ($(printf "%d" "$lta") * 10) ))
                [ "$slc_pct" -gt 100 ] 2>/dev/null && slc_pct="raw:$lta"
            fi
            if [ -n "$ltb" ] && [ "$ltb" != "0x00" ]; then
                mlc_pct=$(( ($(printf "%d" "$ltb") * 10) ))
                [ "$mlc_pct" -gt 100 ] 2>/dev/null && mlc_pct="raw:$ltb"
            fi

            # Block device size
            local size_sectors=$(cat "/sys/block/$blkdev/size" 2>/dev/null)
            local size_mb=0
            [ -n "$size_sectors" ] && size_mb=$((size_sectors * 512 / 1048576))

            # I/O stats (sectors read/written, converted to MB)
            local rd_sectors=$(awk '{print $3}' "/sys/block/$blkdev/stat" 2>/dev/null)
            local wr_sectors=$(awk '{print $7}' "/sys/block/$blkdev/stat" 2>/dev/null)
            local rd_mb=0 wr_mb=0
            [ -n "$rd_sectors" ] && rd_mb=$((rd_sectors * 512 / 1048576))
            [ -n "$wr_sectors" ] && wr_mb=$((wr_sectors * 512 / 1048576))

            # Additional I/O stats: iops-in-progress, avg queue
            local iops_ip=$(awk '{print $9}' "/sys/block/$blkdev/stat" 2>/dev/null)
            local io_ticks=$(awk '{print $10}' "/sys/block/$blkdev/stat" 2>/dev/null)
            local io_weighted=$(awk '{print $11}' "/sys/block/$blkdev/stat" 2>/dev/null)

            if [ "$CSV_MODE" = 1 ]; then
                csv_row "$ts_now" "$blkdev,$size_mb,$rd_mb,$wr_mb,$slc_pct,$mlc_pct,$io_weighted"
            else
                printf "[flash] %-8s size=%6d MB  read=%6d MB  write=%6d MB  SLC_wear=%3s%%  MLC_wear=%3s%%  io_wtd=%s\n" \
                    "$blkdev" "$size_mb" "$rd_mb" "$wr_mb" "$slc_pct" "$mlc_pct" "$io_weighted"
            fi
        done

        [ "$SAMPLES" -gt 1 ] && sleep "$INTERVAL"
        i=$((i + 1))
    done
}

# --- Temperature profiler ---
profile_temp() {
    [ "$CSV_MODE" = 1 ] && csv_hdr "zone,type,temp_c"

    local i=0
    local found=0
    while [ $i -lt "$SAMPLES" ]; do
        local ts_now=$(ts)

        for zone in /sys/class/thermal/thermal_zone*; do
            [ -d "$zone" ] || continue
            local zname=$(basename "$zone")
            local ztype=$(cat "$zone/type" 2>/dev/null || echo "?")
            local temp_raw=$(cat "$zone/temp" 2>/dev/null || echo "0")
            # temp is in millidegrees C
            local temp_c=$((temp_raw / 1000))

            # CPU throttling state
            local throttle=""
            [ -f "$zone/throttle" ] && throttle="throttle=$(cat "$zone/throttle" 2>/dev/null)"

            if [ "$temp_c" -gt 0 ] 2>/dev/null || [ "$CSV_MODE" = 1 ]; then
                found=1
                if [ "$CSV_MODE" = 1 ]; then
                    csv_row "$ts_now" "$zname,$ztype,$temp_c"
                else
                    printf "[temp] %s type=%-20s temp=%4d°C  %s\n" "$zname" "$ztype" "$temp_c" "$throttle"
                fi
            fi
        done

        [ "$found" = 0 ] && { echo "No thermal zones found"; break; }

        [ "$SAMPLES" -gt 1 ] && sleep "$INTERVAL"
        i=$((i + 1))
    done
}

# --- Timer jitter profiler ---
# Approximates frame-budget variance by measuring sleep timer precision.
# High jitter → potential audio buffer underruns / frame drops.
profile_jitter() {
    [ "$CSV_MODE" = 1 ] && csv_hdr "target_us,actual_us,error_us,error_pct"

    # Use a target close to audio buffer period: 1024 frames @ 44100 Hz = 23.2 ms
    # But BusyBox sleep only handles seconds, so we use read -t for sub-second waits
    local target_us=${JITTER_TARGET:-23200}  # 23.2ms default (one audio period)
    local target_s=$((target_us / 1000000))
    local target_remainder=$((target_us % 1000000))

    local i=0
    local max_error=0 min_error=999999999 total_error=0

    echo "# Target: ${target_us} us (audio buffer period at 1024/44100)"
    echo "#"

    while [ $i -lt "$SAMPLES" ]; do
        local t0=$(ts)

        # Sub-second sleep using read -t (microsecond-ish precision on RT kernel)
        if command -v usleep >/dev/null 2>&1; then
            usleep "$target_us"
        elif command -v read >/dev/null 2>&1 && [ "$target_remainder" -gt 0 ] 2>/dev/null; then
            sleep "$target_s" 2>/dev/null || true
            read -t "$(awk "BEGIN {printf \"%.6f\", $target_remainder / 1000000}")" dummy </dev/zero 2>/dev/null || true
        else
            sleep "$INTERVAL"
        fi

        local t1=$(ts)
        # Calculate actual elapsed in microseconds
        local actual_us=$(awk "BEGIN {printf \"%d\", ($t1 - $t0) * 1000000}" 2>/dev/null)
        local error_us=0 error_pct=0
        if [ -n "$actual_us" ] && [ "$actual_us" -gt 0 ] 2>/dev/null; then
            error_us=$((actual_us - target_us))
            [ "$error_us" -lt 0 ] 2>/dev/null && error_us=$((-error_us))
            error_pct=$(awk "BEGIN {printf \"%.1f\", ($error_us / $target_us) * 100}" 2>/dev/null)

            # Track min/max/total
            [ "$error_us" -gt "$max_error" ] 2>/dev/null && max_error=$error_us
            [ "$error_us" -lt "$min_error" ] 2>/dev/null && min_error=$error_us
            total_error=$((total_error + error_us))
        fi

        if [ "$CSV_MODE" = 1 ]; then
            csv_row "$t0" "$target_us,$actual_us,$error_us,$error_pct"
        else
            printf "[jitter] target=%-6d us  actual=%-8s us  error=%-6d us (%-5s%%)\n" \
                "$target_us" "${actual_us:-N/A}" "${error_us:-0}" "${error_pct:-0.0}"
        fi

        i=$((i + 1))
    done

    # Summary
    if [ "$SAMPLES" -gt 1 ]; then
        local avg_err=$((total_error / SAMPLES))
        echo ""
        echo "# Summary (${SAMPLES} samples, target=${target_us} us):"
        echo "#   avg_error=${avg_err} us  min_error=${min_error} us  max_error=${max_error} us"
        # max_error as % of audio period
        local max_pct=$(awk "BEGIN {printf \"%.1f\", ($max_error / $target_us) * 100}" 2>/dev/null)
        echo "#   max_error=${max_pct}% of audio buffer period"
        # Rule of thumb: if max_error > 20% of buffer period, audio glitches likely
        if [ "$max_error" -gt 4640 ] 2>/dev/null; then  # 20% of 23.2ms
            echo "#   WARNING: jitter exceeds 20% of audio buffer period — underruns likely"
        fi
    fi
}
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
    echo "=== GPU / Mali ==="
    CSV_MODE=0 profile_gpu
    echo ""
    echo "=== Temperature ==="
    profile_temp
    echo ""
    echo "=== Flash Storage ==="
    profile_flash
    echo ""
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
    echo "=== Timer Jitter ==="
    profile_jitter "$INTERVAL" "$SAMPLES"
    echo ""
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
    gpu)       profile_gpu ;;
    flash)     profile_flash ;;
    temp)      profile_temp ;;
    jitter)    profile_jitter ;;
    all)       profile_all ;;
    *)         usage ;;
esac
