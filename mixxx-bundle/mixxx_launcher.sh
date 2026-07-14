#!/bin/sh
# MIXXX Launcher — Denon Prime Go (SD card)
# Sets env for SD card's bundled Qt 5.15.8 + eglfs_mali, CPU shielding,
# and USB music library mount.
BUNDLE=/media/az01-internal/mixxx
MUSIC_DIR="$BUNDLE/music"

# USB Music Library: mount USB drive to music directory if present.
# Engine OS stores its library at /Engine Library/ and /Music/ on the USB key.
# MIXXX scans $MUSIC_DIR for tracks — mounting a USB key there makes
# the Engine OS collection available transparently.
mount_usb_music() {
    [ -d "$MUSIC_DIR" ] || mkdir -p "$MUSIC_DIR"
    # Already mounted?
    mountpoint -q "$MUSIC_DIR" && return 0
    # Try common USB partitions
    for dev in /dev/sda1 /dev/sdb1; do
        if [ -b "$dev" ]; then
            mount -o ro "$dev" "$MUSIC_DIR" 2>/dev/null && return 0
        fi
    done
    return 1
}
mount_usb_music

# Workaround: kernel 5.10.109-inmusic-rt64 never sends NLMSG_DONE for the
# hidraw netlink dump, so udev's hid_enumerate() hangs forever. The LD_PRELOAD
# library skips the hidraw udev scan and caps infinite poll() timeouts.
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
# PA_ALSA_PLUGHW=1  # disabled: use hw: device directly, avoids software conversion layer
export HOME=/tmp
export XDG_RUNTIME_DIR=/tmp

# Launch MIXXX pinned to CPU cores 2-3 (audio-dedicated cores).
# We do NOT set RT priority on the main process — that would cause ALL
# 44+ child threads (Mali GPU, touchscreen, CachingReader, Qt pool, GLib,
# LibraryScanner, etc.) to inherit SCHED_FIFO 99 and compete with audio.
# Instead, we selectively boost only the 2 critical audio threads.
taskset -c 2,3 $BUNDLE/bin/mixxx -platform eglfs --settingsPath $BUNDLE/settings --resourcePath $BUNDLE "$@" &
MIXPID=$!

# Audio-critical threads that get SCHED_FIFO and stay on cores 2-3:
AUDIO_THREADS="EngineWorkerSch|EngineSideChain"
# Non-audio threads to banish to cores 0-1 at SCHED_OTHER:
BANISH_PATTERNS="mali-|CachingReader|QEvdevTouch|StatsManager|QDBus|VinylControl|\
LibraryScanner|BrowseThread|AnalyzerThread|Controller$|VSync|gmain|gdbus|\
Thread \(pooled\)|QQuickPixmapRea|QQmlThread"

for i in $(seq 1 12); do
    sleep 1
    for tid in $(ls /proc/$MIXPID/task/ 2>/dev/null); do
        name=$(cat /proc/$MIXPID/task/$tid/comm 2>/dev/null)
        case "$name" in
            EngineWorkerSch|EngineSideChain)
                # Audio engine: SCHED_FIFO prio 98, locked to cores 2-3
                chrt -f -p 98 $tid 2>/dev/null
                taskset -p 0x0C $tid 2>/dev/null
                ;;
        esac
        # Banish all known non-audio threads to cores 0-1 at SCHED_OTHER
        if echo "$name" | grep -qE "$BANISH_PATTERNS"; then
            chrt -o -p 0 $tid 2>/dev/null
            taskset -p 0x03 $tid 2>/dev/null
        fi
    done
done
# Give main thread low RT priority for MIDI/event responsiveness
chrt -f -p 1 $MIXPID 2>/dev/null
taskset -p 0x0C $MIXPID 2>/dev/null

wait $MIXPID
