#!/bin/sh
# MIXXX Launcher — Denon Prime Go (SD card binary + USB bind-mount)
# Uses SD card's bundled Qt 5.15.8 + custom Mali integration for working display.
# Bind-mounts USB vfat to trusted ext4 path to bypass MIXXX sandbox.
# Restores seed DB if current DB is missing/corrupted.

MIXDIR="/media/az01-internal/mixxx"
BUNDLE="$MIXDIR"
SETTINGS="$MIXDIR/settings"

# ── Wait for USB (up to 15s) ──
for i in $(seq 0 15); do
    if [ -b /dev/sda1 ]; then break; fi
    sleep 1
done

# ── Mount USB if plugged ──
if [ -b /dev/sda1 ]; then
    mkdir -p /media/AE1F-B2D6
    mount /dev/sda1 /media/AE1F-B2D6 -o ro,fmask=0022,dmask=0022 2>/dev/null || true
    if [ -d /media/AE1F-B2D6/tuv ]; then
        mkdir -p "$MIXDIR/music"
        mount --bind /media/AE1F-B2D6/tuv "$MIXDIR/music" 2>/dev/null || true
    fi
fi

# ── Restore seed DB if current DB is missing/corrupted ──
# MIXXX loads library directories from the 'directories' SQLite table,
# NOT from mixxx.cfg. A fresh DB has an empty table → scanner does nothing.
# The seed DB has the table pre-populated with the bind-mount path.
if [ ! -f "$SETTINGS/mixxxdb.sqlite" ] || [ $(stat -c%s "$SETTINGS/mixxxdb.sqlite" 2>/dev/null || echo 0) -lt 5000 ]; then
    if [ -f "$SETTINGS/mixxxdb.seed" ]; then
        cp "$SETTINGS/mixxxdb.seed" "$SETTINGS/mixxxdb.sqlite"
    fi
fi

# ── Environment: SD card's bundled Qt 5.15.8 + Mali integration ──
# CRITICAL: SD's Qt 5.15.8 libs are required for display to work.
# Device-native Qt 5.15.2 + eglfs_emu causes a black screen.
export LD_LIBRARY_PATH="$BUNDLE/lib:/usr/lib:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$BUNDLE/qt-plugins"
export QT_QPA_FONTDIR=/usr/share/fonts
export QT_QPA_GENERIC_PLUGINS=evdevtouch:evdevmouse:evdevkeyboard
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_mali
export QT_QPA_EGLFS_KMS_ATOMIC=1
export QT_QPA_EGLFS_ROTATION=90
export QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS="/dev/input/event0:rotate=90"
export QT_LOGGING_RULES="qt.qpa.evdevtouch=true;qt.qpa.input=true"

# ── GPU performance governor ──
for g in /sys/class/devfreq/*mali*/governor /sys/class/devfreq/*gpu*/governor; do
    [ -f "$g" ] && echo performance > "$g" 2>/dev/null
done

export HOME=/root
export XDG_RUNTIME_DIR=/tmp

systemctl stop engine 2>/dev/null || true
sleep 0.5

# ── CPU shielding: pin MIXXX to cores 2-3 with real-time FIFO priority 99 ──
exec taskset -c 2,3 chrt -f 99 "$BUNDLE/bin/mixxx" -platform eglfs \
    --settingsPath "$SETTINGS" \
    --resourcePath "$BUNDLE/bin" \
    "$@"
