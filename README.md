# primemixxx — MIXXX on Denon Prime DJ Hardware

Run [MIXXX](https://mixxx.org) (open-source DJ software) on your Denon DJ
Prime Go or Prime 4 hardware alongside the stock Engine OS — **switchable
on demand by inserting or removing an SD card.** No firmware flashing,
no permanent modification. **Stable at 5ms audio buffer.**

> Fork of [@ghuntley/denon-prime4](https://github.com/ghuntley/denon-prime4) —
> original firmware research. This fork runs a tuned PREEMPT_RT environment
> with CPU shielding, RT thread pinning, and I/O scheduler optimization.

| Device | Status |
|---|---|
| **Prime Go** | ✅ Verified (display, audio, touch, MIDI, 5.8ms latency) |
| **Prime 4** | ⚠️ Untested — boots in offscreen mode (DSI GPU crash) |

### Audio Performance

With CPU shielding, RT thread pinning, and I/O scheduler tuning, the
Prime Go achieves **5.8ms (256/512) ALSA buffer** with SCHED_FIFO 98
audio threads. Early testing shows stable playback at this latency, but
**deeper stress testing is needed** — run with heavy FX chains, pitch
bend, and USB library scanning to validate under load.

### Recent Improvements (2026-07)

- **Per-thread CPU pinning** — EngineWorkerSch/EngineSideChain isolated on cores 2-3, all 40+ other threads (CachingReader, Mali, Qt pool, touchscreen) banished to 0-1
- **I/O scheduler** — BFQ → `none` on both MMC blocks, read-ahead 128→512KB, nr_requests 128→64
- **VM tuning** — dirty_background_bytes 50→20MB, swappiness 60→1, vfs_cache_pressure 100→200, stat_interval 1→10s
- **Filesystem** — all ext4 mounts with `noatime,nodiratime,commit=60`
- **systemd limits** — LimitMEMLOCK=infinity, LimitRTPRIO=99 for audio DMA safety
- **USB gadget** — Ethernet gadget auto-starts at boot for reliable SSH access

## Quick Start (End Users)

You need: a Denon Prime Go or Prime 4, a microSD card (≥ 32 GB), and a computer.

### 1. Download the SD card bundle

Get the latest `prime-series-sdcard-*.tar.gz` from
[GitHub Releases](https://github.com/gueritta/primemixxx/releases/latest) (~25 MB).

### 2. Prepare the SD card

```bash
# Format SD card as ext4 with label TKGL_BOOTSTRAP (replace sdX with your card)
sudo mkfs.ext4 -L TKGL_BOOTSTRAP /dev/sdX1

# Mount it
sudo mount /dev/sdX1 /mnt/sdcard

# Extract the bundle
sudo tar xzf prime-series-sdcard-*.tar.gz -C /mnt/sdcard

# Unmount
sudo umount /mnt/sdcard
```

### 3. Install boot hook (one-time)

SSH into the device and run the install script from the SD card:

```bash
# Connect via USB (preferred): the device appears at 192.168.42.1
ssh root@192.168.42.1   # password: denonprime4

# Or via WiFi — find the IP on your router, or try primego.local
ssh root@<device-ip>

# Run the one-time install (flashes stub + engine.service to internal eMMC)
sh /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/install-device.sh
```

The installer backs up your original Engine OS service and interactively
offers optional features (USB Ethernet gadget, power button shutdown, mDNS fix,
WiFi stability).

**To uninstall** and return to stock Engine OS:

```bash
sh /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/uninstall-device.sh
```

### 4. Reboot & enjoy

```bash
ssh root@192.168.42.1 reboot
```

After reboot, the device detects the SD card and **automatically launches MIXXX**
— no SSH needed.

**To boot into stock Engine OS instead**, simply remove the SD card before
powering on. The device falls back to the original `engine.service` and loads
Engine OS normally. Re-insert the SD card and reboot to return to MIXXX.

To switch between MIXXX and Engine OS at runtime, SSH in and run
`switch-to-mixxx` or `switch-to-engine`.

### USB music library

Plug a USB drive with MP3s into the device. It auto-mounts and MIXXX
scans it on startup.

---

## For Developers

<details>
<summary>Building from source (click to expand)</summary>

### Build from Source

```bash
./unpack.sh              # Download and unpack original firmware
./clone-buildroot.sh     # Clone Buildroot 2021.02.10
./compile-buildroot.sh   # Build toolchain + packages (requires sudo)
./pack.sh                # Pack modified images → firmware .dtb
```

Prerequisites: u-boot tools, 7-zip, QEMU ARM emulation with binfmt, base development packages. See [Buildroot requirements](https://buildroot.org/downloads/manual/manual.html#requirement).

### Deploy MIXXX to Device

```bash
./scripts/dev-collect-mixxx-bundle.sh    # Gather MIXXX + deps from Buildroot output
./scripts/dev-fix-device-libs.sh         # Remove system libs from bundle
DEVICE_IP=<ip> ./scripts/dev-deploy-to-device.sh  # SCP to device
```

### Create SD card bundle (for distribution)

```bash
./scripts/dev-create-sdcard-bundle.sh    # Assemble complete SD card tarball
```

### Device Services (Install/Repair)

```bash
DEVICE_IP=<ip> ./scripts/dev-install-device-services.sh
```

</details>

## Documentation

| Document | What's in it |
|---|---|
| [`docs/ONBOARDING.md`](docs/ONBOARDING.md) | Architecture, hardware, boot chain, MIDI table, build overview, known issues |
| [`docs/launch.md`](docs/launch.md) | Boot chain details, CPU shielding, wrapper scripts |
| [`docs/display.md`](docs/display.md) | Mali GPU, DDK mismatch, EGLFS configuration |
| [`docs/audio.md`](docs/audio.md) | ALSA routing, audio hardware chain |
| [`docs/midi.md`](docs/midi.md) | Full MIDI control table |
| [`SD-CARD.md`](SD-CARD.md) | SD card layout, library listing, launcher reference |
| [`DEPLOY.md`](DEPLOY.md) | Deployment workflow, troubleshooting, SSH setup |
| [`BROKEN_EXPERIMENTS.md`](BROKEN_EXPERIMENTS.md) | Failed experiments — do not repeat |
| [`SKIN-TODO.md`](SKIN-TODO.md) | Skin and hardware mapping pending tasks |
