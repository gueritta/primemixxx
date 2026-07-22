#!/bin/sh
# fix-mdns.sh — Ensure mDNS advertises primego.local, not buildroot.local.
# Idempotent: skips if already configured correctly.
# Runs at boot via fix-mdns.service, or manually.

HOSTNAME="primego"
CONF="/etc/avahi/avahi-daemon.conf"
WANTED="host-name=$HOSTNAME"

# Check if already configured correctly
if grep -q "^$WANTED" "$CONF" 2>/dev/null; then
    # Already set, verify avahi is using it
    if ps | grep "avahi-daemon.*$HOSTNAME" | grep -qv grep; then
        exit 0  # All good, nothing to do
    fi
fi

# Fix: set host-name in avahi config
if grep -q "^#*host-name=" "$CONF" 2>/dev/null; then
    sed -i "s/^#*host-name=.*/$WANTED/" "$CONF"
else
    echo "$WANTED" >> "$CONF"
fi

# Restart avahi to pick up the change
systemctl restart avahi-daemon.service 2>/dev/null || \
    { killall avahi-daemon 2>/dev/null; sleep 1; avahi-daemon -D; }

echo "mDNS fixed: $(hostname).local (was buildroot.local)"
