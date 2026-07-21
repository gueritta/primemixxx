#!/bin/sh
# TKGL module: thin caller — delegates all MIXXX config to SD card launcher.
# All env vars, CPU shielding, USB mount, and Qt config live in mixxx_launcher.sh.
tkgl_mod_mixxx() {
    log "=== mod_mixxx: launching Mixxx ==="

    systemctl is-active --quiet mixxx-app.service && { log "already active"; return 0; }

    # Stop Engine OS — both use ALSA hw:JP11,0
    systemctl is-active --quiet engine.service && { log "stopping engine"; systemctl stop engine.service; }

    # Verify SD card launcher exists
    [ -x /media/az01-internal/mixxx/mixxx_launcher.sh ] || { log "ERROR: SD launcher not found"; return 1; }

    ENTRYPOINT=/data/mixxx/mixxx
    [ -x "$ENTRYPOINT" ] || { log "ERROR: entrypoint not executable"; return 1; }
    LOGFILE="$TKGL_LOG/mixxx_$(date +%Y%m%d_%H%M%S).log"

    # GPU: Mali permissions + performance governor
    [ -c /dev/mali0 ] && chmod 666 /dev/mali0 2>/dev/null
    for g in /sys/class/devfreq/*mali*/governor /sys/class/devfreq/*gpu*/governor; do
        [ -f "$g" ] && echo performance > "$g" 2>/dev/null
    done

    # Pin non-audio IRQs to CPU 0 (skip system IRQs 0-31 and audio DMA IRQ 45)
    for irq in /proc/irq/*/smp_affinity; do
        n=$(echo "$irq" | grep -oE '[0-9]+')
        [ "$n" -le 31 ] 2>/dev/null && continue
        [ "$n" = "45" ] && continue
        echo 1 > "$irq" 2>/dev/null
    done

    systemctl start powerbutton-monitor.service 2>/dev/null || true

    log "starting mixxx-app; log: $LOGFILE"
    systemd-run --unit=mixxx-app --collect --service-type=exec \
        --property=RuntimeDirectory=mixxx --property=RuntimeDirectoryMode=0700 \
        --working-directory=/data/mixxx \
        --setenv=HOME=/root --setenv=XDG_RUNTIME_DIR=/run/mixxx \
        -- /bin/sh -c "exec '$ENTRYPOINT' > '$LOGFILE' 2>&1"

    systemctl is-active --quiet mixxx-app.service && log "mixxx-app started" || { log "ERROR: failed"; return 1; }
}

tkgl_mod_mixxx
