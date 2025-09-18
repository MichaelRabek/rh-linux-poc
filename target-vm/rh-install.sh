#!/bin/bash

VM_NAME=$(basename $PWD)

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [NET_CONN] [N_EXTRA_DRIVES]"
    echo "   or: $0 [N_EXTRA_DRIVES]"
    echo ""
    echo "Install a Linux distribution from the Red Hat family on the $VM_NAME with configurable NVMe drives."
    echo ""
    echo "Arguments:"
    echo "  NET_CONN        Network connection type: 'localhost' or 'bridged' (default: localhost)"
    echo "  N_EXTRA_DRIVES  Number of additional NVMe drives to create (default: 0)"
    echo "                  The $VM_NAME always gets 2 base NVMe drives (boot and NBFT)"
    echo "                  Extra drives are 20GB qcow2 files in the disks/ directory"
    echo ""
    echo "Examples:"
    echo "  $0                    # Create $VM_NAME with localhost networking, 2 NVMe drives"
    echo "  $0 1                  # Create $VM_NAME with localhost networking, 3 NVMe drives"
    echo "  $0 bridged            # Create $VM_NAME with bridged networking, 2 NVMe drives"
    echo "  $0 localhost 3        # Create $VM_NAME with localhost networking, 5 NVMe drives"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message and exit"
    exit 0
fi

# Parse parameters
if [[ "$1" == "localhost" || "$1" == "bridged" ]]; then
    NET_CONN="$1"
    N_EXTRA_DRIVES=${2:-0}
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    NET_CONN="localhost"
    N_EXTRA_DRIVES="$1"
else
    NET_CONN="localhost"
    N_EXTRA_DRIVES=${1:-0}
fi

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

if [ $N_EXTRA_DRIVES -gt 0 ] ; then
    mkdir -p /tmp/rh-linux-poc/$(basename $PWD)
fi

EXTRA_NVMES=()
for ((i=1; i<=N_EXTRA_DRIVES; i++)); do
    NVME_ID=$((i + 2))
    ADDR=$((0x0b + i - 1))
    EXTRA_DISK="disks/nvme${NVME_ID}.qcow2"
    make $EXTRA_DISK DRIVE_CAP=20G
    EXTRA_NVMES+=("--qemu-commandline=-device nvme,drive=NVME${NVME_ID},bus=pcie.0,addr=0x$(printf '%x' $ADDR),max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$(generate_serial_number) -drive file=$(realpath $EXTRA_DISK),if=none,id=NVME${NVME_ID}")
done

echo "using $NET_CONN network"
if [ $NET_CONN = "localhost" ] ; then
    PRIMARY_NETWORK="--network passt,portForward=127.0.0.1:$TARGET_PORT:22"
elif [ $NET_CONN = "bridged" ] ; then
    PRIMARY_NETWORK="--network bridge=br0"
else
    echo "Unknown connection type $NET_CONN"
    exit 1
fi

virt-install \
    --name $(basename $PWD) \
    --uuid $TARGET_SYS_UUID \
    --vcpus 4 \
    --ram 4096 \
    --boot loader=/usr/share/OVMF/OVMF_CODE.fd,loader_secure=no \
    --qemu-commandline="-device nvme,drive=NVME1,bus=pcie.0,addr=0x07,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN0 -drive file=$BOOT_DISK,if=none,id=NVME1" \
    --qemu-commandline="-device nvme,drive=NVME2,bus=pcie.0,addr=0x0a,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1 -drive file=$NBFT_DISK,if=none,id=NVME2" \
    "${EXTRA_NVMES[@]}" \
    $PRIMARY_NETWORK \
    --network bridge=virbr1,mac=$TARGET_MAC2,model=virtio \
    --network bridge=virbr2,mac=$TARGET_MAC3,model=virtio \
    --check mac_in_use=off \
    --location $ISO_FILE,kernel=images/pxeboot/vmlinuz,initrd=images/pxeboot/initrd.img \
    --initrd-inject ./anaconda-ks.cfg \
    --extra-args 'inst.ks=file:/anaconda-ks.cfg inst.text' \
    --console pty,target.type=virtio \
    --noreboot

echo "Installation over."
