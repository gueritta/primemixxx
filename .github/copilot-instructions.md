# Denon Prime 4 — Project Context for Copilot

## What This Is

Custom firmware for Denon DJ Prime 4 / Prime Go hardware, focused on deploying
**MIXXX** (open-source DJ software) alongside or instead of the stock Engine OS.

The device is a **Rockchip RK3288 ARMv7** (Cortex-A17) with a Mali-T76x GPU,
running a stripped-down Buildroot Linux (kernel `5.10.109-inmusic-rt64` with
`PREEMPT_RT`). No X11 or Wayland — Qt5 renders directly to framebuffer via EGLFS.

## Architecture

```
┌─────────────────────────────────────────────────┐
│ Device                                          │
│  /data/mixxx/mixxx  ← entry point (3 lines)     │
│       │                                         │
│       ▼                                         │
│  /media/az01-internal/mixxx/  ← SD card bundle  │
│       │                                         │
│       ├── lib/bin/mixxx       ← 10 MB binary    │
│       ├── lib/                ← 66+ .so files   │
│       ├── qt-plugins/         ← Qt 5.15.8 EGLFS │
│       ├── mixxx_launcher.sh   ← 14-line wrapper │
│       └── mixxx-mapping/      ← MIDI mappings   │
└─────────────────────────────────────────────────┘

Boot chain:
  tkgl-mixxx.service → tkgl-bootstrap-launcher → tkgl_mod_mixxx.sh
    → systemd-run --unit=mixxx-app → /data/mixxx/mixxx
      → SD card launcher → bin/mixxx → lib/bin/mixxx
```

## Key Files (repo)

| Path | Role |
|------|------|
| `mixxx-bundle/mixxx_launcher.sh` | **Source of truth** — working SD card launcher (14 lines, env vars only) |
| `tkgl-bootstrap/modules/mod_mixxx/tkgl_mod_mixxx.sh` | TKGL bootstrap module (autostart at boot) |
| `buildroot-customizations/board/inmusic/jp11/rootfs_overlay/` | Overlay files for firmware images |
| `buildroot-customizations/…/data/mixxx/mixxx` | Entry point delegation script (116 bytes) |
| `buildroot-customizations/…/usr/bin/mixxx_launcher.sh` | Launcher shipped in firmware overlay |
| `scripts/collect-mixxx-bundle.sh` | Gathers MIXXX + deps from Buildroot output → `mixxx-bundle/` |
| `scripts/deploy-to-device.sh` | SCP bundle to device, install services + switchers |
| `scripts/fix-device-libs.sh` | Removes system-critical libs (libc, libm, etc.) from deployed bundle |
| `scripts/quick-fix-deploy.sh` | Redeploys only changed files for fast iteration |
| `SD-CARD.md` | Complete SD card layout, binary details, known issues |
| `DEPLOY.md` | Deployment workflow, troubleshooting |
| `docs/launch.md` | Boot chain, CPU shielding, wrapper scripts |
| `docs/display.md` | Mali GPU, DDK mismatch, EGLFS configuration |
| `docs/audio.md` | ALSA routing, XMOS/AKM hardware chain |
| `docs/firmware.md` | Firmware flashing notes, known issues |
| `BROKEN_EXPERIMENTS.md` | Failed experiments — do not repeat |

## Env Vars (working, from device)

```sh
LD_LIBRARY_PATH=$BUNDLE/lib:/usr/qt/lib:/usr/lib
QT_QPA_PLATFORM=eglfs
QT_QPA_EGLFS_INTEGRATION=eglfs_mali
QT_QPA_EGLFS_ROTATION=90
QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=/dev/input/event0:rotate=0
HOME=/tmp
```

## Critical Rules & Pitfalls

1. **Two MIXXX binaries exist.** Only `lib/bin/mixxx` (~10 MB) works. `mixxx.real` (~17 MB) crashes with
   `EGLFS: OpenGL windows cannot be mixed with others`. `bin/mixxx` MUST be a symlink to `../lib/bin/mixxx`.

2. **System libs must NOT be in the bundle.** `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`,
   `librt.so.1`, `libstdc++.so.6`, `libgcc_s.so.1`, `ld-linux-armhf.so.3`, `libatomic.so.1` must come
   from the device's `/lib`. Bundled versions cause segfaults (kernel ABI mismatch).

3. **Mali DDK r1p0 vs r0p0.** The device has Mali r1p0. Buildroot's bundled `libEGL.so`/`libGLESv2.so`
   target r0p0. Fix: symlink them to `/usr/lib/libmali.so.14.0` on the SD card.

4. **SD Qt 5.15.8, NOT device Qt 5.15.2.** The SD card bundles its own Qt with a custom
   `libqeglfs-mali-integration.so`. Device Qt + `eglfs_emu` = black screen.

5. **Launcher must NOT set `QT_QPA_EGLFS_KMS_ATOMIC=1`** — this breaks Mali integration.

6. **Touchscreen `rotate=0`** despite `QT_QPA_EGLFS_ROTATION=90`. Mali renders portrait (800×1280),
   display controller rotates to landscape. Touch coordinates match physical orientation.

7. **`mixxx-app.service` must NOT be masked.** TKGL uses `systemd-run --unit=mixxx-app`.
   If masked to `/dev/null`, `systemd-run` fails silently.

8. **`--resourcePath` is `$BUNDLE` (root), NOT `$BUNDLE/bin`.**

## Device Access

- IP: `10.26.222.244` (or `primego.local`)
- SSH: `root@primego.local`, password `denonprime4`
- SD card mount: `/media/az01-internal/`
- Internal storage: `/data/`

## Workflow

1. **Build** MIXXX via Buildroot: `./compile-buildroot.sh`
2. **Collect** from Buildroot output: `./scripts/collect-mixxx-bundle.sh`
3. **Deploy** to device via SCP: `./scripts/deploy-to-device.sh`
4. **Verify** on device: `ssh root@primego.local ps | grep mixxx`

**After any SCP-based file change on device**, update the local repo to match.
The repo is the source of truth. Never let device files diverge without syncing back.

## Boot Verification

```bash
# After reboot, verify MIXXX is running
ssh root@primego.local 'ps | grep mixxx'
# Should show mixxx process with correct env

# Check transient service
ssh root@primego.local 'systemctl status mixxx-app.service'
# Should show Active: active (running)

# Check USB bind-mount (if USB music used)
ssh root@primego.local 'mount | grep "az01-internal/mixxx/music"'
```

## Submodules

- `buildroot-customizations/` — separate repo with overlay files for Buildroot
- `tkgl-bootstrap/` — TKGL bootstrap framework (modular boot-time script execution)
