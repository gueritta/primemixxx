# Deploying MIXXX on Denon Prime Series

## End User Quickstart (No Compiling)

If you just want MIXXX on your Prime Go or Prime 4 without building anything:

1. **Download the SD card bundle** from [GitHub Releases](https://github.com/gueritta/denon-prime4/releases/latest) — file `prime-series-sdcard-*.tar.gz`
2. **Extract the bundle** to a microSD card formatted as ext4 (label `TKGL_BOOTSTRAP`)
3. **Insert the SD card** and power on
4. **SSH in** and run the bootstrap:

```bash
ssh root@<device-ip>   # password: denonprime4
mount -L TKGL_BOOTSTRAP /media/TKGL_BOOTSTRAP
/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/scripts/tkgl_bootstrap
```

| Device | Status |
|---|---|
| **Prime Go** | ✅ Verified working — display, audio, touch, MIDI all functional |
| **Prime 4** | ⚠️ Untested — MIXXX runs in offscreen mode but native display (DSI) causes GPU segfault |

See the [README Quick Start](README.md#quick-start-end-users) for detailed step-by-step instructions.

---

## Developer Deployment (via SSH)

## Prerequisites

1. **SSH access**: `ssh root@<device-ip>` (password: `denonprime4`)
   - Prime Go: USB Ethernet gadget at `192.168.42.1` or WiFi
   - Prime 4: WiFi (keepalive ping needed to prevent SSH drops)

2. **Build machine**: MIXXX already compiled via Buildroot (`scripts/collect-mixxx-bundle.sh` needs the output)

## Quick Start

> **⚠️ Golden rule: every change applies to BOTH local repo AND device.**  
> The repo is always the source of truth — commit locally first, then deploy to device.  
> Never edit files directly on the device without updating the repo.  
> Never commit without deploying. **Local ↔ device must always be in sync.**

```bash
# 1. Collect MIXXX + dependencies from Buildroot output
./scripts/collect-mixxx-bundle.sh

# 2. Deploy to device (backs up SD card first, copies bundle, installs services)
DEVICE_IP=primego.local ./scripts/deploy-to-device.sh

# 3. Switch to MIXXX
ssh root@primego.local switch-to-mixxx

# 4. Switch back to Engine
ssh root@primego.local switch-to-engine
```

## Device Services

`scripts/install-device-services.sh` installs all system-level services. Run it standalone
to fix/reinstall services without re-deploying the full MIXXX bundle:

```bash
DEVICE_IP=<ip> ./scripts/install-device-services.sh
```

| Service | Purpose | Auto-start |
|---|---|---|
| `usb-gadget-eth.service` | USB Ethernet gadget (RNDIS) | Yes (boot) |
| `fix-mdns.service` | Fixes mDNS hostname | Yes (boot, oneshot) |
| `powerbutton-monitor.service` | Graceful shutdown on power button | No (only during MIXXX sessions) |
| `99-usb-automount.rules` | Auto-mount USB drives for music library | Yes (udev) |
| `99-wifi-power-save.rules` | Disable WiFi power save (prevents SSH drops) | Yes (udev) |

## What Gets Deployed (SD-Only Approach)

The SD-only bundle lives entirely on the SD card — nothing is written to internal storage.

| Path on SD card | Contents |
|---|---|
| `tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/lib/bin/mixxx` | MIXXX binary (ARMv7, ~10 MB, working) |
| `tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/bin/mixxx` | Symlink → `../lib/bin/mixxx` |
| `tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/lib/` | All shared libraries MIXXX needs |
| `tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/qt-plugins/` | Qt5 EGLFS platform, image, SQL plugins |
| `tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/mixxx-mapping/` | MIDI controller mappings (Prime Go + Prime 4) |
| `tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/mixxx_launcher.sh` | Launcher with env vars, Mali, CPU shielding |
| `tkgl_bootstrap_DenonPrimeGO/modules/mod_mixxx/` | TKGL module — launches MIXXX via systemd-run |
| `tkgl_bootstrap_DenonPrimeGO/scripts/tkgl_bootstrap` | Bootstrap entry point |

## How It Works

For the full boot chain, architecture, and launch path details, see
[`docs/ONBOARDING.md`](docs/ONBOARDING.md).

**Quick summary (SD-only approach):**
- User inserts SD card, powers on → Engine OS boots normally (hardware init)
- User SSHes in and runs the TKGL bootstrap script on the SD card
- TKGL bootstrap → `systemd-run --unit=mixxx-app` → SD card launcher → MIXXX
- MIXXX runs entirely from SD card — internal storage is never modified

### Boot Verification
```bash
ssh root@<ip> 'ps | grep mixxx'
ssh root@<ip> 'systemctl status mixxx-app.service'
ssh root@<ip> 'mount | grep TKGL_BOOTSTRAP'
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
- Ensure device is on the same WiFi network
- Try USB Ethernet gadget: connect USB-C to computer, device appears at `192.168.42.1`
- WiFi SSH drops after ~30s silence — keep a keepalive ping running: `ping -i 25 <device-ip> > /dev/null &`

**MIXXX segfaults (exit code 139 / signal 11)**:
- **System libs conflict**: The bundle must NOT contain `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1`, `libstdc++.so.6`, `libgcc_s.so.1`, `ld-linux-armhf.so.3`, or `libatomic.so.1`. These MUST come from the device's `/lib`.
- **Mali DDK mismatch**: Error "DDK is not compatible... r1p0 vs r0p0" means the bundled `libEGL.so`/`libGLESv2.so` target the wrong Mali driver version. Fix: `cd $BUNDLE/lib && rm -f libEGL.so libGLESv2.so libGLESv1_CM.so && ln -sf /usr/lib/libmali.so.14.0 libEGL.so && ln -sf /usr/lib/libmali.so.14.0 libGLESv2.so && ln -sf /usr/lib/libmali.so.14.0 libGLESv1_CM.so`
- **EGLFS crash "OpenGL windows cannot be mixed with others"**: This happens when using the wrong binary (`mixxx.real` 17 MB). Use `lib/bin/mixxx` 10 MB instead. Check: `ls -la bin/mixxx` should point to `../lib/bin/mixxx`, NOT `../mixxx.real`.
- **Prime 4 DSI display**: Prime 4 uses DSI-1 display (not LVDS-1 like Prime Go). MIXXX may segfault during EGL initialization due to DDK/DSI incompatibility. Run `-platform offscreen` to verify the binary works. Native display support requires further investigation.

