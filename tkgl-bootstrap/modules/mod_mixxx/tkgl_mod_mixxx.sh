#!/bin/sh
# TKGL module: start Mixxx in an independent systemd cgroup.
# Delegates to /data/mixxx/mixxx which then delegates to the SD card launcher.
# mixxx-app.service must NOT be masked — systemd-run needs the unit name available.

tkgl_mod_mixxx() {
    log "=== mod_mixxx: launching Mixxx ==="

    # Disable WiFi power save to prevent SSH drops during sessions
    iw dev wlan0 set power_save off 2>/dev/null || true
    log "WiFi power save disabled"

    if systemctl is-active --quiet mixxx-app.service; then
        log "mixxx-app.service is already active"
        return 0
    fi

    # /data/mixxx/mixxx is a delegation script that calls the SD card launcher:
    #   exec /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/mixxx_launcher.sh "$@"
    # The SD launcher sets all env vars (Qt, Mali, USB, seed DB) and CPU shielding.
    MIXDIR=/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle
    ENTRYPOINT=$MIXDIR/mixxx_launcher.sh
    LOGFILE="$TKGL_LOG/mixxx_$(date +%Y%m%d_%H%M%S).log"

    if [ ! -x "$ENTRYPOINT" ]; then
        log "ERROR: Mixxx entrypoint not executable: $ENTRYPOINT"
        return 1
    fi

    [ -c /dev/mali0 ] && chmod 666 /dev/mali0 2>/dev/null
    for governor in /sys/class/devfreq/*mali*/governor /sys/class/devfreq/*gpu*/governor; do
        [ -f "$governor" ] && echo performance > "$governor" 2>/dev/null
    done
    udevadm trigger --subsystem-match=block --action=add 2>/dev/null || true

    # Pin non-audio IRQs to CPU 0 to prevent GPU/USB/MMC interrupts from
    # preempting audio engine threads on isolated cores 2-3.
    for irq in /proc/irq/*/smp_affinity; do
        irqnum=$(echo "$irq" | grep -oE '[0-9]+')
        # Skip IRQs 0-31 (system-critical) and 45 (audio DMA controller)
        [ "$irqnum" -le 31 ] 2>/dev/null && continue
        [ "$irqnum" = "45" ] && continue
        echo 1 > "$irq" 2>/dev/null
    done

    log "starting mixxx-app.service; log: $LOGFILE"
    # Env vars intentionally NOT set here — the SD card launcher handles all of:
    # Qt 5.15.8, eglfs_mali, USB bind-mount, seed DB restore, CPU shielding.
    # Passing --settingsPath or -platform here would override the SD launcher's settings.

    # Start power button monitor to gracefully shut down MIXXX on button press
    systemctl start powerbutton-monitor.service 2>/dev/null || true
    log "powerbutton-monitor started"

    systemd-run --unit=mixxx-app --collect --service-type=exec \
        --property=RuntimeDirectory=mixxx \
        --property=RuntimeDirectoryMode=0700 \
        --working-directory="$MIXDIR" \
        --setenv=HOME=/root \
        --setenv=XDG_RUNTIME_DIR=/run/mixxx \
        -- /bin/sh -c "exec '$ENTRYPOINT' > '$LOGFILE' 2>&1"

    if systemctl is-active --quiet mixxx-app.service; then
        log "mixxx-app.service started in an independent cgroup"
    else
        log "ERROR: mixxx-app.service did not become active"
        return 1
    fi
}

tkgl_mod_mixxx
