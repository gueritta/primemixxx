# Denon Prime Go — MIXXX on SD Card

Run [MIXXX](https://mixxx.org) (open-source DJ software) on your Denon DJ Prime Go
alongside the stock Engine OS — switchable on demand. **No compiling required.**

## Quick Start (End Users)

You need: a Denon Prime Go, a microSD card (≥ 2 GB), and a computer.

### 1. Download the files

| File | Where | Size |
|---|---|---|
| **SSH-enabled firmware** | [icedream/denon-prime4 Releases](https://github.com/icedream/denon-prime4/releases/latest) → `PRIMEGO-4.3.4-STOCK-SSH-Update.img` | ~168 MB |
| **SD card bundle** | [gueritta/denon-prime4 Releases](https://github.com/gueritta/denon-prime4/releases/latest) → `primego-sdcard-mixxx-*.tar.gz` | ~25 MB |

### 2. Flash the firmware

```bash
# Put device in update mode (hold BACK + power on, or SSH in and run:)
ssh root@primego.local reboot loader

# Flash via USB using the Go updater:
cd go && go run ./cmd/updater/ --firmware ../PRIMEGO-4.3.4-STOCK-SSH-Update.img
```

This installs stock Engine OS 4.3.4 **plus SSH and WiFi** — your device stays
fully functional as a Prime Go, just with remote access added.

### 3. Prepare the SD card

```bash
# Format SD card as ext4 with label TKGL_BOOTSTRAP (replace sdX with your card)
sudo mkfs.ext4 -L TKGL_BOOTSTRAP /dev/sdX1

# Mount it
sudo mount /dev/sdX1 /mnt/sdcard

# Extract the bundle
sudo tar xzf primego-sdcard-mixxx-*.tar.gz -C /mnt/sdcard --strip-components=1

# Unmount
sudo umount /mnt/sdcard
```

### 4. Insert & boot

Insert the SD card into the Prime Go and power on. The device boots into
Engine OS first (for hardware init), then **TKGL auto-launches MIXXX** from
the SD card.

To switch between Engine OS and MIXXX:
```bash
ssh root@primego.local switch-to-mixxx   # Engine → MIXXX
ssh root@primego.local switch-to-engine  # MIXXX → Engine
```

### USB music library

Plug a USB drive with MP3s into the Prime Go. It auto-mounts and MIXXX
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
./scripts/collect-mixxx-bundle.sh    # Gather MIXXX + deps from Buildroot output
./scripts/fix-device-libs.sh         # Remove system libs from bundle
DEVICE_IP=primego.local ./scripts/deploy-to-device.sh  # SCP to device
```

### Create SD card bundle (for distribution)

```bash
./scripts/create-sdcard-bundle.sh    # Assemble complete SD card tarball
```

### Device Services (Install/Repair)

```bash
DEVICE_IP=primego.local ./scripts/install-device-services.sh
```

### Flash Firmware

```bash
# Windows (original tool)
./unpack-updater.sh && ./generate-updater-win.sh

# Cross-platform (Go-based)
cd go && go run ./cmd/updater/ --firmware ../PRIMEGO-4.3.4-STOCK-SSH-Update.img
```

</details>

## Documentation

| Document | What's in it |
|---|---|
| [`docs/ONBOARDING.md`](docs/ONBOARDING.md) | Architecture, hardware, boot chain, MIDI table, build overview, known issues |
| [`docs/launch.md`](docs/launch.md) | Boot chain details, CPU shielding, wrapper scripts |
| [`docs/display.md`](docs/display.md) | Mali GPU, DDK mismatch, EGLFS configuration |
| [`docs/audio.md`](docs/audio.md) | ALSA routing, XMOS/AKM hardware chain |
| [`docs/midi.md`](docs/midi.md) | Full MIDI control table |
| [`SD-CARD.md`](SD-CARD.md) | SD card layout, library listing, launcher reference |
| [`DEPLOY.md`](DEPLOY.md) | Deployment workflow, troubleshooting, end-user quickstart |
| [`BROKEN_EXPERIMENTS.md`](BROKEN_EXPERIMENTS.md) | Failed experiments — do not repeat |
