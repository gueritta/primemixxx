#!/bin/sh
# switch-to-engine — Switch from MIXXX back to Engine DJ
# Usage: ssh root@primego switch-to-engine
set -e

echo "Switching to Engine DJ..."

# Stop MIXXX
echo "Stopping mixxx.service..."
systemctl stop mixxx.service 2>/dev/null || true
sleep 1

# Start Engine
echo "Starting engine.service..."
systemctl start engine.service
echo "Engine DJ is now running. Use 'switch-to-mixxx' to go back."
