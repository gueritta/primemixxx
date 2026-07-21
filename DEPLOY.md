# Deploying MIXXX via SSH (No-Strip Approach)

This guide covers deploying MIXXX to a Denon Prime Go **without stripping** the original Engine OS firmware. MIXXX lives on the internal SD card and is switchable on demand via SSH.

## Prerequisites

1. **Flash the stock+SSH firmware** to your Prime Go:
   - File: `PRIMEGO-4.3.4-STOCK-SSH-Update.img` (168MB)
   - This is stock Engine OS 4.3.4 with SSH + WiFi auto-provisioning added
   - Flash via USB using the Go updater tool (`go/cmd/updater/`) in device update mode (`reboot loader`)
   
2. **SSH access**: `ssh root@primego.local` (password: `denonprime4`)

3. **Build machine**: MIXXX already compiled via Buildroot (`scripts/collect-mixxx-bundle.sh` needs the output)

## Quick Start

```bash
# 1. Collect MIXXX + dependencies from Buildroot output
./scripts/collect-mixxx-bundle.sh

# 2. Deploy to device (backs up SD card first, copies bundle, installs service)
DEVICE_IP=primego.local ./scripts/deploy-to-device.sh

# 3. Switch to MIXXX
ssh root@primego.local switch-to-mixxx

# 4. Switch back to Engine
ssh root@primego.local switch-to-engine
```

## What Gets Deployed

| Path on device | Contents |
|---|---|
| `/media/az01-internal/mixxx/lib/bin/mixxx` | MIXXX binary (ARMv7, ~10 MB, working) |
| `/media/az01-internal/mixxx/bin/mixxx` | Symlink → `../lib/bin/mixxx` |
| `/media/az01-internal/mixxx/mixxx.real` | 17 MB binary — DO NOT USE (EGLFS crash) |
| `/media/az01-internal/mixxx/lib/` | All shared libraries MIXXX needs |
| `/media/az01-internal/mixxx/qt-plugins/` | Qt5 EGLFS platform, image, SQL plugins |
| `/media/az01-internal/mixxx/mixxx-mapping/` | MIDI controller mappings |
| `/media/az01-internal/mixxx/mixxx_launcher.sh` | Minimal wrapper with env vars only |
| `/data/mixxx/mixxx` | Entry point — delegates to SD launcher |
| `/usr/bin/switch-to-mixxx` | Switcher: Engine → MIXXX |
| `/usr/bin/switch-to-engine` | Switcher: MIXXX → Engine |

## How It Works

For the full boot chain, architecture, and launch path details, see
[`docs/ONBOARDING.md`](docs/ONBOARDING.md).

**Quick summary:**
- **Autostart (TKGL):** `tkgl-mixxx.service` → bootstrap → `systemd-run --unit=mixxx-app` → SD card launcher → MIXXX
- **Manual switch:** `ssh root@primego.local switch-to-mixxx` / `switch-to-engine`

### Boot Verification
```bash
ssh root@primego.local 'ps | grep mixxx'
ssh root@primego.local 'systemctl status mixxx-app.service'
ssh root@primego.local 'mount | grep "az01-internal/mixxx/music"'
```

## SD Card Backup

`deploy-to-device.sh` automatically backs up `/media/az01-internal/` to `sdcard-backup-YYYYMMDD-HHMMSS/` before deploying. This captures the overlay filesystem state (connman WiFi configs, Engine library database, etc.).

## Flashing the Firmware

The stock+SSH firmware is at `PRIMEGO-4.3.4-STOCK-SSH-Update.img` (symlink to `.dtb`).

To rebuild it:
```bash
# Source DTS: PRIMEGO-4.3.4-STOCK-SSH-Update.img.dts
# Rootfs:    unpacked-ssh-img/rootfs-stock-ssh.img.xz
make PRIMEGO-4.3.4-STOCK-SSH-Update.img.dtb
```

To flash:
```bash
# Put device in update mode
ssh root@primego.local reboot loader

# Use the Go updater tool
cd go && go run ./cmd/updater/ --firmware ../PRIMEGO-4.3.4-STOCK-SSH-Update.img
```

## Troubleshooting

**Can't SSH to device**:
- Ensure WiFi is configured (the firmware auto-provisions "pd" network)
- Try USB ethernet gadget: connect USB-C to computer, device appears as USB Ethernet
- Fallback: flash stock firmware, use `mount.sh --write` to manually add WiFi config

**MIXXX segfaults (exit code 139)**:
- **System libs conflict**: The bundle must NOT contain `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1`, `libstdc++.so.6`, `libgcc_s.so.1`, `ld-linux-armhf.so.3`, or `libatomic.so.1`. These MUST come from the device's `/lib`.
- **Mali DDK mismatch**: Error "DDK is not compatible... r1p0 vs r0p0" means the bundled `libEGL.so`/`libGLESv2.so` target the wrong Mali driver version. Fix: `cd /media/az01-internal/mixxx/lib && rm -f libEGL.so libGLESv2.so libGLESv1_CM.so && ln -sf /usr/lib/libmali.so.14.0 libEGL.so && ln -sf /usr/lib/libmali.so.14.0 libGLESv2.so && ln -sf /usr/lib/libmali.so.14.0 libGLESv1_CM.so`
- **EGLFS crash "OpenGL windows cannot be mixed with others"**: This happens when using the wrong binary (`mixxx.real` 17 MB). Use `lib/bin/mixxx` 10 MB instead. Check: `ls -la bin/mixxx` should point to `../lib/bin/mixxx`, NOT `../mixxx.real`.
- **Qt 5.15.8 bundled on SD card**: MIXXX is compiled against Qt 5.15.8 and the SD card bundles this exact version. The device's native Qt 5.15.2 at `/usr/qt/lib` is used as fallback only.

**MIXXX fails to start**:
- Check `journalctl -u mixxx.service` or `journalctl -u mixxx-app.service` on device
- Check TKGL boot log: `ls /var/log/tkgl/mixxx*.log`
- **mixxx-app.service is masked**: Run `systemctl unmask mixxx-app.service` — the TKGL module needs this unit name for `systemd-run`
- Common issue: EGLFS can't open display — ensure engine.service is fully stopped first
- Verify `/media/az01-internal/mixxx/lib/` contains all needed .so files

**MIXXX runs but no display**:
- The Mali GPU needs proper initialization. Engine does this on boot.
- Try: stop engine, wait 3 seconds, then start MIXXX
- If still blank, reboot device and run `switch-to-mixxx` immediately after boot (before Engine fully initializes the display)

**Want MIXXX to autostart?**:
```bash
ssh root@primego.local systemctl enable mixxx.service
# Device will now boot directly into MIXXX (skipping Engine)
```

