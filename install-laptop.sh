#!/bin/bash

DEVICE_FILE="devices.tmp"

if [ ! -f "$DEVICE_FILE" ]; then
    echo "Device file does not exist: $DEVICE_FILE"
    exit 1
fi

# Check for environment variables or ask for them
: "${USERNAME:=$(read -p "Enter the username: " REPLY; echo $REPLY)}"
: "${PASSWORD:=$(read -p "Enter the password for $USERNAME: " REPLY; echo $REPLY)}"
: "${HOSTNAME:=$(read -p "Enter the hostname: " REPLY; echo $REPLY)}"
: "${GETSSHID:=$(read -p "Enter the ssh-import-id (i.e. gh:username for github): " REPLY; echo $REPLY)}"

apt --fix-broken install
apt update -y
apt upgrade -y
apt install -y ubuntu-server software-properties-common
add-apt-repository -y universe

echo "# <target name>	<source device>		<key file>	<options>" > /etc/crypttab
echo "crypt1 UUID=$(blkid -s UUID -o value /dev/disk/by-partlabel/prim1 | tr -d '\n') none luks,discard" >> /etc/crypttab

apt update -y
apt install -y linux-{,image-,headers-}generic linux-firmware \
               grub2-common grub-efi-amd64 efibootmgr \
               cryptsetup btrfs-progs zstd \
               dropbear-initramfs cryptsetup-initramfs \
               openssh-server \
               keyutils curl wget parted command-not-found ssh-import-id \
               mc nano jq pastebinit sudo

ssh-import-id "${GETSSHID}"
ssh-import-id "${GETSSHID}" -o /etc/dropbear/initramfs/authorized_keys
chmod 600 /etc/dropbear/initramfs/authorized_keys

cd /etc/dropbear/initramfs

echo "GRUB_ENABLE_CRYPTODISK=y" > /etc/default/grub.d/cryptodisk.cfg
echo "GRUB_DISABLE_OS_PROBER=false" > /etc/default/grub.d/osprober.cfg

FILE="/etc/dropbear/initramfs/dropbear.conf"
OPTIONS_LINE='DROPBEAR_OPTIONS="-I 180 -j -k -p 2222 -s -c cryptroot-unlock"'

if ! grep -Fxq "$OPTIONS_LINE" "$FILE_PATH"; then
    sed -i '/^DROPBEAR_OPTIONS=/d' "$FILE_PATH"
    echo "$OPTIONS_LINE" | sudo tee -a "$FILE_PATH" > /dev/null
fi

update-grub
update-initramfs -u -k all
while IFS= read -r device; do
    echo "Running grub-install on $device..."
    grub-install "$device"
done < "$DEVICE_FILE"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Ubuntu
update-grub

echo "${HOSTNAME}" > /etc/hostname
useradd ${USERNAME} -mG users,sudo,adm,plugdev,lxd -s /bin/bash
echo "${USERNAME}:${PASSWORD}" | sudo chpasswd

ssh-import-id GETSSHID -o /home/${USERNAME}/.ssh/authorized_keys

# After first boot
timedatectl set-timezone Europe/Prague
systemctl enable fstrim.timer
systemctl enable systemd-timesyncd
hostnamectl status
hostnamectl set-hostname ${HOSTNAME}



