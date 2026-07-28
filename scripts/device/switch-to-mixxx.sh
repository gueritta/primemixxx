#!/bin/sh
# switch-to-mixxx — Switch from Engine DJ to MIXXX (deployed on SD card)
# Usage: ssh root@primego switch-to-mixxx
set -e

echo "Switching to MIXXX..."

# Remount rootfs read-write if needed
mount -o remount,rw / 2>/dev/null || true

# Stop Engine
echo "Stopping engine.service..."
systemctl stop engine.service 2>/dev/null || true
sleep 1

# Ensure MIXXX launcher is executable
chmod +x /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/mixxx_launcher.sh

# Start MIXXX
echo "Starting mixxx.service..."
systemctl start mixxx.service

# Start power button monitor (only needed for MIXXX, not Engine DJ)
systemctl start powerbutton-monitor.service 2>/dev/null || true

echo "MIXXX is now running. Use 'switch-to-engine' to go back."
