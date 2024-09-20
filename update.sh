#!/bin/bash

# Update the package list and install necessary packages
apt update && apt install apt-transport-https ca-certificates sudo curl -y

# Replace http with https in all .list files in /etc/apt, except for a specific line
sudo find /etc/apt -type f -name "*.list" -exec sed -i '
# Proxmox Repository Anpassung für Bookworm
/^deb http:\/\/download.proxmox.com\/debian\/pve bookworm/!s|http://|https://|g
# Proxmox Repository Anpassung für Bullseye
/^deb http:\/\/download.proxmox.com\/debian\/pve bullseye/!s|http://|https://|g
# Proxmox Repository Anpassung für Buster
/^deb http:\/\/download.proxmox.com\/debian\/pve buster/!s|http://|https://|g
' {} +
# Update, upgrade, and remove unnecessary packages
apt update && apt dist-upgrade -y && apt autoremove -y
