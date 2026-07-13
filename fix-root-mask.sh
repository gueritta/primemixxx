#!/bin/sh
echo "$(date): fix-root-mask starting" >> /data/fix-root-mask.log

# Step 1: Unmount overlay to access real root
umount -l /etc 2>/dev/null
sleep 1

# Step 2: Remount / RW
mount -o remount,rw /

# Step 3: Remove the /dev/null mask on real root
rm -f /etc/systemd/system/engine.service

# Step 4: Write our no-op unit to real root
cat > /etc/systemd/system/engine.service << 'UNIT'
[Unit]
Description=Engine (TKGL bootstrap host)
After=touch-fw-update.service xmos-update.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/data/tkgl-bootstrap-launcher
ExecStart=/bin/true
TimeoutStopSec=30
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
UNIT

# Step 5: Fix the multi-user.target.wants symlink on real root
rm -f /etc/systemd/system/multi-user.target.wants/engine.service
ln -sf /etc/systemd/system/engine.service /etc/systemd/system/multi-user.target.wants/engine.service

sync
mount -o remount,ro /
mount /etc 2>/dev/null
sleep 1

# Step 6: Clean overlay so real root shines through
rm -f /data/system/etc/overlay/systemd/system/engine.service 2>/dev/null
rm -rf /data/system/etc/overlay/systemd/system/engine.service.d 2>/dev/null

# Also use systemctl to fix the overlay's symlink
systemctl daemon-reload 2>/dev/null

echo "$(date): fix-root-mask DONE" >> /data/fix-root-mask.log
