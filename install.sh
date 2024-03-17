#!/bin/bash

apt update -y
apt upgrade -y
apt install -y ubuntu-server
add-apt-repository -y universe

apt update -y
apt install -y linux-{,image-,headers-}generic linux-firmware
#linux-generic-hwe-22.04 linux-headers-generic-hwe-22.04 initramfs-tools cryptsetup
#cryptsetup-initramfs dropbear-initramfs efibootmgr keyutils btrfs-progs grub-efi-amd64-signed grub-pc zstd curl wget command-not-found parted ubuntu-server mc
apt install -y grub2-common grub-efi-amd64 dropbear-initramfs cryptsetup cryptsetup-initramfs efibootmgr keyutils btrfs-progs zstd curl wget parted command-not-found ssh-import-id
apt install -y mc
ssh-import-id gh:killua-eu
ssh-import-id gh:killua-eu -o /etc/dropbear/initramfs/authorized_keys
cd /etc/dropbear/initramfs

echo "GRUB_ENABLE_CRYPTODISK=y" > /etc/default/grub.d/cryptodisk.cfg
echo "GRUB_DISABLE_OS_PROBER=false" > /etc/default/grub.d/osprober.cfg

FILE="/etc/dropbear/initramfs/dropbear.conf"
OPTIONS_LINE='DROPBEAR_OPTIONS="-I 180 -j -k -p 2222 -s -c cryptroot-unlock"'

if ! grep -Fxq "$OPTIONS_LINE" "$FILE_PATH"; then
    sudo sed -i '/^DROPBEAR_OPTIONS=/d' "$FILE_PATH"
    echo "$OPTIONS_LINE" | sudo tee -a "$FILE_PATH" > /dev/null
fi

echo "# <target name>	<source device>		<key file>	<options>" > /etc/crypttab
echo "crypt1 UUID=$(blkid -s UUID -o value /dev/disk/by-partlabel/prim1 | tr -d '\n') none luks,discard" >> /etc/crypttab
echo "crypt2 UUID=$(blkid -s UUID -o value /dev/disk/by-partlabel/prim2 | tr -d '\n') none luks,discard" >> /etc/crypttab

update-grub
update-initramfs -u -k all
grub-install /dev/vda # !!!!!!
grub-install /dev/vdb # !!!!!!
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Ubuntu
update-grub


FIRSTUSER="killua"
SETHOSTNAME="myhost"
IMPORTSSH="gh:killua-eu"
echo "${SETHOSTNAME}" > /etc/hostname
sudo useradd ${FIRSTUSER} -mG users,sudo,adm,plugdev,lxd -s /bin/bash
ssh-import-id $IMPORTSSH -o /home/${FIRSTUSER}/.ssh/authorized_keys

# After first boot
timedatectl set-timezone Europe/Prague
systemctl enable fstrim.timer
systemctl enable systemd-timesyncd
hostnamectl status
hostnamectl set-hostname ${SETHOSTNAME}



