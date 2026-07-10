# Firmware Flashing Notes

## Known Issues

### "too large for partition" via fastboot

The `rootfs-stock-ssh.img.xz` (512MB uncompressed) may exceed the Prime Go's rootfs partition when flashed via fastboot (USB updater `.run`). The stock rootfs is the same size, so the SSH additions likely push it just over the limit.

**Workaround**: Copy the `.img` (DTB) file to a USB drive and flash via the device's recovery/update mode, which reads directly from USB mass storage.

## Flashing Methods

1. **USB fastboot** (`.run` updater) — requires device in update mode, fastboot over USB
2. **USB drive** — copy `.img` to FAT32 USB drive root, insert into device, enter update mode
3. **SSH** — `reboot loader` then fastboot flash (only works if SSH is already enabled)
