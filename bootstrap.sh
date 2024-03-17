#!/bin/bash

echo "Sensing required devices ... "
if [ ! -b "/dev/mapper/crypt1" ]; then echo "[FAIL] Cannot find /dev/mapper/crypt1" ; exit 1; fi;
if [ ! -b "/dev/mapper/crypt2" ]; then echo "[FAIL] Cannot find /dev/mapper/crypt2" ; exit 1; fi;
if [ ! -b "/dev/disk/by-partlabel/boot1" ]; then echo "[FAIL] Cannot find /dev/disk/by-partlabel/boot1" ; exit 1; fi;
if [ ! -b "/dev/disk/by-partlabel/boot1" ]; then echo "[FAIL] Cannot find /dev/disk/by-partlabel/boot1" ; exit 1; fi;

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

echo "Remounting for chroot"
sudo mount -o subvol=@,compress=zstd /dev/mapper/crypt1 /mnt
sudo mkdir /mnt/{boot,home,var,snapshots,tmp}
sudo mkdir /mnt/var/log
sudo mount -o subvol=@home,compress=zstd /dev/mapper/crypt1 /mnt/home
sudo mount -o subvol=@varlog,compress=zstd /dev/mapper/crypt1 /mnt/var/log
sudo mount -o subvol=@snapshots,compress=zstd /dev/mapper/crypt1 /mnt/snapshots
sudo mount -o subvol=@tmp,compress=zstd /dev/mapper/crypt1 /mnt/tmp

sudo mount /dev/disk/by-partlabel/boot1 /mnt/boot

sudo mkdir /mnt/boot/efi
sudo mount /dev/disk/by-partlabel/efi1 /mnt/boot/efi

echo "Genfstab and debootstrap"
sudo apt update
apt install -y arch-install-scripts debootstrap
genfstab -U /mnt >> /mnt/etc/fstab
sudo debootstrap --arch amd64 noble /mnt http://archive.ubuntu.com/ubuntu/

echo "Chrooting ..."
for i in /dev /dev/pts /proc /sys /run; do sudo mount -B $i /mnt$i; done
cp ./install.sh /mnt/root/install.sh
chmod +x /mnt/root/install.sh
sudo chroot /mnt
