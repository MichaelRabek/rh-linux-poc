#!/bin/bash

VM_NAME=$(basename $PWD)

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [N_EXTRA_DRIVES]"
    echo ""
    echo "Install a Linux distribution from the Red Hat family on the $VM_NAME with configurable NVMe drives."
    echo ""
    echo "Arguments:"
    echo "  N_EXTRA_DRIVES  Number of additional NVMe drives to create (default: 0)"
    echo "                  The $VM_NAME always gets 2 base NVMe drives (boot and NBFT)"
    echo "                  Extra drives are 20GB qcow2 files in the disks/ directory"
    echo ""
    echo "Examples:"
    echo "  $0              # Create $VM_NAME with 2 NVMe drives (default)"
    echo "  $0 1            # Create $VM_NAME with 3 NVMe drives total"
    echo "  $0 3            # Create $VM_NAME with 5 NVMe drives total"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message and exit"
    exit 0
fi

N_EXTRA_DRIVES=${1:-0}

source ../global_vars.sh
source ../vm_lib.sh

find_iso

BOOT_DISK=$(find . -name boot.qcow2 -print)
if [ -z "$BOOT_DISK" ]; then
    echo " boot.qcow2 not found!"
    exit 1
else
    BOOT_DISK=$(realpath $BOOT_DISK)
    echo "using $BOOT_DISK"
fi

NBFT_DISK=$(find . -name nvme1.qcow2 -print)
if [ -z "$NBFT_DISK" ]; then
    echo "nvme1.qcow2 not found!"
    exit 1
else
    NBFT_DISK=$(realpath $NBFT_DISK)
    echo "using $NBFT_DISK"
fi

virt-install \
    --name $(basename $PWD) \
    --uuid $TARGET_SYS_UUID \
    --vcpus 4 \
    --ram 4096 \
    --boot loader=/usr/share/OVMF/OVMF_CODE.fd,loader_secure=no \
    --qemu-commandline="-device nvme,drive=NVME1,bus=pcie.0,addr=0x07,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN0 -drive file=$BOOT_DISK,if=none,id=NVME1" \
    --qemu-commandline="-device nvme,drive=NVME2,bus=pcie.0,addr=0x0a,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1 -drive file=$NBFT_DISK,if=none,id=NVME2" \
    --network passt,portForward=127.0.0.1:$TARGET_PORT:22 \
    --network bridge=virbr1,mac=$TARGET_MAC2,model=virtio \
    --network bridge=virbr2,mac=$TARGET_MAC3,model=virtio \
    --check mac_in_use=off \
    --location $ISO_FILE \
    --initrd-inject ./anaconda-ks.cfg \
    --extra-args 'inst.ks=file:/anaconda-ks.cfg inst.text' \
    --console pty,target.type=virtio \
    --noreboot

echo "Installation over."
