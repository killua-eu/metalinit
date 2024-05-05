#!/bin/bash

# After first boot
sudo timedatectl set-timezone Europe/Prague
sudo systemctl enable fstrim.timer
sudo systemctl enable systemd-timesyncd
sudo hostnamectl status
sudo systemctl enable ssh
sudo systemctl start ssh
sudo hostnamectl set-hostname