# Denon Prime 4 — Project Onboarding

## What This Project Is

Custom firmware for Denon DJ Prime 4 / Prime Go hardware that deploys
**MIXXX** (open-source DJ software) alongside or instead of the stock Engine OS.
MIXXX runs from an internal SD card without stripping the original firmware —
the two are switchable on demand.

---

## Hardware

| Component | Detail |
|---|---|
| **SoC** | Rockchip RK3288 ARMv7 (Cortex-A17, 4 cores) |
| **GPU** | Mali-T76x (4 cores, r1p0 0x0750) |
| **Kernel** | `6.1.111-inmusic-2024-09-19-rt41` with `PREEMPT_RT` |
| **OS** | Stripped-down Buildroot Linux — no X11, no Wayland |
| **Display** | 7-inch touchscreen, LVDS-1, portrait framebuffer 800×1280 rotated to 1280×800 landscape by display controller |
| **Touchscreen** | ILI2117 on `/dev/input/event0` |
| **Audio** | XMOS XS1-U6A USB audio controller → AKM AK4621 CODEC + AK4413 DAC |
| **MIDI** | Internal USB MIDI (platters, faders, pads all exposed as MIDI controllers) |

---

## Architecture Decisions

### Why Qt 5.15.8 on SD card (not device Qt 5.15.2)

The SD card bundles its own Qt 5.15.8 with a custom-built `libqeglfs-mali-integration.so`.
Device's native Qt 5.15.2 uses `eglfs_emu` which can't take over the display from fbcon
and produces a black screen. The SD card's Qt was compiled from the same Buildroot
environment as MIXXX, ensuring ABI compatibility. Device Qt 5.15.2 at `/usr/qt/lib`
is included in `LD_LIBRARY_PATH` as a fallback (after the SD bundle, before system libs).

### Why PREEMPT_RT

The kernel is built with full preemption (`CONFIG_PREEMPT_RT`) to guarantee <5ms audio
latency. MIXXX's audio engine threads run at `SCHED_FIFO` priority 98 on dedicated
CPU cores (2-3), isolated from all other system threads. Without PREEMPT_RT, the
kernel could block the audio thread during a syscall, causing dropouts.

### Why Mali r1p0 (not Buildroot's r0p0)

The device's Mali GPU is hardware revision r1p0. Buildroot ships Mali DDK r0p0 by default.
The user-space driver (`libmali.so`) must match the kernel-space driver's ABI exactly.
A DDK mismatch causes EGL initialization failure. The fix: symlink the SD card's
`libEGL.so` and `libGLESv2.so` to the device's native `/usr/lib/libmali.so.14.0`.

### Why two MIXXX binaries exist

Buildroot produces two binaries:
- `lib/bin/mixxx` (~10 MB, stripped) — works correctly with EGLFS
- `mixxx.real` (~17 MB, unstripped) — crashes with `EGLFS: OpenGL windows cannot be mixed with others`

Only the 10 MB binary works. `bin/mixxx` must be a symlink to `../lib/bin/mixxx`.

---

## Boot Chain

```
Device power-on
  → U-Boot → Linux kernel
    → systemd
      → tkgl-mixxx.service (enabled)
        → /data/tkgl-bootstrap-launcher
          → sources tkgl-bootstrap/modules/mod_mixxx/tkgl_mod_mixxx.sh
            → systemd-run --unit=mixxx-app -- /data/mixxx/mixxx
              → /data/mixxx/mixxx (116-byte delegation script)
                → /media/az01-internal/mixxx/mixxx_launcher.sh (SD card)
                  → USB bind-mount + seed DB restore + env setup
                    → MIXXX binary with CPU shielding
```

### Entry Point: `/data/mixxx/mixxx`

A thin delegation script on internal storage:
```sh
#!/bin/sh
exec /media/az01-internal/mixxx/mixxx_launcher.sh "$@"
```

This exists on internal storage so it survives SD card removal. All real logic
lives on the SD card where it can be updated independently.

### TKGL Bootstrap Framework

TKGL is a modular boot-time script execution framework. At boot, the systemd
service launches a bootstrap binary that scans for modules and executes them.
The `mod_mixxx` module handles:

- USB drive mounting and bind-mounting to the music library path
- Seed database restoration (pre-populated SQLite DB with library directory entries)
- GPU performance governor setup
- Launching MIXXX via `systemd-run --unit=mixxx-app`

The critical property: if anything goes wrong with TKGL or the SD card, you can
unplug the SD card and reboot to stock Engine OS. The internal storage is never
modified at runtime.

### Restarting MIXXX (after skin/config changes)

MIXXX runs as a transient systemd unit (`mixxx-app.service`) launched by TKGL
via `systemd-run --unit=mixxx-app`. The boot chain is:

```
engine.service → TKGL bootstrap → tkgl_mod_mixxx.sh → systemd-run --unit=mixxx-app
```

`tkgl_mod_mixxx.sh` checks if `mixxx-app.service` is already active and skips
relaunch if so. Therefore, the ONLY correct restart sequence is:

```sh
# 1. Stop the transient unit first
systemctl stop mixxx-app.service

# 2. Trigger TKGL to recreate it
systemctl restart engine.service
```

**DO NOT** use any of these (they will silently fail to restart MIXXX):
- `systemctl restart mixxx-app.service` — TKGL sees the unit still running and skips
- `pkill mixxx` + `systemctl restart engine.service` — orphaned unit stays "active", TKGL skips
- `kill -9 <pid>` — same problem as pkill

### CPU Shielding Strategy

MIXXX launches with `taskset -c 2,3` to isolate on cores 2-3. After launch, a
post-launch loop in the launcher:

1. **Audio-critical threads** (EngineWorkerSch, EngineSideChain): boosted to
   `SCHED_FIFO` priority 98, pinned to cores 2-3
2. **Non-audio threads** (Mali GPU, touchscreen, CachingReader, Qt pool, GLib, etc.):
   set to `SCHED_OTHER`, banished to cores 0-1
3. **Main thread**: `SCHED_FIFO` priority 1 on cores 2-3 (low RT for MIDI/UI)

IRQ affinity: all non-audio IRQs (GPU, USB, MMC) are pinned to CPU 0 at boot.

For full details, see [`docs/launch.md`](launch.md).

---

## SD Card Layout Rationale

The SD card at `/media/az01-internal/mixxx/` (mounted as `$BUNDLE`) contains
everything MIXXX needs at runtime:

```
$BUNDLE/
├── lib/bin/mixxx          # Working binary (~10 MB)
├── bin/mixxx → ../lib/bin/mixxx
├── lib/                   # 66+ shared libraries (Qt 5.15.8, ALSA, codecs, etc.)
├── qt-plugins/            # Qt 5.15.8 EGLFS plugins (platforms, integrations)
├── mixxx-mapping/         # MIDI controller mappings (XML + JS)
├── mixxx_launcher.sh      # SD card launcher with env vars + CPU shielding
├── settings/              # MIXXX runtime settings and database
└── share/mixxx/           # Resource path (skins, translations)
```

**Why the SD card?** The device's internal storage is limited and shared with
Engine OS. The SD card provides:
- Independent updates without touching internal storage
- Fallback: unplug SD card → stock Engine OS boots normally
- Space for the full Qt 5.15.8 bundle (66+ .so files)
- Persistence of MIXXX settings and library database

For the full directory tree and library listing, see [`SD-CARD.md`](../SD-CARD.md).

---

## MIDI Mapping Conventions

All controls on the Prime Go (platters, faders, pads, buttons, encoders) are
exposed as internal USB MIDI devices. The Engine OS firmware uses QML-based
mappings; MIXXX uses XML + JavaScript.

### Channel Layout

| MIDI Channel | Purpose |
|:---:|:---|
| 1 | Mixer Channel 1 (PFL, EQ, fader, sweep FX) |
| 2 | Mixer Channel 2 |
| 3 | Left Deck (transport, pads, jog, tempo) |
| 4 | Right Deck (transport, pads, jog, tempo) |
| 5 | DJ FX (select, time, wet/dry, activate) |
| 16 | Global (back, forward, browse, view, shift, load) |

### Deck Controls (Channels 3 & 4)

| Control | Note (dec) | Notes |
|---------|:---:|:---|
| Load | 1 / 2 | Left=1, Right=2 |
| Sync | 8 | Hold = KeySync |
| Cue | 9 | Shift = Set Cue Point |
| Play | 10 | |
| Pad Mode CUES | 11 | Alt = STEMS |
| Pad Mode LOOPS | 12 | Alt = AUTO |
| Pad Mode ROLL | 13 | Shift = SAMPLER |
| Action Pads | 15–22 | 8 velocity-sensitive pads |
| Pitch Bend – | 29 | |
| Pitch Bend + | 30 | |
| Jog Touch | 33 | |
| Vinyl | 35 | Hold = GridCueEdit, Shift = SlipMode |
| AutoLoop Push | 39 | Shift = IncreaseBeatJumpSize |
| Tempo Slider | CC 0x1F / 0x4B | Upper inverted |
| AutoLoop Turn | CC 0x20 | Shift = BeatJump |
| Jog Wheel | CC 0x37 / 0x4D | |

### Mixer Channels (Channels 1 & 2)

| Control | Note/CC |
|---------|:---:|
| PFL (Cue Monitor) | Note 13 |
| Trim (Gain) | CC 3 |
| Treble (High EQ) | CC 4 |
| Mid EQ | CC 6 |
| Bass (Low EQ) | CC 8 |
| Channel Fader | CC 14 |
| Sweep FX Knob | CC 11 |
| Sweep FX Select | Notes 14, 15 |

### DJ FX (Channel 5)

| Control | Note/CC |
|---------|:---:|
| FX Select Push | Note 7 |
| FX Select Turn | CC 33 |
| FX Time Push | Note 8 |
| FX Time Turn | CC 34 |
| FX Wet/Dry | CC 4 |
| FX Activate | Note 6 |
| FX Assign 1/2 | Notes 11, 12 |

### Global (Channel 16)

| Control | Note/CC |
|---------|:---:|
| Back | Note 3 |
| Forward | Note 4 |
| Browse Encoder Push | Note 6 |
| Browse Encoder Turn | CC 5 |
| View | Note 7 |
| Shift | Note 8 |
| Eject/Source | Note 20 |
| Crossfader | CC 14 |
| Cue Mix | CC 12 |
| Cue Gain | CC 13 |

For the complete MIDI reference and LED protocols, see [`docs/midi.md`](midi.md)
and [`docs/hardware-reference.md`](hardware-reference.md).

---

## Build Pipeline Overview

### Prerequisites

- Buildroot 2021.02.10
- QEMU ARM user-mode emulation with binfmt
- u-boot tools, 7-zip, base development packages

### Build Steps

```bash
# 1. Unpack original firmware
./unpack.sh

# 2. Clone matching Buildroot
./clone-buildroot.sh

# 3. Build toolchain + packages (requires sudo for loopback mount)
./compile-buildroot.sh

# 4. Pack modified images into firmware
./pack.sh
```

### MIXXX Bundle Pipeline

```bash
# 1. Collect MIXXX + dependencies from Buildroot output
./scripts/collect-mixxx-bundle.sh

# 2. Remove system-critical libs from bundle (libc, libm, etc.)
./scripts/fix-device-libs.sh

# 3. Deploy to device via SCP
DEVICE_IP=primego.local ./scripts/deploy-to-device.sh
```

### Fast Iteration

```bash
# Redeploy only changed files (skips full bundle collection)
./scripts/quick-fix-deploy.sh
```

### Updater Tools

- **Windows (original tool):** `./unpack-updater.sh` + `./generate-updater-win.sh`
- **Cross-platform (Go):** `go/cmd/updater/` — requires Go 1.22+, MinGW-w64 (Windows) or makeself (Linux)

---

## Device Access

| Property | Value |
|---|---|
| SSH | `root@primego.local` |
| SD card mount | `/media/az01-internal/` |
| Internal storage | `/data/` |

**IP discovery:** The device advertises via mDNS as `primego.local`. Static IP may
vary by network. Use `DEVICE_IP` env var in all deployment scripts — never hardcode.

---

## Known Issues & Dead Ends

### Active Issues

1. **Missing `.midi.xml` = skin fails to render** — The controller mapping file (`Denon-Prime-Go.midi.xml`) is **critical** for proper skin rendering on the EGLFS display. Without it, MIXXX loads the skin but **skips controller initialization entirely**, and the skin only shows the toolbar (decks/waveforms/library hidden). This file must exist at the path referenced in `mixxx.cfg`'s `[ControllerPreset]` section (e.g. `/data/mixxx/settings/controllers/Denon-Prime-Go.midi.xml`). Never delete `.midi.xml` files during cleanup. See [2026-07-22 incident] for full details.

2. **Two MIXXX binaries** — only `lib/bin/mixxx` works. `mixxx.real` crashes with EGLFS error.
3. **Mali DDK mismatch** — Buildroot bundles r0p0; device is r1p0. Workaround: symlink to device's native `libmali.so.14.0`.
4. **WiFi power save** — must disable with `iw dev wlan0 set power_save off` (not persistent).
5. **Kernel limitations** — `CONFIG_NO_HZ_FULL` not set, `CONFIG_HZ=1000`, no `rcu_nocbs`. Causes ~0.1-0.2% CPU steal on audio cores. Unfixable without kernel rebuild.
6. **USB MP3 library** — MIXXX sandbox blocks vfat; workaround mounts USB to ext4 path.

### Failed Experiments (from `BROKEN_EXPERIMENTS.md`)

- **Qt 5.15.2 downgrade** — incompatible with GCC 16 host compiler. Reverted.
- **eglfs_mali rotation** — Mali ignores `QT_QPA_EGLFS_ROTATION`. Blocked.
- **SSH in custom firmware** — OpenSSH not enabled in Buildroot defconfig. Needs fix.
- **Qt rotation via QTransform** — alternative to eglfs_mali rotation, not yet attempted.

For the complete list of failed approaches, see [`BROKEN_EXPERIMENTS.md`](../BROKEN_EXPERIMENTS.md).

---

## Further Reading

| Document | Covers |
|---|---|
| [`docs/launch.md`](launch.md) | Boot chain, CPU shielding, wrapper scripts |
| [`docs/display.md`](display.md) | Mali GPU, DDK mismatch, EGLFS configuration |
| [`docs/audio.md`](audio.md) | ALSA routing, XMOS/AKM hardware chain |
| [`docs/midi.md`](midi.md) | Full MIDI control table |
| [`docs/hardware-reference.md`](hardware-reference.md) | LED protocols, SysEx format |
| [`docs/firmware.md`](firmware.md) | Firmware flashing notes |
| [`SD-CARD.md`](../SD-CARD.md) | Complete SD card layout, library listing |
| [`DEPLOY.md`](../DEPLOY.md) | Deployment workflow, troubleshooting |
| [`BROKEN_EXPERIMENTS.md`](../BROKEN_EXPERIMENTS.md) | Failed experiments — do not repeat |
