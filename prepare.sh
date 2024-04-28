#!/bin/bash

# Default partition sizes in MiB
EFI_SIZE="${EFI_SIZE:-1024}"
BOOT_SIZE="${BOOT_SIZE:-2048}"
SWAP_SIZE="${SWAP_SIZE:-0}"
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
    echo "  SWAP_SIZE           Size of the swap partition in MiB (default: 0)"
    echo "  CRYPT_PWD           MANDATORY luks2 crypt password."
    echo "*) SWAP partition won't be created if SWAP_SIZE is set to 0"
    echo
    echo "Example:"
    echo "  sudo SWAP_SIZE=0 CRYPT_PWD='secret' $0"
}

if [ -z "${CRYPT_PWD}" ]; then
    echo "[ERROR] CRYPT_PWD ENV variable not set!"
    echo ""
    show_help
    exit 1
fi

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
    if [ "${SWAP_SIZE}" -gt 0 ]; then sudo parted -s "${device}" mkpart swap linux-swap ${swap_start}MiB ${swap_end}MiB; fi
    sudo parted -s "${device}" mkpart primary ${primary_start}MiB ${primary_end}

    echo "    >> Setting up partition names"
    counter=0
    # BIOS
    let counter+=1;
    sudo parted -s "${device}" name $counter "bios${2}"
    sudo parted -s "${device}" set $counter bios_grub on
    # EFI
    let counter+=1;
    sudo parted -s "${device}" name $counter "efi${2}"
    sudo parted -s "${device}" set $counter esp on
    # BOOT
    let counter+=1;
    sudo parted -s "${device}" name $counter "boot${2}"
    # SWAP (if not zero)
    if [ "${SWAP_SIZE}" -gt 0 ]; then
        let counter+=1;
        sudo parted -s "${device}" name $counter "swap${2}"
    fi
    # PRIMARY
    let counter+=1;
    sudo parted -s "${device}" name $counter "prim${2}"

    # wait before setting up cryptsetup
    sleep 2

    CRYPTDEV="/dev/disk/by-partlabel/prim${2}"
    echo "    >> Running cryptsetup on ${CRYPTDEV}"
    if [ -b "${CRYPTDEV}" ]; then
        sudo cryptsetup luksFormat "${CRYPTDEV}" --label="crypt${2}" --type luks2 --key-slot=0 <<< ${CRYPT_PWD}
        sleep 1
        sudo cryptsetup open "${CRYPTDEV}" "crypt${2}" --type luks2 --key-slot=0 <<< "${CRYPT_PWD}"
    else
        echo "No partition found with label: prim${2}"
    fi

    mkfs.fat -F32 -v -I "/dev/disk/by-partlabel/efi${2}"
    if [ "${SWAP_SIZE}" -gt 0 ]; then
        mkswap "/dev/disk/by-partlabel/swap${2}"
        swapon "/dev/disk/by-partlabel/swap${2}"
    fi
    echo "${device} partitioned."
}

prepare_fs() {
  echo "Sensing required devices ... "
  if [ ! -b "/dev/mapper/crypt1" ]; then echo "[FAIL] Cannot find /dev/mapper/crypt1" ; exit 1; fi;
  if [ ! -b "/dev/mapper/crypt2" ]; then echo "[FAIL] Cannot find /dev/mapper/crypt2" ; exit 1; fi;
  if [ ! -b "/dev/disk/by-partlabel/boot1" ]; then echo "[FAIL] Cannot find /dev/disk/by-partlabel/boot1" ; exit 1; fi;
  if [ ! -b "/dev/disk/by-partlabel/boot2" ]; then echo "[FAIL] Cannot find /dev/disk/by-partlabel/boot2" ; exit 1; fi;

  echo "Preparing BTRFS RAIDs"
  sudo mkfs.btrfs -m raid1 -d raid1 /dev/disk/by-partlabel/boot1 /dev/disk/by-partlabel/boot2 -f
  sudo mkfs.btrfs -m raid1 -d raid1 /dev/mapper/crypt1 /dev/mapper/crypt2 -f
  sudo mount -o subvolid=5,defaults,compress=zstd:1,discard=async /dev/mapper/crypt1 /mnt
  echo "Creating subvols"
  sudo btrfs subvolume create /mnt/@
  sudo btrfs subvolume create /mnt/@home
  sudo btrfs subvolume create /mnt/@varlog
  sudo btrfs subvolume create /mnt/@snapshots
  sudo btrfs subvolume create /mnt/@tmp
  sudo umount /mnt
}

remount_fs() {
  echo "Enter the mount point (default /, for chrooting use i.e. /mnt):"
  read -p "Mount point: " mount_point
  mount_point="${mount_point:-/}"  # Use /mnt as default if no input provided

  if [ ! -d "$mount_point" ]; then
    echo "Directory does not exist. Creating $mount_point."
    sudo mkdir -p "$mount_point"
    if [ $? -ne 0 ]; then  # Check if mkdir was successful
      echo "Failed to create directory $mount_point. Please check your permissions."
      exit 1
    fi
  fi

  echo "Checking for devices"
  if [ ! -b "/dev/mapper/crypt1" ]; then sudo cryptsetup open /dev/disk/by-partlabel/prim1 crypt1 --type luks2 --key-slot=0 <<< "${CRYPT_PWD}"; fi
  if [ ! -b "/dev/mapper/crypt2" ]; then sudo cryptsetup open /dev/disk/by-partlabel/prim2 crypt2 --type luks2 --key-slot=0 <<< "${CRYPT_PWD}"; fi
  if [ ! -b "/dev/mapper/crypt1" ]; then echo "[FAIL] Cannot find /dev/mapper/crypt1" ; exit 1; fi
  if [ ! -b "/dev/mapper/crypt2" ]; then echo "[FAIL] Cannot find /dev/mapper/crypt2" ; exit 1; fi

  echo "Remounting for chroot at $mount_point"
  sudo mount -o subvol=@,compress=zstd /dev/mapper/crypt1 "$mount_point"
  sudo mkdir -p "$mount_point"/{boot,home,var,snapshots,tmp}
  sudo mkdir -p "$mount_point"/var/log
  sudo mount -o subvol=@home,compress=zstd /dev/mapper/crypt1 "$mount_point"/home
  sudo mount -o subvol=@varlog,compress=zstd /dev/mapper/crypt1 "$mount_point"/var/log
  sudo mount -o subvol=@snapshots,compress=zstd /dev/mapper/crypt1 "$mount_point"/snapshots
  sudo mount -o subvol=@tmp,compress=zstd /dev/mapper/crypt1 "$mount_point"/tmp
  sudo mount /dev/disk/by-partlabel/boot1 "$mount_point"/boot
  sudo mkdir -p "$mount_point"/boot/efi
  sudo mount /dev/disk/by-partlabel/efi1 "$mount_point"/boot/efi
}

prepare_pkgs() {
  echo "Genfstab and debootstrap"
  sudo apt update
  sudo apt install -y arch-install-scripts debootstrap
  # libnpth0t64,libnpth0,libaio1t64,libaio1
  sudo debootstrap --include=libnpth0t64,libaio1t64,software-properties-common --components=main,restricted,universe --log-extra-deps --variant=minbase --arch=amd64 noble /mnt http://archive.ubuntu.com/ubuntu/
  sudo genfstab -U /mnt | sudo tee -a /mnt/etc/fstab > /dev/null
}

do_chroot() {
  echo "Chrooting ..."
  for i in /dev /dev/pts /proc /sys /run; do sudo mount -B $i /mnt$i; done
  sudo cp -r ./devices.tmp /mnt/root/devices.tmp
  sudo cp -r ./install.sh /mnt/root/install.sh
  sudo chroot /mnt
}


select_devices() {
    echo "Detected storage devices:"
    devices=($(lsblk -o NAME,TRAN,RM,TYPE | grep disk | grep -v "1 disk" | awk '{print $1}'))
    for i in "${!devices[@]}"; do
        echo "$((i+1))) /dev/${devices[i]}"
    done

    # Ask the user for the devices to partition
    read -p "Enter the numbers of the devices you want to partition (separated by spaces): " input
    selection=($input)
    echo "Partitioning with EFI_SIZE ${EFI_SIZE}, BOOT_SIZE=${BOOT_SIZE}, SWAP_SIZE=${SWAP_SIZE}"
    # Validate selection and partition the selected devices
    truncate -s 0 ./devices.tmp;
    for i in "${selection[@]}"; do
        if [[ $i =~ ^[0-9]+$ ]] && [[ "$i" -ge 1 ]] && [[ "$i" -le "${#devices[@]}" ]]; then
            partition_device "/dev/${devices[$((i-1))]}" "${i}"
            echo "/dev/${devices[$((i-1))]}" >> ./devices.tmp
        else
            echo "Invalid selection: $i"
        fi
    done

    echo "Partitioning complete."
}

crypt_open() {
    for CRYPTDEV in /dev/disk/by-partlabel/prim*; do
        # Extract the identifier from the partition label
        i=$(echo $CRYPTDEV | grep -o '[0-9]*$')
        echo "Opening LUKS on ${CRYPTDEV} as crypt${i}..."
        sudo cryptsetup open "${CRYPTDEV}" "crypt${i}" --type luks2 --key-slot=0 <<< "${CRYPT_PWD}"
        if [ $? -eq 0 ]; then
            echo "Successfully opened ${CRYPTDEV} as crypt${i}."
        else
            echo "Failed to open ${CRYPTDEV} as crypt${i}."
        fi
    done
}

# Check for help option
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Main menu for script operations
main_menu() {
    echo "Please select an operation:"
    echo "1) Partition devices"
    echo "2) Prepare file systems"
    echo "3) Remount file systems"
    echo "-----------------------"
    echo "4) Prepare packages for installation"
    echo "5) Enter chroot environment"
    echo "-----------------------"
    echo "6) Show help"
    echo "7) Exit"
    read -p "Enter your choice: " choice

    case "$choice" in
        1) select_devices;;
        2) prepare_fs;;
        3) remount_fs;;
        4) prepare_pkgs;;
        5) do_chroot;;
        6) show_help;;
        7) crypt_open;;
        8) exit 0;;
        *) echo "Invalid choice, please try again."; main_menu;;
    esac
}

main_menu





