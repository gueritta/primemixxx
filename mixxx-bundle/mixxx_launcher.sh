#!/bin/sh
# MIXXX Launcher — Denon Prime Go / Prime 4 (SD card)
# Auto-detects device model via DRM connector and applies correct display settings.
# Sets env for SD card's bundled Qt 5.15.8 + eglfs_mali, CPU shielding,
# and USB music library mount.

# Guard against duplicate instances (systemd-run may restart before old process exits)
if pidof mixxx > /dev/null 2>&1; then
    echo "Mixxx already running, exiting."
    exit 0
fi

# Detect device model from DRM connector
# Prime Go  = DSI-1  (rotation 90,  no vsync needed)
# Prime 4   = LVDS-1 (rotation 270, needs SWAPINTERVAL=1)
detect_device() {
    if [ -f /sys/class/drm/card0-DSI-1/status ] && \
       grep -q connected /sys/class/drm/card0-DSI-1/status 2>/dev/null; then
        DEVICE="primego"
        ROTATION=90
        SWAPINTERVAL=0
    else
        DEVICE="prime4"
        ROTATION=270
        SWAPINTERVAL=1
    fi
    echo "[launcher] detected device: $DEVICE (rotation=$ROTATION swapinterval=$SWAPINTERVAL)"
}
detect_device

BUNDLE=/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle
MUSIC_DIR="$BUNDLE/music"

mount_usb_music() {
    [ -d "$MUSIC_DIR" ] || mkdir -p "$MUSIC_DIR"
    mountpoint -q "$MUSIC_DIR" && return 0
    for dev in /dev/sda1 /dev/sdb1; do
        if [ -b "$dev" ]; then
            mount -o ro "$dev" "$MUSIC_DIR" 2>/dev/null && return 0
        fi
    done
    return 1
}
mount_usb_music

# Work around kernel 5.10 hidraw netlink bug — udev's hid_enumerate() hangs without NLMSG_DONE
export LD_PRELOAD=$BUNDLE/lib/no_hid_poll.so
# Qt 5.15.8 plugins from SD card (NOT device's Qt 5.15.2 — eglfs_emu can't take over fbcon)
export QT_PLUGIN_PATH="$BUNDLE/qt-plugins"
# SD Qt 5.15.8 first, device Qt 5.15.2 fallback, then system libs
export LD_LIBRARY_PATH="$BUNDLE/lib:/usr/qt/lib:/usr/lib"
# EGLFS full-screen compositor (no X11/Wayland on embedded display)
export QT_QPA_PLATFORM=eglfs
# Mali GPU integration (r1p0 DDK via /usr/lib/libmali.so.14.0 symlinks)
export QT_QPA_EGLFS_INTEGRATION=eglfs_mali
# Vsync: Prime 4 DSI-1 needs it to prevent tearing; Prime Go LVDS-1 doesn't
export QT_QPA_EGLFS_SWAPINTERVAL="$SWAPINTERVAL"
# Display rotation: Prime Go LVDS-1=90°, Prime 4 DSI-1=270°
export QT_QPA_EGLFS_ROTATION="$ROTATION"
# System fonts from device rootfs (not bundled on SD card)
export QT_QPA_FONTDIR=/usr/share/fonts
# Touchscreen on /dev/input/event0, hardware keyboard on /dev/input/event1
export QT_QPA_GENERIC_PLUGINS="evdevtouch:/dev/input/event0 evdevkeyboard:/dev/input/event1"
# Touch calibration: rotate matches display rotation, min/max match ILI2117 sensor bounds
export QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS="/dev/input/event0:rotate=$ROTATION:minX=0:maxX=1280:minY=0:maxY=800"
# Physical screen dimensions in mm (Prime Go 5" display)
export QT_QPA_EGLFS_PHYSICAL_WIDTH=155
export QT_QPA_EGLFS_PHYSICAL_HEIGHT=98
# MIXXX config/cache in tmpfs (avoids SD card wear from constant writes)
export HOME=/tmp
export XDG_RUNTIME_DIR=/tmp

# Disable RT throttling — audio threads need 100% of their timeslice.
# Without this, the kernel reserves 5% of CPU time for non-RT tasks,
# starving the audio engine under load.
echo -1 > /proc/sys/kernel/sched_rt_runtime_us

# Launch MIXXX pinned to CPU cores 2-3 (audio-dedicated cores).
# We do NOT set RT priority on the main process — that would cause ALL
# 44+ child threads to inherit SCHED_FIFO and compete with audio.
# Instead, we selectively boost only the critical audio threads.
taskset -c 2,3 $BUNDLE/bin/mixxx -platform eglfs --settingsPath $BUNDLE/settings --resourcePath $BUNDLE "$@" &
MIXPID=$!

# Audio-critical threads that get SCHED_FIFO and stay on cores 2-3:
# Non-audio threads to banish to cores 0-1 at SCHED_OTHER:
BANISH_PATTERNS="mali-|CachingReader|QEvdevTouch|StatsManager|QDBus|VinylControl|LibraryScanner|BrowseThread|AnalyzerThread|Controller$|VSync|gmain|gdbus|Thread \(pooled\)|QQuickPixmapRea|QQmlThread"

for i in $(seq 1 12); do
    sleep 1
    for tid in $(ls /proc/$MIXPID/task/ 2>/dev/null); do
        name=$(cat /proc/$MIXPID/task/$tid/comm 2>/dev/null)
        case "$name" in
            EngineWorkerSch|EngineSideChain)
                chrt -f -p 98 $tid 2>/dev/null
                taskset -p 0x0C $tid 2>/dev/null
                ;;
        esac
        if echo "$name" | grep -qE "$BANISH_PATTERNS"; then
            chrt -o -p 0 $tid 2>/dev/null
            taskset -p 0x03 $tid 2>/dev/null
        fi
    done
done
chrt -f -p 1 $MIXPID 2>/dev/null
taskset -p 0x0C $MIXPID 2>/dev/null

wait $MIXPID
