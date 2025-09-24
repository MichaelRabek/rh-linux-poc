#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    VM_NAME=$(basename $PWD)
    echo "Usage: $0 [NET_CONN] [N_EXTRA_DRIVES] [QEMU_ARGS]"
    echo "   or: $0 [N_EXTRA_DRIVES] [QEMU_ARGS]"
    echo "   or: $0 [QEMU_ARGS]"
    echo ""
    echo "Install a Linux distribution on the $VM_NAME with configurable networking."
    echo ""
    echo "Arguments:"
    echo "  NET_CONN        Network connection type: 'localhost' or 'bridged' (default: localhost)"
    echo "  N_EXTRA_DRIVES  Number of additional NVMe drives to create (default: 0)"
    echo "                  The $VM_NAME always gets 2 base NVMe drives (boot and NBFT)"
    echo "  QEMU_ARGS       Optional extra commands for QEMU"
    echo ""
    echo "Examples:"
    echo "  $0                         # Create $VM_NAME with localhost networking"
    echo "  $0 1                       # Create $VM_NAME with localhost networking, 1 extra drive"
    echo "  $0 bridged                 # Create $VM_NAME with bridged networking"
    echo "  $0 localhost 3             # Create $VM_NAME with localhost networking, 3 extra drives"
    echo "  $0 localhost 0 -vnc :0     # Create $VM_NAME with a VNC connection"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message and exit"
    exit 0
fi

HOST=`hostname`
VMNAME=`basename $PWD`
QEMU=none
BRIDGE_HELPER=none
QARGS=""
ISO_FILE=""

# Parse parameters
if [[ "$1" == "localhost" || "$1" == "bridged" ]]; then
    NET_CONN="$1"
    N_EXTRA_DRIVES=${2:-0}
    shift 2
    QEMU_ARGS=$@
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    NET_CONN="localhost"
    N_EXTRA_DRIVES="$1"
    shift 1
    QEMU_ARGS=$@
else
    NET_CONN="localhost"
    N_EXTRA_DRIVES=${1:-0}
    shift 1
    QEMU_ARGS=$@
fi

find_iso
check_qemu_command

BOOT_DISK=$(find . -name boot.qcow2 -print)
if [ -z "$BOOT_DISK" ]; then
    echo " $BOOT_DISK not found!"
    exit 1
else
    BOOT_DISK=$(realpath $BOOT_DISK)
    echo "using $BOOT_DISK"
fi

NBFT_DISK=$(find . -name nvme1.qcow2 -print)
if [ -z "$NBFT_DISK" ]; then
    echo " $NBFT_DISK not found!"
    exit 1
else
    NBFT_DISK=$(realpath $NBFT_DISK)
    echo "using $NBFT_DISK"
fi

case "$NET_CONN" in
    localhost)
        # NET0_NET="-netdev user,id=net0,net=$NET_CIDR,hostfwd=tcp::$NET_PORT-:22"
        NET0_NET="-netdev user,id=net0,hostfwd=tcp::$TARGET_PORT-:22"
        NET0_DEV="-device e1000,netdev=net0,addr=4"
        echo "$TARGET_PORT" > .netport
    ;;
    bridged)
        NET0_NET="-netdev bridge,br=br0,id=net0,helper=$BRIDGE_HELPER"
        NET0_DEV="-device virtio-net-pci,netdev=net0,mac=$TARGET_MAC1,addr=4"
    ;;
    *)
    echo " Error: invalid argument $3"
        exit 1
    ;;
esac

check_qargs

echo ""
echo " Be sure to create the root account with ssh access."
echo " Reboot to complete the install and login to the root account."
echo ""
echo " Record the host interface name and ip address with \"ip -br address show\" command."
echo ""
echo " Next step will be to run the \"./netsetup.sh\" script."
echo ""

NET1_NET="-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE_HELPER"
NET1_DEV="-device virtio-net-pci,netdev=net1,mac=$TARGET_MAC2,addr=5"
NET2_NET="-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE_HELPER"
NET2_DEV="-device virtio-net-pci,netdev=net2,mac=$TARGET_MAC3,addr=6"

$QEMU -name $VMNAME -M q35 -accel kvm -bios OVMF-pure-efi.fd -cpu host -m 4G -smp 4 $QARGS \
-uuid $TARGET_SYS_UUID \
-boot order=cd \
-cdrom $ISO_FILE \
-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN0 \
-drive file=$BOOT_DISK,if=none,id=NVME1 \
-device nvme,drive=NVME2,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1 \
-drive file=$NBFT_DISK,if=none,id=NVME2 \
$NET0_NET \
$NET0_DEV \
$NET1_NET \
$NET1_DEV \
$NET2_NET \
$NET2_DEV \
$QEMU_ARGS

exit $?
