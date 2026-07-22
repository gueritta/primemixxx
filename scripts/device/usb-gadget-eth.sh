#!/bin/sh
# USB Ethernet Gadget — survives cable unplug/replug
GADGET_DIR=/sys/kernel/config/usb_gadget/g_ether
UDC_DEV=ff580000.usb

# Create gadget if not present
if [ ! -d "$GADGET_DIR" ]; then
    mkdir -p "$GADGET_DIR" || exit 1
    echo 0x1d6b > "$GADGET_DIR/idVendor"
    echo 0x0104 > "$GADGET_DIR/idProduct"
    echo 0x0200 > "$GADGET_DIR/bcdDevice"
    mkdir -p "$GADGET_DIR/strings/0x409"
    echo "DenonDJ" > "$GADGET_DIR/strings/0x409/manufacturer"
    echo "PRIME GO USB Ethernet" > "$GADGET_DIR/strings/0x409/product"
    mkdir -p "$GADGET_DIR/configs/c.1/strings/0x409"
    echo "USB Ethernet" > "$GADGET_DIR/configs/c.1/strings/0x409/configuration"
    echo 500 > "$GADGET_DIR/configs/c.1/MaxPower"
    mkdir -p "$GADGET_DIR/functions/ecm.usb0"
    echo "02:00:42:00:00:01" > "$GADGET_DIR/functions/ecm.usb0/dev_addr"
    echo "02:00:42:00:00:02" > "$GADGET_DIR/functions/ecm.usb0/host_addr"
    ln -s "$GADGET_DIR/functions/ecm.usb0" "$GADGET_DIR/configs/c.1/"
fi

# Bind UDC if not bound
CURRENT_UDC=$(cat "$GADGET_DIR/UDC" 2>/dev/null)
if [ -z "$CURRENT_UDC" ]; then
    echo "$UDC_DEV" > "$GADGET_DIR/UDC"
fi

# Configure usb0 IP
for i in $(seq 1 30); do [ -d /sys/class/net/usb0 ] && break; sleep 1; done
if [ -d /sys/class/net/usb0 ]; then
    ip link set usb0 up 2>/dev/null
    ip addr add 192.168.42.1/24 dev usb0 2>/dev/null
fi
