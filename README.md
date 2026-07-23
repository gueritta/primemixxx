# Denon Prime Series — MIXXX on SD Card

Run [MIXXX](https://mixxx.org) (open-source DJ software) on your Denon DJ
Prime Go or Prime 4 alongside the stock Engine OS — switchable on demand.
**No compiling required.**

| Device | Status |
|---|---|
| **Prime Go** | ✅ Verified working (display, audio, touch, MIDI) |
| **Prime 4** | ⚠️ Untested — boots MIXXX in offscreen mode, but native display (DSI) causes GPU crash |

## Quick Start (End Users)

You need: a Denon Prime Go or Prime 4, a microSD card (≥ 32 GB), and a computer.

### 1. Download the SD card bundle

Get the latest `prime-series-sdcard-*.tar.gz` from
[GitHub Releases](https://github.com/gueritta/denon-prime4/releases/latest) (~25 MB).

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

### 3. Insert & boot

Insert the SD card and power on. The device boots into Engine OS first.

**To start MIXXX**, SSH in and run:

```bash
ssh root@<device-ip>   # password: denonprime4

# Mount the SD card and start MIXXX
mount -L TKGL_BOOTSTRAP /media/TKGL_BOOTSTRAP
/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/scripts/tkgl_bootstrap
```

MIXXX takes over the display. Engine OS continues running underneath — to
switch back, SSH in and restart Engine:

```bash
ssh root@<device-ip> 'systemctl stop mixxx-app.service; systemctl restart engine.service'
```

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
./scripts/collect-mixxx-bundle.sh    # Gather MIXXX + deps from Buildroot output
./scripts/fix-device-libs.sh         # Remove system libs from bundle
DEVICE_IP=<ip> ./scripts/deploy-to-device.sh  # SCP to device
```

### Create SD card bundle (for distribution)

```bash
./scripts/create-sdcard-bundle.sh    # Assemble complete SD card tarball
```

### Device Services (Install/Repair)

```bash
DEVICE_IP=<ip> ./scripts/install-device-services.sh
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
