#!/bin/bash

# After first boot
timedatectl set-timezone Europe/Prague
systemctl enable fstrim.timer
systemctl enable systemd-timesyncd
hostnamectl status
#hostnamectl set-hostname ${HOSTNAME}
