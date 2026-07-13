#!/bin/sh
# TKGL module: start Mixxx in an independent systemd cgroup.

tkgl_mod_mixxx() {
    log "=== mod_mixxx: launching Mixxx ==="

    if systemctl is-active --quiet mixxx-app.service; then
        log "mixxx-app.service is already active"
        return 0
    fi

    MIXDIR=/data/mixxx
    MIBIN=$MIXDIR/mixxx
    LOGFILE="$TKGL_LOG/mixxx_$(date +%Y%m%d_%H%M%S).log"

    if [ ! -x "$MIBIN" ]; then
        log "ERROR: Mixxx binary not executable: $MIBIN"
        return 1
    fi

    [ -c /dev/mali0 ] && chmod 666 /dev/mali0 2>/dev/null
    for governor in /sys/class/devfreq/*mali*/governor /sys/class/devfreq/*gpu*/governor; do
        [ -f "$governor" ] && echo performance > "$governor" 2>/dev/null
    done
    udevadm trigger --subsystem-match=block --action=add 2>/dev/null || true

    log "starting mixxx-app.service; log: $LOGFILE"
    systemd-run --unit=mixxx-app --collect --service-type=exec \
        --property=RuntimeDirectory=mixxx \
        --property=RuntimeDirectoryMode=0700 \
        --working-directory="$MIXDIR" \
        --setenv=LD_LIBRARY_PATH="$MIXDIR/lib:/usr/qt/lib:/usr/lib" \
        --setenv=QT_PLUGIN_PATH="$MIXDIR/qt-plugins:/usr/qt/plugins" \
        --setenv=QT_QPA_PLATFORM=eglfs \
        --setenv=QT_QPA_EGLFS_INTEGRATION=eglfs_mali \
        --setenv=QT_QPA_EGLFS_KMS_ATOMIC=1 \
        --setenv=QT_QPA_EGLFS_ROTATION=90 \
        --setenv=QT_QPA_FONTDIR=/usr/share/fonts \
        --setenv=QT_QPA_GENERIC_PLUGINS=evdevtouch:/dev/input/event0,evdevkeyboard:/dev/input/event1 \
        --setenv=QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=/dev/input/event0:rotate=0 \
        --setenv=HOME=/root \
        --setenv=XDG_RUNTIME_DIR=/run/mixxx \
        -- /bin/sh -c "exec taskset -c 2,3 chrt -f 99 '$MIBIN' -platform eglfs --settingsPath /data/mixxx/settings --controllerDebug --developer > '$LOGFILE' 2>&1"

    if systemctl is-active --quiet mixxx-app.service; then
        log "mixxx-app.service started in an independent cgroup"
    else
        log "ERROR: mixxx-app.service did not become active"
        return 1
    fi
}

tkgl_mod_mixxx
