# primemixxx — MIXXX on Denon Prime DJ Hardware

Run [MIXXX](https://mixxx.org) (open-source DJ software) on your Denon DJ
Prime Go or Prime 4 alongside the stock Engine OS — switchable on demand.
**No compiling required.**

> Fork of [@ghuntley/denon-prime4](https://github.com/ghuntley/denon-prime4) —
> original firmware research. This fork focuses on deploying a working MIXXX
> environment via SD card with dual-boot support.

| Device | Status |
|---|---|
| **Prime Go** | ✅ Verified working (display, audio, touch, MIDI) |
| **Prime 4** | ⚠️ Untested — boots MIXXX in offscreen mode, but native display (DSI) causes GPU crash |

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
sh /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/install-boot-hook.sh
```

### 4. Reboot & enjoy

```bash
ssh root@192.168.42.1 reboot
```

After reboot, the device detects the SD card and **automatically launches MIXXX**
— no SSH needed. To switch between MIXXX and Engine OS, SSH in and run
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
