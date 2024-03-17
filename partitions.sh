#!/bin/bash

# Default partition sizes in MiB
EFI_SIZE="${EFI_SIZE:-1024}"
BOOT_SIZE="${BOOT_SIZE:-2048}"
SWAP_SIZE="${SWAP_SIZE:-32768}"
IMPORT_SSH="${IMPORT_SSH:-gh:killua-eu}"

show_help() {
    echo "Disk Partitioning Script"
    echo
    echo "Usage: sudo $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message."
    echo
    echo "Environment variables:"
    echo "  EFI_SIZE            Size of the EFI partition in MiB (default: 1024)"
    echo "  BOOT_SIZE           Size of the /boot partition in MiB (default: 2048)"
    echo "  SWAP_SIZE           Size of the swap partition in MiB (default: 32768)"
    echo "  CRYPT_PWD           MANDATORY luks2 crypt password."
    echo "  IMPORT_SSH          Import ssh keys (example: gh:GithubUser)."
    echo
    echo "Example:"
    echo "  EFI_SIZE=1024 BOOT_SIZE=2048 SWAP_SIZE=40000 CRYPT_PWD='secret' sudo $0"
}

if [ -z "${CRYPT_PWD}" ]; then
    echo "[ERROR] CRYPT_PWD ENV variable not set!"
    echo ""
    show_help
    exit 1
fi

ssh-import-id "${IMPORT_SSH}" -o /home/installer/.ssh/authorized_keys


# Function to create partitions on a given device
partition_device() {
     local device=$1
    echo "Wiping ${device}..."
    wipefs -a "${device}"

    echo "Partitioning ${device}..."

    # Creating new GPT partition table
    parted -s "${device}" mklabel gpt
    parted -s "${device}" align-check opt 1

    # Partitioning
    # - p1: (bios spacer)
    # - p2: /boot/efi, fat32 unencrypted (needs manual dd between dev1 and dev2)
    # - p3: /boot, btrfs-raid1 unencrypted
    # - p4: /, btrfs-raid1 on a luks2 device (/dev/mapper/$ROOTx_crypt)

     local spacer_start="1"
     local spacer_end="2"
     local efi_partition="${device}2"
     local efi_start="${spacer_end}"
     local efi_end=$((efi_start + EFI_SIZE))
     local boot_partition="${device}3"
     local boot_start="${efi_end}"
     local boot_end=$((boot_start + BOOT_SIZE))
     local swap_start="${boot_end}"
     local swap_end=$((swap_start + SWAP_SIZE))
     local primary_start="${swap_end}"
     local primary_end="100%"

    echo "    >> Setting up partitions"
    sudo parted -s "${device}" mkpart '""' ${spacer_start}MiB ${spacer_end}MiB
    sudo parted -s "${device}" mkpart EFI fat32 ${efi_start}MiB ${efi_end}MiB
    sudo parted -s "${device}" mkpart boot ${boot_start}MiB ${boot_end}MiB
    sudo parted -s "${device}" mkpart swap linux-swap ${swap_start}MiB ${swap_end}MiB
    sudo parted -s "${device}" mkpart primary ${primary_start}MiB ${primary_end}

    echo "    >> Setting up partition names"
    sudo parted -s "${device}" name 1 "bios${2}"
    sudo parted -s "${device}" name 2 "efi${2}"
    sudo parted -s "${device}" name 3 "boot${2}"
    sudo parted -s "${device}" name 4 "swap${2}"
    sudo parted -s "${device}" name 5 "prim${2}"
    echo "    >> Setting up partition flags"
    sudo parted -s "${device}" set 1 bios_grub on
    sudo parted -s "${device}" set 2 esp on
    sleep 1

    CRYPTDEV="/dev/disk/by-partlabel/prim${2}"
    echo "    >> Running cryptsetup on ${CRYPTDEV}"
    if [ -b "${CRYPTDEV}" ]; then
        sudo cryptsetup luksFormat "${CRYPTDEV}" --label="crypt${2}" --type luks2 --key-slot=0 <<< ${CRYPT_PWD}
        # echo -n ${CRYPT_PWD} | cryptsetup --batch-mode luksFormat "/dev/disk/by-partlabel/prim${2}" --label="crypt${2}"
        sleep 1
        sudo cryptsetup open "${CRYPTDEV}" "crypt${2}" --type luks2 --key-slot=0 <<< "${CRYPT_PWD}"
    else
        echo "No partition found with label: prim${2}"
    fi

    mkfs.fat -F32 -v -I "/dev/disk/by-partlabel/efi${2}"
    #mkfs.ext4 ${boot_partition}
    mkswap "/dev/disk/by-partlabel/swap${2}"
    swapon "/dev/disk/by-partlabel/swap${2}"
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
echo "Partitioning with EFI_SIZE ${EFI_SIZE}, BOOT_SIZE=${BOOT_SIZE}, SWAP_SIZE=${SWAP_SIZE}"
# Validate selection and partition the selected devices
for i in "${selection[@]}"; do
    if [[ $i =~ ^[0-9]+$ ]] && [[ "$i" -ge 1 ]] && [[ "$i" -le "${#devices[@]}" ]]; then
        partition_device "/dev/${devices[$((i-1))]}" "${i}"
    else
        echo "Invalid selection: $i"
    fi
done

echo "Partitioning complete."




