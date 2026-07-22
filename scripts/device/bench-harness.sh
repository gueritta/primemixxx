#!/bin/sh
# Benchmark Harness — before/after optimization comparison
# Runs profiler + cpu-latency + xrun-monitor, applies an optimization,
# re-runs, and diffs results.
#
# Usage (on device):
#   bench-harness.sh [output_dir] [duration_s]
#
#   output_dir: where to store results (default: /tmp/bench-YYYYMMDD-HHMMSS)
#   duration_s: how long each phase runs (default: 30)
#
# What it measures:
#   PHASE 1 (baseline): Run profiler + CPU latency benchmark
#   PHASE 2 (with optimization): Apply optimization, re-run same measurements
#
# Results are stored as text files, diff'd at the end.

set -e

OUTDIR=${1:-/tmp/bench-$(date +%Y%m%d-%H%M%S)}
DURATION=${2:-30}
SCRIPT_DIR=$(dirname "$0")

mkdir -p "$OUTDIR"

log() { echo "[harness] $*"; }
ts() { date +%Y%m%d-%H%M%S; }

# --- Phase: run all measurements ---
run_phase() {
    local phase=$1
    local dir="$OUTDIR/$phase"
    mkdir -p "$dir"

    log "=== Phase $phase starting at $(ts) ==="

    # Find MIXXX PID if running
    MIXPID=$(pidof mixxx 2>/dev/null | awk '{print $1}' || true)

    # 1. CPU latency benchmark (cyclictest equivalent)
    log "Running CPU latency benchmark..."
    sh "$SCRIPT_DIR/cpu-latency.sh" 1000 500 > "$dir/cpu-latency.txt" 2>"$dir/cpu-latency.err" || true

    # 2. Continuous profiler (CPU mode) for the duration
    log "Running CPU profiler for ${DURATION}s..."
    timeout "$DURATION" sh "$SCRIPT_DIR/profiler.sh" cpu 2 $((DURATION / 2)) > "$dir/profiler-cpu.txt" 2>/dev/null || true

    # 3. IRQ profiler
    log "Running IRQ profiler for 10s..."
    sh "$SCRIPT_DIR/profiler.sh" irq 2 5 > "$dir/profiler-irq.txt" 2>/dev/null || true

    # 4. Scheduler profiler
    [ -f /proc/schedstat ] && {
        log "Running sched profiler for 10s..."
        sh "$SCRIPT_DIR/profiler.sh" sched 2 5 > "$dir/profiler-sched.txt" 2>/dev/null || true
    } || log "No /proc/schedstat — skipping sched profiler"

    # 5. Thread profiler (if MIXXX is running)
    if [ -n "$MIXPID" ] && [ -d "/proc/$MIXPID" ]; then
        log "Running thread profiler for PID $MIXPID (10s)..."
        sh "$SCRIPT_DIR/profiler.sh" threads 2 5 "$MIXPID" > "$dir/profiler-threads.txt" 2>/dev/null || true
    else
        log "MIXXX not running — skipping thread profiler"
    fi

    # 6. Xrun counts (if MIXXX is running)
    log "Recording xrun counts..."
    sh "$SCRIPT_DIR/xrun-monitor.sh" 5 "$DURATION" > "$dir/xruns.txt" 2>/dev/null &

    # 7. System snapshot
    log "Taking system snapshot..."
    {
        echo "=== CPU Info ==="
        cat /proc/cpuinfo 2>/dev/null | grep -E "model name|BogoMIPS|Hardware|Processor" || true
        echo "=== CPU Freq ==="
        for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
            [ -f "$c" ] && echo "$c: $(cat "$c")" || true
        done
        for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [ -f "$c" ] && echo "$c: $(cat "$c")" || true
        done
        echo "=== Uptime ==="
        cat /proc/uptime 2>/dev/null || true
        echo "=== Memory ==="
        cat /proc/meminfo 2>/dev/null | grep -E "^Mem|^Swap" || true
        echo "=== Kernel ==="
        uname -a 2>/dev/null || true
        echo "=== Cmdline ==="
        cat /proc/cmdline 2>/dev/null || true
        echo "=== RT throttle ==="
        cat /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null || true
        echo "=== Timer migration ==="
        cat /proc/sys/kernel/timer_migration 2>/dev/null || true
        echo "=== THP ==="
        cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
        echo "=== KSM ==="
        cat /sys/kernel/mm/ksm/run 2>/dev/null || true
    } > "$dir/system-snapshot.txt" 2>/dev/null

    # Wait for xrun monitor to finish
    wait 2>/dev/null || true

    log "=== Phase $phase complete at $(ts) ==="
}

# --- Apply optimization ---
apply_optimizations() {
    log "Applying optimizations..."

    # CPU governor → performance
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$gov" ] && echo performance > "$gov" 2>/dev/null && log "  CPU governor: performance" || true
    done

    # THP off
    [ -f /sys/kernel/mm/transparent_hugepage/enabled ] && {
        echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null && log "  THP: disabled" || true
    }

    # Timer migration off
    [ -f /proc/sys/kernel/timer_migration ] && {
        echo 0 > /proc/sys/kernel/timer_migration 2>/dev/null && log "  Timer migration: off" || true
    }

    # KSM off
    [ -f /sys/kernel/mm/ksm/run ] && {
        echo 0 > /sys/kernel/mm/ksm/run 2>/dev/null && log "  KSM: off" || true
    }

    # VM writeback tuning
    sysctl -w vm.dirty_ratio=5 > /dev/null 2>&1 && log "  vm.dirty_ratio=5" || true
    sysctl -w vm.dirty_background_ratio=1 > /dev/null 2>&1 && log "  vm.dirty_background_ratio=1" || true

    # Pin audio IRQ to CPU 2
    [ -f /proc/irq/45/smp_affinity ] && {
        echo 4 > /proc/irq/45/smp_affinity 2>/dev/null && log "  Audio IRQ 45 → CPU 2" || true
    }

    # Disable IPv6
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null 2>&1 && log "  IPv6: disabled" || true

    log "Optimizations applied."
}

# --- Restore baseline ---
restore_baseline() {
    log "Restoring baseline settings..."
    # We don't actually revert — baseline is measured first, then optimizations applied.
    # The phase1 vs phase2 comparison shows the effect.
    log "  (baseline was measured in phase1 before any changes)"
}

# --- Diff results ---
diff_phase() {
    local d1="$OUTDIR/baseline"
    local d2="$OUTDIR/optimized"
    local diffd="$OUTDIR/diffs"
    mkdir -p "$diffd"

    log "=== Computing diffs ==="

    # CPU latency summary
    if [ -f "$d1/cpu-latency.txt" ] && [ -f "$d2/cpu-latency.txt" ]; then
        echo "--- CPU Latency ---"
        echo "Baseline:"; grep -E "Min|Max|Avg|P99" "$d1/cpu-latency.txt" | head -6
        echo "Optimized:"; grep -E "Min|Max|Avg|P99" "$d2/cpu-latency.txt" | head -6
        echo ""
        echo "Full diff:" > "$diffd/cpu-latency.diff"
        diff "$d1/cpu-latency.txt" "$d2/cpu-latency.txt" >> "$diffd/cpu-latency.diff" 2>&1 || true
        echo "  cpu-latency diff: $diffd/cpu-latency.diff"
    fi

    # System snapshot diff
    if [ -f "$d1/system-snapshot.txt" ] && [ -f "$d2/system-snapshot.txt" ]; then
        diff "$d1/system-snapshot.txt" "$d2/system-snapshot.txt" > "$diffd/system-snapshot.diff" 2>&1 || true
        echo "  system-snapshot diff: $diffd/system-snapshot.diff"
    fi

    # Xrun summary
    if [ -f "$d1/xruns.txt" ] && [ -f "$d2/xruns.txt" ]; then
        echo ""
        echo "--- Xruns ---"
        echo "Baseline total xruns: $(grep -c "overrun\|underrun" "$d1/xruns.txt" 2>/dev/null || echo 0)"
        echo "Optimized total xruns: $(grep -c "overrun\|underrun" "$d2/xruns.txt" 2>/dev/null || echo 0)"
    fi

    log "=== Results saved to $OUTDIR ==="
}

# --- Main ---
echo "============================================"
echo "  Denon Prime Go Optimization Benchmark"
echo "  Duration per phase: ${DURATION}s"
echo "  Output: $OUTDIR"
echo "============================================"
echo ""

# Phase 1: Baseline
run_phase "baseline"

# Apply optimizations
apply_optimizations

# Wait for stabilization
log "Waiting 5s for system to stabilize..."
sleep 5

# Phase 2: Optimized
run_phase "optimized"

# Diff results
diff_phase

echo ""
echo "===== Benchmark complete ====="
echo "Results in: $OUTDIR"
echo "  baseline/   — before optimization"
echo "  optimized/  — after optimization"
echo "  diffs/      — comparison"
