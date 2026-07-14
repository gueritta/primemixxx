#!/bin/sh
# MIXXX Launcher — Denon Prime Go (SD card)
# Sets env for SD card's bundled Qt 5.15.8 + eglfs_mali, CPU shielding,
# and USB music library mount.
BUNDLE=/media/az01-internal/mixxx
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

export LD_PRELOAD=$BUNDLE/lib/no_hid_poll.so
export QT_PLUGIN_PATH="$BUNDLE/qt-plugins"
export LD_LIBRARY_PATH="$BUNDLE/lib:/usr/qt/lib:/usr/lib"
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_mali
export QT_QPA_EGLFS_ROTATION=90
export QT_QPA_FONTDIR=/usr/share/fonts
export QT_QPA_GENERIC_PLUGINS="evdevtouch:/dev/input/event0 evdevkeyboard:/dev/input/event1"
export QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=/dev/input/event0:rotate=90
export QT_QPA_EGLFS_PHYSICAL_WIDTH=155
export QT_QPA_EGLFS_PHYSICAL_HEIGHT=98
export HOME=/tmp
export XDG_RUNTIME_DIR=/tmp

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
