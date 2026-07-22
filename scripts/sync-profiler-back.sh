#!/bin/sh
# sync-profiler-back.sh — Pull profiler scripts from device back to local repo
# Use after editing profiling tools on-device during a runtime session.
#
# Usage: DEVICE_IP=10.128.54.244 ./scripts/sync-profiler-back.sh
#        DEV=root@192.168.42.1 ./scripts/sync-profiler-back.sh

DEV="${1:-root@${DEVICE_IP:-primego.local}}"
LOCAL_DIR="$(cd "$(dirname "$0")/device" && pwd)"

echo "=== Pulling profiler scripts from $DEV ==="
echo ""

for f in profiler.sh cpu-latency.sh xrun-monitor.sh bench-harness.sh; do
    echo -n "  $f ... "
    if scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$DEV:/data/$f" "$LOCAL_DIR/$f" 2>/dev/null; then
        echo "OK"
    else
        echo "FAIL (file may not exist on device)"
    fi
done

echo ""
echo "Done. Run: git diff scripts/device/"
