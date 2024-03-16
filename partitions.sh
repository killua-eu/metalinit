#!/bin/bash

# Default partition sizes in GiB
EFI_SIZE=${EFI_SIZE:-1}
BOOT_SIZE=${BOOT_SIZE:-1}
SWAP_SIZE=${SWAP_SIZE:-32}

show_help() {
    echo "Disk Partitioning Script"
    echo
    echo "Usage: sudo $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message."
    echo
    echo "Environment variables:"
    echo "  EFI_SIZE            Size of the EFI partition in GiB (default: 1)"
    echo "  BOOT_SIZE           Size of the /boot partition in GiB (default: 1)"
    echo "  SWAP_SIZE           Size of the swap partition in GiB (default: 32)"
    echo
    echo "Example:"
    echo "  EFI_SIZE=1 BOOT_SIZE=2 SWAP_SIZE=4 sudo $0"
}

# Function to create partitions on a given device
partition_device() {
    local device=$1
    echo "Partitioning ${device}..."

    # Wipe existing partition table
    wipefs -a ${device}

    # Creating new GPT partition table
    parted -s ${device} mklabel gpt

    local efi_partition="${device}1"
    local efi_start="1"
    local efi_end=$((${efi_start}+${EFI_SIZE}))
    local boot_partition="${device}2"
    local boot_start=${efi_end}
    local boot_end=$((${boot_start} + ${BOOT_SIZE}))
    local primary_start=${boot_end}
    local primary_end="100%-${BOOT_SIZE}GiB"
    local swap_start=${primary_end}
    local swap_end="100%"

    parted -s ${device} mkpart EFI fat32 ${efi_start} ${efi_end}
    parted -s ${device} mkpart boot ext4 ${boot_start} ${boot_end}
    parted -s ${device} mkpart primary ${primary_start} ${primary_end}
    parted -s ${device} mkpart swap linux-swap ${swap_start} 100%

    mkfs.fat -F32 ${efi_partition}
    mkfs.ext4 ${boot_partition}
    echo "${device} partitioned."
}

# Check for help option
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Present a menu for the user to select which devices to partition
echo "Detected storage devices:"
devices=($(lsblk -dn -o name -I 8,9,179,253,259 | grep -v 'loop\|^[sr]'))
for i in "${!devices[@]}"; do
    echo "$((i+1))) /dev/${devices[i]}"
done

# Ask the user for the devices to partition
read -p "Enter the numbers of the devices you want to partition (separated by spaces): " input
selection=($input)

# Validate selection and partition the selected devices
for i in "${selection[@]}"; do
    if [[ $i =~ ^[0-9]+$ ]] && [ "$i" -ge 1 ] && [ "$i" -le "${#devices[@]}" ]]; then
        partition_device "/dev/${devices[$((i-1))]}"
    else
        echo "Invalid selection: $i"
    fi
done

echo "Partitioning complete."
