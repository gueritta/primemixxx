# Denon Prime 4 — Custom Firmware + MIXXX

Custom firmware for Denon DJ Prime 4 / Prime Go hardware that deploys
[MIXXX](https://mixxx.org) (open-source DJ software) alongside or instead of
the stock Engine OS. MIXXX runs from an internal SD card — the two are
switchable on demand without stripping the original firmware.

## Getting Started

**New to the project?** Start here: [`docs/ONBOARDING.md`](docs/ONBOARDING.md)

### Prebuilt Firmware

Download the latest firmware from [GitHub Releases](https://github.com/icedream/denon-prime4/releases/latest).

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

### Device Services (Install/Repair)

```bash
# Install/reinstall all system services without re-deploying the full bundle
DEVICE_IP=primego.local ./scripts/install-device-services.sh
```

Installs: `mixxx.service`, `usb-gadget-eth.service` (USB SSH), `fix-mdns.service` (primego.local), `powerbutton-monitor.service`, switcher scripts, and udev rules.

### Flash Firmware

```bash
# Windows (original tool)
./unpack-updater.sh && ./generate-updater-win.sh

# Cross-platform (Go-based)
cd go && go run ./cmd/updater/ --firmware ../PRIMEGO-4.3.4-STOCK-SSH-Update.img
```

## Documentation

| Document | What's in it |
|---|---|
| [`docs/ONBOARDING.md`](docs/ONBOARDING.md) | Architecture, hardware, boot chain, MIDI table, build overview, known issues |
| [`docs/launch.md`](docs/launch.md) | Boot chain details, CPU shielding, wrapper scripts |
| [`docs/display.md`](docs/display.md) | Mali GPU, DDK mismatch, EGLFS configuration |
| [`docs/audio.md`](docs/audio.md) | ALSA routing, XMOS/AKM hardware chain |
| [`docs/midi.md`](docs/midi.md) | Full MIDI control table |
| [`SD-CARD.md`](SD-CARD.md) | SD card layout, library listing |
| [`DEPLOY.md`](DEPLOY.md) | Deployment workflow, troubleshooting |
| [`BROKEN_EXPERIMENTS.md`](BROKEN_EXPERIMENTS.md) | Failed experiments — do not repeat |
