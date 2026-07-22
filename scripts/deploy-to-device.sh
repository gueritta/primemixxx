#!/bin/bash -e
# deploy-to-device.sh — Deploy the MIXXX bundle to a Denon Prime Go device
# via SCP, and install systemd service + switcher scripts.
#
# Prerequisites:
#   1. Device is running TKGL stock firmware (SSH enabled)
#   2. ./scripts/collect-mixxx-bundle.sh has been run (produces mixxx-bundle/)
#   3. Device is reachable via SSH at the configured host/IP
#
# Usage:
#   DEVICE_IP=192.168.1.100 ./scripts/deploy-to-device.sh
#   (or edit DEVICE_IP below)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUNDLE_DIR="$REPO_ROOT/mixxx-bundle"

# ── Configuration ────────────────────────────────────────────────────────────
DEVICE_IP="${DEVICE_IP:-primego.local}"
SSH_USER="${SSH_USER:-root}"
SSH_PASS="${SSH_PASS:-denonprime4}"
DEVICE_MIXXX_DIR="/media/az01-internal/mixxx"
BACKUP_DIR="$REPO_ROOT/sdcard-backup-$(date +%Y%m%d-%H%M%S)"

# ── SSH helper using sshpass ─────────────────────────────────────────────────
if command -v sshpass &>/dev/null; then
  SSH_CMD="sshpass -p '$SSH_PASS' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  SCP_CMD="sshpass -p '$SSH_PASS' scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r"
else
  echo "WARNING: sshpass not installed. You will be prompted for the password."
  echo "Install with: sudo apt install sshpass"
  SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  SCP_CMD="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r"
fi

SSH_TARGET="${SSH_USER}@${DEVICE_IP}"

# ── Pre-flight checks ────────────────────────────────────────────────────────
echo "=== Deploying MIXXX to device ==="
echo "Device:  $SSH_TARGET"
echo "Bundle:  $BUNDLE_DIR"
echo "Target:  $DEVICE_MIXXX_DIR"

if [ ! -f "$BUNDLE_DIR/bin/mixxx" ]; then
  echo "ERROR: MIXXX bundle not found. Run scripts/collect-mixxx-bundle.sh first." >&2
  exit 1
fi

# Test SSH connectivity
echo ""
echo "--- Testing SSH connection (password: $SSH_PASS) ---"
if ! eval $SSH_CMD "$SSH_TARGET" "echo 'SSH OK'"; then
  echo "ERROR: Cannot SSH to device. Check DEVICE_IP and that the device is on." >&2
  exit 1
fi

# ── Step 1: Remount rootfs read-write ────────────────────────────────────────
echo ""
echo "--- Remounting / as read-write ---"
eval $SSH_CMD "$SSH_TARGET" "mount -o remount,rw /" || {
  echo "WARNING: Could not remount / as read-write. Continuing anyway..."
}

# ── Step 2: Back up SD card contents ─────────────────────────────────────────
echo ""
echo "--- Backing up /media/az01-internal/ from device ---"
mkdir -p "$BACKUP_DIR"
eval $SCP_CMD "$SSH_TARGET:/media/az01-internal/*" "$BACKUP_DIR/" 2>/dev/null && \
  echo "SD card backup saved to: $BACKUP_DIR" || \
  echo "WARNING: SD card backup may be incomplete (directory may be empty or inaccessible)."
echo "Backup size: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)"

# ── Step 3: Copy MIXXX bundle to device ──────────────────────────────────────
echo ""
echo "--- Copying MIXXX bundle to device ($DEVICE_MIXXX_DIR) ---"
eval $SSH_CMD "$SSH_TARGET" "mkdir -p '$DEVICE_MIXXX_DIR'"
eval $SCP_CMD "$BUNDLE_DIR"/* "$SSH_TARGET:$DEVICE_MIXXX_DIR/" || {
  echo "ERROR: Failed to copy bundle to device." >&2
  exit 1
}
echo "Bundle copied successfully."

# ── Step 4: Install systemd service ──────────────────────────────────────────
echo ""
echo "--- Installing mixxx.service on device ---"

# Read the service file template and substitute the SD card path
SERVICE_FILE="$REPO_ROOT/scripts/device/mixxx.service"

eval $SSH_CMD "$SSH_TARGET" "cat > /etc/systemd/system/mixxx.service << 'SERVICEOF'
[Unit]
Description=MIXXX DJ Software (SD Card)
After=sound.target multi-user.target
Conflicts=engine.service
Before=engine.service

[Service]
Type=simple
ExecStart=$DEVICE_MIXXX_DIR/mixxx_launcher.sh
Restart=on-failure
RestartSec=2
Environment=HOME=/root

# Environment is set by mixxx_launcher.sh, not duplicated here.
# Key env: LD_LIBRARY_PATH (SD card Qt 5.15.8), QT_QPA_EGLFS_INTEGRATION=eglfs_mali

# Real-time audio
LimitRTPRIO=99
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
SERVICEOF"

# Do NOT enable by default — user switches explicitly
eval $SSH_CMD "$SSH_TARGET" "systemctl daemon-reload"

# ── Step 4b: Install USB automount udev rule ─────────────────────────────────
echo ""
echo "--- Installing USB automount udev rule ---"
eval $SSH_CMD "$SSH_TARGET" "cat > /etc/udev/rules.d/99-usb-automount.rules << 'RULESEOF'
# Auto-mount USB storage for MIXXX music library
ACTION==\"add\", SUBSYSTEMS==\"usb\", SUBSYSTEM==\"block\", KERNEL==\"sd[a-z][0-9]\", ENV{ID_FS_USAGE}==\"filesystem\", \
  RUN{program}+=\"/usr/bin/systemd-mount --no-block --automount=yes --collect \$devnode /media/usb-%k\"

ACTION==\"remove\", SUBSYSTEMS==\"usb\", SUBSYSTEM==\"block\", KERNEL==\"sd[a-z][0-9]\", \
  RUN{program}+=\"/usr/bin/systemd-umount /media/usb-%k\", \
  RUN{program}+=\"/bin/rmdir /media/usb-%k\"
RULESEOF"

eval $SSH_CMD "$SSH_TARGET" "udevadm control --reload-rules && echo 'Udev rules reloaded'"

# ── Step 5: Install switcher scripts ─────────────────────────────────────────
echo ""
echo "--- Installing switcher scripts on device ---"

# switch-to-mixxx.sh
eval $SSH_CMD "$SSH_TARGET" "cat > /usr/bin/switch-to-mixxx << 'SWEOF'
#!/bin/bash
# Switch from Engine DJ to MIXXX
set -e

echo \"Switching to MIXXX...\"

# Remount rootfs read-write if needed
mount -o remount,rw / 2>/dev/null || true

# Stop Engine
echo \"Stopping engine.service...\"
systemctl stop engine.service 2>/dev/null || true
sleep 1

# Ensure MIXXX launcher is executable
chmod +x $DEVICE_MIXXX_DIR/mixxx_launcher.sh

# Start MIXXX
echo \"Starting mixxx.service...\"
systemctl start mixxx.service
echo \"MIXXX is now running. Use 'switch-to-engine' to go back.\"
SWEOF"
eval $SSH_CMD "$SSH_TARGET" "chmod +x /usr/bin/switch-to-mixxx"

# switch-to-engine.sh
eval $SSH_CMD "$SSH_TARGET" "cat > /usr/bin/switch-to-engine << 'SWEOF'
#!/bin/bash
# Switch from MIXXX back to Engine DJ
set -e

echo \"Switching to Engine DJ...\"

# Stop MIXXX
echo \"Stopping mixxx.service...\"
systemctl stop mixxx.service 2>/dev/null || true
sleep 1

# Start Engine
echo \"Starting engine.service...\"
systemctl start engine.service
echo \"Engine DJ is now running. Use 'switch-to-mixxx' to go back.\"
SWEOF"
eval $SSH_CMD "$SSH_TARGET" "chmod +x /usr/bin/switch-to-engine"

# ── Step 5b: Install USB Ethernet gadget + WiFi power save fix ────────────
echo ""
echo "--- Installing USB Ethernet gadget + WiFi power save fix ---"

eval $SSH_CMD "$SSH_TARGET" "cat > /usr/sbin/usb-gadget-eth.sh << 'GADGETEOF'
#!/bin/sh
# USB Ethernet Gadget — survives cable unplug/replug
# Device: 192.168.42.1/24, Host: 192.168.42.2/24
GADGET_DIR=/sys/kernel/config/usb_gadget/g_ether
UDC_DEV=ff580000.usb

# Create gadget if not present
if [ ! -d \"\$GADGET_DIR\" ]; then
    mkdir -p \"\$GADGET_DIR\" || exit 1
    echo 0x1d6b > \"\$GADGET_DIR/idVendor\"
    echo 0x0104 > \"\$GADGET_DIR/idProduct\"
    echo 0x0200 > \"\$GADGET_DIR/bcdDevice\"
    mkdir -p \"\$GADGET_DIR/strings/0x409\"
    echo \"DenonDJ\" > \"\$GADGET_DIR/strings/0x409/manufacturer\"
    echo \"PRIME GO USB Ethernet\" > \"\$GADGET_DIR/strings/0x409/product\"
    mkdir -p \"\$GADGET_DIR/configs/c.1/strings/0x409\"
    echo \"USB Ethernet\" > \"\$GADGET_DIR/configs/c.1/strings/0x409/configuration\"
    echo 500 > \"\$GADGET_DIR/configs/c.1/MaxPower\"
    mkdir -p \"\$GADGET_DIR/functions/ecm.usb0\"
    echo \"02:00:42:00:00:01\" > \"\$GADGET_DIR/functions/ecm.usb0/dev_addr\"
    echo \"02:00:42:00:00:02\" > \"\$GADGET_DIR/functions/ecm.usb0/host_addr\"
    ln -s \"\$GADGET_DIR/functions/ecm.usb0\" \"\$GADGET_DIR/configs/c.1/\"
fi

# Bind UDC if not bound (handles cable unplug/replug)
CURRENT_UDC=\$(cat \"\$GADGET_DIR/UDC\" 2>/dev/null)
if [ -z \"\$CURRENT_UDC\" ]; then
    echo \"\$UDC_DEV\" > \"\$GADGET_DIR/UDC\"
fi

# Configure usb0 IP
for i in \$(seq 1 30); do [ -d /sys/class/net/usb0 ] && break; sleep 1; done
if [ -d /sys/class/net/usb0 ]; then
    ip link set usb0 up 2>/dev/null
    ip addr add 192.168.42.1/24 dev usb0 2>/dev/null
fi
GADGETEOF"

eval $SSH_CMD "$SSH_TARGET" "chmod +x /usr/sbin/usb-gadget-eth.sh"

eval $SSH_CMD "$SSH_TARGET" "cat > /etc/systemd/system/usb-gadget-eth.service << 'SERVEOF'
[Unit]
Description=USB Ethernet Gadget
After=sys-kernel-config.mount
Before=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/usb-gadget-eth.sh
[Install]
WantedBy=multi-user.target
SERVEOF"

eval $SSH_CMD "$SSH_TARGET" "systemctl daemon-reload && systemctl enable usb-gadget-eth.service && echo 'USB Ethernet gadget installed and enabled'"

# WiFi power save disable — prevents SSH disconnections after ~30s idle
eval $SSH_CMD "$SSH_TARGET" "cat > /etc/udev/rules.d/99-wifi-power-save.rules << 'WIFIRULE'
ACTION==\"add\", SUBSYSTEM==\"net\", KERNEL==\"wlan*\", RUN+=\"/usr/sbin/iw dev \$name set power_save off\"
WIFIRULE"
eval $SSH_CMD "$SSH_TARGET" "udevadm control --reload-rules && echo 'WiFi power save udev rule installed'"

# ── Step 6: Install power button shutdown service ─────────────────────────
echo ""
echo "--- Installing power button shutdown service ---"

# Copy monitor script from repo (source of truth)
eval $SSH_CMD "$SSH_TARGET" "cat > /usr/sbin/powerbutton-monitor << 'MONEOF'
#!/bin/sh
# Power button → clean shutdown (stop MIXXX gracefully, then poweroff).
#
# The Denon Prime 4 / Prime Go (RK3288 + RK808 PMIC) exposes the power button
# as an input device (name typically "rk8xx_pwrkey" on /dev/input/event0).
# This script reads raw input_event structs (16 bytes on ARM 32-bit LE)
# and watches for KEY_POWER (code 116 = 0x74, type EV_KEY=1, value=1 for press).
#
# Shutdown sequence:
#   1. Debounce: ignore presses within 3s of the last one
#   2. systemctl stop mixxx-app.service (SIGTERM → MIXXX saves DB, exits cleanly)
#   3. Wait up to 30s for MIXXX to stop; SIGKILL if it hangs
#   4. Stop engine.service (if active)
#   5. sync + poweroff

LOG_TAG="powerbutton"
log() { echo "[$LOG_TAG] $*" >&2; }

# Locate hexdump — BusyBox places it in /usr/bin; util-linux in /usr/bin
for candidate in /usr/bin/hexdump /sbin/hexdump /bin/hexdump; do
    [ -x "$candidate" ] && { HEXDUMP="$candidate"; break; }
done
[ -z "$HEXDUMP" ] && { log "hexdump not found"; exit 1; }

# --- Find the input device carrying the power key ---
find_pwr_device() {
    for dev in /dev/input/event*; do
        [ -e "$dev" ] || continue
        name=$(cat "/sys/class/input/${dev##*/}/device/name" 2>/dev/null) || continue
        case "$name" in
            *pwr*|*PWR*|*Power*|*power*|*button*|*Button*|rk8xx*|rk808*|gpio*|*key*|*Key*)
                log "using $dev ($name)"
                echo "$dev"
                return 0
                ;;
        esac
    done
    [ -e /dev/input/event0 ] && { log "fallback to /dev/input/event0"; echo /dev/input/event0; return 0; }
    return 1
}

# --- Read one input_event and check for KEY_POWER press ---
# input_event layout (ARM 32-bit LE):
#   [0-3] tv_sec  [4-7] tv_usec  [8-9] type  [10-11] code  [12-15] value
# KEY_POWER: type=1 (EV_KEY), code=116 (0x0074), value=1 (press)
check_event() {
    line=$("$HEXDUMP" -v -n 16 -e '16/1 " %02x" "\n"' /dev/stdin 2>/dev/null) || return 1
    [ -z "$line" ] && return 1
    set -- $line
    [ "${9}"  = "01" ] && [ "${10}" = "00" ] && [ "${11}" = "74" ] && \
    [ "${12}" = "00" ] && [ "${13}" = "01" ] || return 1
    return 0
}

# --- Stop a systemd service with timeout ---
stop_service() {
    local svc="$1" timeout="${2:-30}"
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        log "$svc is not active"
        return 0
    fi
    log "stopping $svc (timeout ${timeout}s)"
    systemctl stop "$svc" 2>/dev/null || true
    local waited=0
    while systemctl is-active --quiet "$svc" 2>/dev/null && [ "$waited" -lt "$timeout" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        log "WARNING: $svc still running after ${timeout}s — sending SIGKILL"
        # systemctl kill may not exist on old systemd; fall back to kill
        systemctl kill -s KILL "$svc" 2>/dev/null || {
            pid=$(systemctl show -p MainPID "$svc" 2>/dev/null | cut -d= -f2)
            [ -n "$pid" ] && [ "$pid" != "0" ] && kill -9 "$pid" 2>/dev/null
        }
        sleep 1
    fi
    log "$svc stopped after ${waited}s"
}

# --- Debounce helper ---
should_debounce() {
    [ -f /tmp/pwrbtn_last ] || return 1
    local now last diff
    now=$(cat /proc/uptime 2>/dev/null | cut -d. -f1)
    last=$(cat /tmp/pwrbtn_last)
    diff=$((now - last))
    [ "$diff" -lt 3 ]
}

# === Main ===
PWR_DEV=$(find_pwr_device) || { log "no input device found"; exit 1; }
log "monitoring $PWR_DEV for KEY_POWER"

while true; do
    if dd if="$PWR_DEV" bs=16 count=1 2>/dev/null | check_event; then
        log "KEY_POWER press detected"

        if should_debounce; then
            log "debounce — ignoring (last press < 3s ago)"
            continue
        fi
        cat /proc/uptime | cut -d. -f1 > /tmp/pwrbtn_last

        # 1. Gracefully stop MIXXX (SIGTERM → save DB → exit)
        stop_service mixxx-app.service 30

        # 2. Stop Engine if running (belt & suspenders)
        if systemctl is-active --quiet engine.service 2>/dev/null; then
            log "stopping engine.service"
            systemctl stop engine.service 2>/dev/null || true
            sleep 2
        fi

        # 3. Power off
        log "shutting down"
        sync
        /sbin/poweroff 2>/dev/null || /sbin/shutdown -h now 2>/dev/null || /bin/busybox poweroff
        log "poweroff returned — sleeping, systemd will restart us"
        sleep 10
    fi
done

MONEOF"
eval $SSH_CMD "$SSH_TARGET" "chmod +x /usr/sbin/powerbutton-monitor"

# Install and enable the systemd service
eval $SSH_CMD "$SSH_TARGET" "cat > /etc/systemd/system/powerbutton-monitor.service << 'UNITEOF'
[Unit]
Description=Power button shutdown monitor
Documentation=https://github.com/gueritta/denon-prime4
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/sbin/powerbutton-monitor
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNITEOF"

eval $SSH_CMD "$SSH_TARGET" "systemctl daemon-reload && systemctl enable powerbutton-monitor.service && systemctl start powerbutton-monitor.service"
echo "Power button monitor installed and started."

# ── Step 7: Verify deployment ────────────────────────────────────────────────
echo ""
echo "--- Verifying deployment ---"
eval $SSH_CMD "$SSH_TARGET" "ls -la '$DEVICE_MIXXX_DIR/bin/mixxx' && echo 'MIXXX binary: OK'"
eval $SSH_CMD "$SSH_TARGET" "ls '$DEVICE_MIXXX_DIR/lib/' | wc -l | xargs echo 'Library count:'"
eval $SSH_CMD "$SSH_TARGET" "ls -la /usr/bin/switch-to-mixxx /usr/bin/switch-to-engine && echo 'Switcher scripts: OK'"
eval $SSH_CMD "$SSH_TARGET" "systemctl status mixxx.service --no-pager -l 2>&1 | head -5"

echo ""
echo "=== Deployment complete! ==="
echo ""
echo "  To switch to MIXXX:  ssh $SSH_TARGET switch-to-mixxx"
echo "  To switch to Engine:  ssh $SSH_TARGET switch-to-engine"
echo "  SD card backup:      $BACKUP_DIR"
echo ""
echo "NOTE: The device will still boot into Engine DJ by default."
echo "      MIXXX must be started manually via the switcher."

# ── Step 8: Clean stale settings/controllers copies and fix config ─────
# MIXXX config may point to settings/controllers/ — fix to use controllers/
echo ""
echo "--- Cleaning stale settings/controllers/ and fixing config ---"
eval $SSH_CMD "$SSH_TARGET" '
CTRL_DIR="/media/az01-internal/mixxx/controllers"
SETTINGS_DIR="/media/az01-internal/mixxx/settings/controllers"
rm -f "$SETTINGS_DIR"/Denon-Prime-Go-scripts.js "$SETTINGS_DIR"/Denon-Prime-Go.midi.xml "$SETTINGS_DIR"/Denon-Prime-Go-jog-wheel-scripts.js "$SETTINGS_DIR"/Denon-Prime-Go-Jog-Wheels.midi.xml "$SETTINGS_DIR"/midi-components-0.0.js
# Fix MIXXX config to point to controllers/ (not settings/controllers/)
sed -i "s|/media/az01-internal/mixxx/settings/controllers/Denon-Prime-Go.midi.xml|/media/az01-internal/mixxx/controllers/Denon-Prime-Go.midi.xml|" /media/az01-internal/mixxx/settings/mixxx.cfg
echo "Stale copies removed, config path fixed."
'
