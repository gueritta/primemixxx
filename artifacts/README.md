# SD Card Artifacts

Flashable SD card snapshots. Too large for git — stored locally.

## Current Artifact

```
primego-sdcard-mixxx-20260710.tar.gz  (183MB)
MD5: a8ef04d9695286d08fdf17b3c24bc7c8
```

Contains:
- `mixxx-bundle/` — MIXXX 2.5.6 + 66 libs + Qt plugins + controller mappings + launcher
- `scripts/device/` — systemd service + switch-to-mixxx + switch-to-engine

## Deploy to Device

```bash
# Extract to SD card root
tar xzf primego-sdcard-mixxx-20260710.tar.gz -C /mountpoint/

# On device, contents go to:
#   /media/az01-internal/mixxx/  ← mixxx-bundle/*
#   /etc/systemd/system/         ← mixxx.service
#   /usr/bin/                    ← switch-to-mixxx, switch-to-engine
```

## Recreate from Buildroot

```bash
# 1. Rebuild MIXXX
make mixxx-rebuild

# 2. Collect bundle from Buildroot output
./scripts/collect-mixxx-bundle.sh

# 3. Create artifact tarball
tar -czf artifacts/primego-sdcard-mixxx-$(date +%Y%m%d).tar.gz \
    mixxx-bundle/ scripts/device/
```

## Flash to SD Card

```bash
# Mount SD card
sudo mount /dev/sdX1 /mnt/sdcard

# Extract artifact
sudo tar xzf artifacts/primego-sdcard-mixxx-20260710.tar.gz -C /mnt/sdcard/

# Or deploy via SSH to device (recommended)
DEVICE_IP=10.70.180.244 ./scripts/deploy-to-device.sh

sudo umount /mnt/sdcard
```
