#!/bin/sh
# TKGL module: ensure USB Ethernet gadget is installed and running on the system.
# This runs BEFORE mod_mixxx so USB SSH is available regardless of MIXXX state.

tkgl_mod_usb() {
    log "=== mod_usb: USB Ethernet gadget ==="

    # Check if service already installed on system
    if [ -f /usr/lib/systemd/system/usb-gadget-eth.service ]; then
        log "usb-gadget-eth.service already installed on system"
    else
        log "Installing USB gadget service to system..."
        if [ -f "$TKGL_MODULES/mod_usb/usb-gadget-eth.service" ]; then
            cp "$TKGL_MODULES/mod_usb/usb-gadget-eth.service" /usr/lib/systemd/system/
            cp "$TKGL_MODULES/mod_usb/usb-gadget-eth.sh" /usr/sbin/
            chmod +x /usr/sbin/usb-gadget-eth.sh
            systemctl daemon-reload
            systemctl enable usb-gadget-eth.service
            log "USB gadget service installed and enabled"
        else
            log "ERROR: usb-gadget-eth.service not found in module — USB SSH unavailable"
            return 1
        fi
    fi

    # Start the service (no-op if already active)
    systemctl start usb-gadget-eth.service 2>/dev/null || true

    # Wait briefly for usb0 to come up
    for i in $(seq 1 10); do
        [ -d /sys/class/net/usb0 ] && break
        sleep 1
    done

    if ip link show usb0 >/dev/null 2>&1; then
        log "usb0 interface ready at 192.168.42.1"
    else
        log "WARNING: usb0 did not come up"
    fi

    return 0
}
