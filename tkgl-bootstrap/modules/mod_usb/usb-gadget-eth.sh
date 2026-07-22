#!/bin/sh
# USB Ethernet Gadget Setup — makes the Prime Go appear as a USB Ethernet adapter
# Connected computer gets network access to the device via usb0 (192.168.42.1)

GADGET_DIR=/sys/kernel/config/usb_gadget/g_ether

# Only create if not already set up
if [ -d "$GADGET_DIR" ]; then
    echo "USB gadget already configured"
    exit 0
fi

mkdir -p "$GADGET_DIR" || exit 1

# USB vendor/product IDs (use Linux Foundation generic)
echo 0x1d6b > "$GADGET_DIR/idVendor"   # Linux Foundation
echo 0x0104 > "$GADGET_DIR/idProduct"  # Multifunction Composite Gadget
echo 0x0200 > "$GADGET_DIR/bcdDevice"  # USB 2.0

# English strings
mkdir -p "$GADGET_DIR/strings/0x409"
echo "DenonDJ" > "$GADGET_DIR/strings/0x409/manufacturer"
echo "PRIME GO USB Ethernet" > "$GADGET_DIR/strings/0x409/product"
echo "$(cat /sys/class/net/eth0/address 2>/dev/null || echo '00:11:22:33:44:55')" > "$GADGET_DIR/strings/0x409/serialnumber"

# Configuration
mkdir -p "$GADGET_DIR/configs/c.1/strings/0x409"
echo "USB Ethernet" > "$GADGET_DIR/configs/c.1/strings/0x409/configuration"
echo 500 > "$GADGET_DIR/configs/c.1/MaxPower"

# Ethernet function (supports RNDIS + ECM + NCM — computer picks best)
mkdir -p "$GADGET_DIR/functions/ecm.usb0"
# Use a fixed MAC so the host's network manager remembers the interface
echo "02:00:42:00:00:01" > "$GADGET_DIR/functions/ecm.usb0/dev_addr"
echo "02:00:42:00:00:02" > "$GADGET_DIR/functions/ecm.usb0/host_addr"

ln -s "$GADGET_DIR/functions/ecm.usb0" "$GADGET_DIR/configs/c.1/"

# Bind to UDC (USB Device Controller)
UDC=$(ls /sys/class/udc/ 2>/dev/null | head -1)
if [ -n "$UDC" ]; then
    echo "$UDC" > "$GADGET_DIR/UDC"
    echo "USB Ethernet gadget activated on $UDC"
else
    echo "ERROR: No UDC found — USB OTG not available"
    exit 1
fi
