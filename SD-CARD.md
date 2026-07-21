# SD Card Reconstruction — Denon Prime GO (`/media/az01-internal/mixxx/`)

## Identity

- **Mount point:** `/media/az01-internal` (internal SD card, mounted by `edisksd` service)
- **Activation:** `echo external > /sys/bus/platform/devices/sd-mux/state`
- **Evidence:** The `mount.sh` script creates `media/az01-internal` as the SD card mount target. Stock firmware's `setup-prerequisites.sh` activates the SD mux. This IS the real SD card, not a partition.

## Local Source Copy

The `mixxx-bundle/` directory in this repo is the **local mirror** of what was SCP'd to the device. It was created by `scripts/collect-mixxx-bundle.sh` from Buildroot output, then deployed via `scripts/deploy-to-device.sh` using SCP.

## Directory Structure (Binary Layout)

**Important:** The MIXXX binary lives in `lib/bin/mixxx` (~10 MB stripped). The `bin/` directory contains symlinks pointing into `lib/bin/`:

```
/media/az01-internal/mixxx/
├── mixxx.real                             # 17 MB binary — DO NOT USE (causes EGLFS crash)
├── bin/
│   ├── mixxx -> ../lib/bin/mixxx          # Symlink to working 10 MB binary
│   ├── controllers -> ../lib/bin/controllers
│   ├── effects -> ../lib/bin/effects
│   ├── keyboard -> ../lib/bin/keyboard
│   ├── skins -> ../lib/bin/skins
│   └── translations -> ../lib/bin/translations
├── lib/
│   ├── bin/
│   │   ├── mixxx                          # MIXXX 2.5.6 ARMv7 binary (~10 MB, working)
│   │   ├── mixxx.bak                      # Backup copy
│   │   ├── controllers -> ../controllers  # Symlink to parent dir
│   │   ├── effects -> ../effects
│   │   ├── keyboard -> ../keyboard
│   │   ├── skins -> ../skins
│   │   └── translations -> ../translations
│   ├── nodialog.so                        # LD_PRELOAD dialog blocker (unused by default)
│   ├── ...                                # 66 shared libraries
│   ├── libQt5*.so.5                       # Qt 5.15.8 (bundled, not device's 5.15.2)
│   ├── libEGL.so, libGLESv2.so, libGLESv1_CM.so  # Mali r1p0 shims → /usr/lib/libmali.so
│   ├── libasound.so.2                     # ALSA
│   ├── libportaudio.so.2, libportmidi.so.2  # Audio I/O
│   ├── libFLAC.so.12, libogg.so.0, libvorbis*.so  # Audio codecs
│   ├── libmp3lame.so.0, libmad.so.0       # MP3 codecs
│   ├── libsndfile.so.1                    # Sample file I/O
│   ├── libebur128.so.1                    # Loudness normalization
│   ├── libkeyfinder.so.2, libchromaprint.so.1  # Key/BPM detection
│   ├── librubberband.so.2                 # Time stretching
│   ├── libfftw3.so.3                      # FFT
│   ├── libqt5keychain.so.1                # Credential storage
│   ├── libprotobuf-lite.so.32             # Protocol Buffers
│   ├── liblilv-0, libserd-0, libsord-0, libsratom-0  # LV2 plugin host
│   ├── libSoundTouch.so.1                 # Pitch/tempo
│   ├── libid3tag.so.0, libtag.so.1        # Metadata
│   ├── libmodplug.so.1, libmp4v2.so.2     # Tracker/MP4
│   ├── libopus.so.0, libopusfile.so.0    # Opus codec
│   ├── libsystemd.so.0, libudev.so.1      # System integration
│   ├── libdbus-1.so.3                     # D-Bus
│   ├── libglib-2.0, libgio-2.0, libgobject-2.0, libgmodule-2.0, libgthread-2.0  # GLib
│   ├── libpcre.so.1, libpcre2-16.so.0     # Regex
│   ├── libffi.so.8                        # Foreign function interface
│   ├── libz.so.1                          # Compression
│   ├── libblkid.so.1, libmount.so.1       # Block device/mount
│   ├── libcap.so.2                        # POSIX capabilities
│   ├── libcrypto.so.1.1, libssl.so.1.1    # OpenSSL
│   ├── libsecret-1.so.0                   # Secret service
│   ├── libupower-glib.so.3                # Power management
│   └── libusb-1.0.so.0                    # USB
├── qt-plugins/                            # Qt 5.15.8 platform plugins
│   ├── platforms/
│   │   ├── libqeglfs.so                   # EGLFS (main)
│   │   ├── libqminimalegl.so
│   │   ├── libqminimal.so
│   │   └── libqoffscreen.so
│   ├── egldeviceintegrations/
│   │   └── libqeglfs-mali-integration.so   # Custom Mali integration (CRITICAL for display)
│   ├── generic/
│   │   ├── libqevdevkeyboardplugin.so
│   │   ├── libqevdevmouseplugin.so
│   │   ├── libqevdevtabletplugin.so
│   │   └── libqevdevtouchplugin.so        # Touchscreen
│   ├── imageformats/
│   │   ├── libqico.so
│   │   └── libqsvg.so
│   ├── iconengines/
│   │   └── libqsvgicon.so
│   ├── sqldrivers/
│   │   └── libqsqlite.so
│   └── platformthemes/
│       └── libqxdgdesktopportal.so
├── mixxx-mapping/                         # Controller mappings
│   ├── Denon-Prime-4*.xml, *-scripts.js   # Prime 4 mapping
│   └── prime-go/Denon-Prime-Go*.xml, *-scripts.js  # Prime GO mapping
├── mixxx_launcher.sh                      # Wrapper: stops engine, sets env, CPU shielding
├── settings/                              # MIXXX runtime settings (created at launch)
│   └── mixxx.cfg
├── share/
│   └── mixxx/                             # Resource path (skins, translations, etc.)
└── backup/                                # Device binary backup
    └── mixxx.bak                          # MD5: a0365bdce2162c1a09d0ba77ab4af227
```

## Launcher Script (Working Version on Device)

The actual working launcher on the device is minimal — the TKGL bootstrap framework
handles USB mounts, seed DB, and GPU governor. This script only sets environment
variables and launches MIXXX. **Located on SD card at `mixxx_launcher.sh`.**

The entry point on internal storage (`/data/mixxx/mixxx`) is a thin delegation:
```sh
#!/bin/sh
# TKGL entry point - delegates to SD card launcher
exec /media/az01-internal/mixxx/mixxx_launcher.sh "$@"
```

```sh
#!/bin/sh
# MIXXX Launcher — Denon Prime Go (SD card)
# Sets env for SD card's bundled Qt 5.15.8 + eglfs_mali, CPU shielding,
# and USB music library mount.
BUNDLE=/media/az01-internal/mixxx
MUSIC_DIR="$BUNDLE/music"

# USB Music Library: mount USB drive to music directory if present
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
export QT_QPA_GENERIC_PLUGINS=evdevtouch:/dev/input/event0,evdevkeyboard:/dev/input/event1
export QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=/dev/input/event0:rotate=90
export QT_QPA_EGLFS_PHYSICAL_WIDTH=155
export QT_QPA_EGLFS_PHYSICAL_HEIGHT=98
# PA_ALSA_PLUGHW=1  # disabled: use hw: device directly, avoids software conversion
export HOME=/tmp
export XDG_RUNTIME_DIR=/tmp

# Launch at SCHED_OTHER — NOT SCHED_FIFO 99! Setting RT on the main process
# causes ALL 44+ child threads (Mali GPU, touchscreen, CachingReader, Qt pool,
# GLib, LibraryScanner, etc.) to inherit SCHED_FIFO and compete with audio.
# Instead, selectively boost only the 2 critical audio engine threads.
taskset -c 2,3 $BUNDLE/bin/mixxx -platform eglfs --settingsPath $BUNDLE/settings --resourcePath $BUNDLE "$@" &
MIXPID=$!

# Audio-critical threads: SCHED_FIFO 98, pinned to cores 2-3
# All other threads: SCHED_OTHER, banished to cores 0-1
BANISH="mali-|CachingReader|QEvdevTouch|StatsManager|QDBus|VinylControl|\
LibraryScanner|BrowseThread|AnalyzerThread|Controller$|VSync|gmain|gdbus|\
Thread \(pooled\)|QQuickPixmapRea|QQmlThread"

for i in $(seq 1 12); do
    sleep 1
    for tid in $(ls /proc/$MIXPID/task/ 2>/dev/null); do
        name=$(cat /proc/$MIXPID/task/$tid/comm 2>/dev/null)
        case "$name" in EngineWorkerSch|EngineSideChain)
            chrt -f -p 98 $tid 2>/dev/null
            taskset -p 0x0C $tid 2>/dev/null ;; esac
        if echo "$name" | grep -qE "$BANISH"; then
            chrt -o -p 0 $tid 2>/dev/null
            taskset -p 0x03 $tid 2>/dev/null
        fi
    done
done
# Main thread: low RT for MIDI/UI responsiveness on audio cores
chrt -f -p 1 $MIXPID 2>/dev/null
taskset -p 0x0C $MIXPID 2>/dev/null

wait $MIXPID
```

### Key differences from the repo's old template:
| Setting | Old (wrong) | Actual (working) |
|---------|-------------|------------------|
| `--resourcePath` | `$BUNDLE/bin` | `$BUNDLE` (root) |
| `HOME` | `/root` | `/tmp` |
| `LD_LIBRARY_PATH` | `$BUNDLE/lib:/usr/lib` | `$BUNDLE/lib:/usr/qt/lib:/usr/lib` |
| `QT_QPA_EGLFS_KMS_ATOMIC` | `1` | not set |
| `QT_QPA_GENERIC_PLUGINS` | `evdevtouch:evdevmouse:evdevkeyboard` | `evdevtouch:/dev/input/event0,evdevkeyboard:/dev/input/event1` |
| `LD_PRELOAD` | not set | `$BUNDLE/lib/no_hid_poll.so` |
| CPU shielding | not set | `taskset -c 2,3` + engine thread RT boost (see launcher) |
| USB music mount | manual | `mount_usb_music()` in launcher |
| `PA_ALSA_PLUGHW` | `1` | disabled (use hw: directly) |

## Audio Optimization Stack

### Thread Scheduling
- **2 audio threads** at SCHED_FIFO 98 on dedicated cores 2-3: EngineWorkerSch, EngineSideChain
- **Main thread** at SCHED_FIFO 1 on cores 2-3 (low RT for MIDI/UI responsiveness)
- **44+ non-audio threads** (Mali GPU, touchscreen, CachingReader, Qt pool, GLib, etc.)
  banished to cores 0-1 at SCHED_OTHER via launcher post-launch loop
- **RT throttling disabled** (`sched_rt_runtime_us=-1`)

### IRQ Affinity
- All non-audio IRQs (GPU, USB, MMC) pinned to CPU 0 via TKGL module at boot
- Audio DMA IRQ (45) left untouched — stays on default core with audio engine

### ALSA Configuration
- Device: `hw:JP11,0` (direct, no plughw conversion)
- Format: S32_LE, 4 channels, 44100 Hz
- latency=5: period_size=1024 (23.2ms), buffer_size=2048 (46.4ms total)

### Kernel Limitations (unfixable without rebuild)
- `CONFIG_NO_HZ_FULL` not set: 1ms timer tick fires on ALL cores including isolated 2-3
- `CONFIG_HZ=1000`: 1kHz scheduler tick — ~0.1-0.2% CPU steal on audio cores
- No `rcu_nocbs`: RCU callbacks can land on audio cores
- `isolcpus=1-3` in cmdline but incomplete without `nohz_full` companion

## Systemd Service

There are two service paths:

### 1. Firmware overlay: `/usr/lib/systemd/system/mixxx.service`
The canonical service definition in the Buildroot overlay. Sources `mixxx_launcher.sh`.

### 2. TKGL Bootstrap: `/etc/systemd/system/tkgl-mixxx.service`
The actual service used at boot (TKGL framework). Can be masked with
`systemctl mask tkgl-mixxx` or overridden by the `mixxx` service.

### Boot chain:
```
tkgl-mixxx.service → /data/tkgl-bootstrap-launcher → tkgl_mod_mixxx.sh
  → systemd-run --unit=mixxx-app → /data/mixxx/mixxx → SD card launcher → MIXXX
```

### Important: `mixxx-app.service` and masking

The TKGL module uses `systemd-run --unit=mixxx-app` to create a transient unit.
If the name is masked (`/dev/null`), `systemd-run` fails silently and MIXXX
won't start at boot. If masked, unmask with:
```bash
systemctl unmask mixxx-app.service 2>/dev/null || true
```

### To re-enable the simple service:

## USB MP3 Library: Sandbox Bypass & Seed DB

### Problem
1. MIXXX sandbox silently blocks vfat filesystems → USB library won't scan
2. First-run wizard (which imports config→DB) is skipped by EGLFS dialog suppression

### Solution
1. **Mount USB to ext4 path** bypasses sandbox: `mount -o ro /dev/sda1 /media/az01-internal/mixxx/music`
2. **Seed DB** (`mixxxdb.seed`) pre-populated with `directories` table entry pointing to the music path
3. **Wrapper** restores seed DB if current DB is missing or < 5KB

### CRITICAL: Library directories live in SQLite, NOT mixxx.cfg
The `directories` table in `mixxxdb.sqlite` stores music library paths.
The `[Recording] Directory` in `mixxx.cfg` is ONLY for saving recordings — it has
nothing to do with music library scanning. `RescanOnStartup 1` does nothing
if the `directories` table is empty.

To verify/repair the library directory entry:
```bash
sqlite3 /media/az01-internal/mixxx/settings/mixxxdb.sqlite \
  "SELECT directory FROM directories;"
```
If empty, insert the library path:
```bash
sqlite3 /media/az01-internal/mixxx/settings/mixxxdb.sqlite \
  "INSERT INTO directories (id, directory, volume) VALUES (1, '/media/az01-internal/mixxx/music', 1);"
```
Then restart MIXXX with `RescanOnStartup 1` in `[Library]` section of `mixxx.cfg`.
Set back to `0` after scan completes to avoid re-scanning every boot.

### Config (mixxx.cfg)
```ini
[Config]
FirstRun=1
HasScreenedForLibraryDir=1
[Library]
Directory[0]=/media/az01-internal/mixxx/music
RescanOnStartup=0
```

## Switcher Scripts (on device)

### `/usr/bin/switch-to-mixxx`
```sh
#!/bin/sh
mount -o remount,rw / 2>/dev/null
systemctl stop engine
/media/az01-internal/mixxx/mixxx_launcher.sh
```

### `/usr/bin/switch-to-engine`
```sh
#!/bin/sh
killall mixxx 2>/dev/null
systemctl start engine
```

## CRITICAL: System Libs NOT on SD Card

These 9 libraries are provided by the device's `/lib` — bundling them causes segfaults from kernel ABI mismatch:
- `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`
- `librt.so.1`, `libstdc++.so.6`, `libgcc_s.so.1`
- `ld-linux-armhf.so.3`, `libatomic.so.1`

The `fix-device-libs.sh` script removes these from the bundle after collection.

## Known Issues (Current State)

1. **Two binaries exist:** `mixxx.real` (17 MB) at the root is a DIFFERENT build that crashes with `EGLFS: OpenGL windows cannot be mixed with others`. The working binary is `lib/bin/mixxx` (~10 MB). `bin/mixxx` is a symlink pointing to `lib/bin/mixxx` — do NOT change it to point to `mixxx.real`.
2. **Screen rotation:** `QT_QPA_EGLFS_ROTATION=90` — Qt's logical screen is **1280×800 landscape**; the GPU framebuffer is 800×1280 portrait and the display controller rotates it. Touchscreen uses `rotate=90` to map the ILI2117's physical landscape coordinates to Qt's coordinate system.
3. **Mali DDK mismatch:** Bundled `libEGL.so`/`libGLESv2.so` from Buildroot target r0p0; device has r1p0. **FIXED:** Symlinks on SD card point all EGL/GLES libs to `/usr/lib/libmali.so.14.0`.
4. **Qt version:** SD card bundles Qt 5.15.8. Device's native Qt 5.15.2 is **NOT used**. Launcher includes `/usr/qt/lib` in `LD_LIBRARY_PATH` (between bundle and system paths) as fallback.
5. **WiFi power save:** Must run `iw dev wlan0 set power_save off` — not persistent across reboots.
6. **nodialog.so:** Present at `lib/nodialog.so` but NOT used in the default launcher. The `mixxx-svc` fallback launcher uses it. The TKGL bootstrap path does not.

## Deployment Scripts

- `scripts/collect-mixxx-bundle.sh` — Gathers MIXXX + deps from Buildroot output into `mixxx-bundle/`
- `scripts/deploy-to-device.sh` — SCPs bundle to device, installs systemd service + switchers, backs up existing SD card
- `scripts/fix-device-libs.sh` — Removes system-critical libs from deployed bundle on device
- `scripts/quick-fix-deploy.sh` — Redeploys only changed files for fast iteration
