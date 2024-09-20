#!/bin/bash

# Update the package list and install necessary packages
apt update && apt install apt-transport-https ca-certificates sudo curl -y

# Systemerkennung
if grep -qi 'proxmox' /etc/os-release; then
    echo "Proxmox-System erkannt."
    # Anpassungen für Proxmox-Repositories
    sudo find /etc/apt -type f -name "*.list" -exec sed -i '
    # Proxmox Repository Anpassung für Bookworm
    /^deb http:\/\/download.proxmox.com\/debian\/pve bookworm/!s|http://|https://|g
    # Proxmox Repository Anpassung für Bullseye
    /^deb http:\/\/download.proxmox.com\/debian\/pve bullseye/!s|http://|https://|g
    # Proxmox Repository Anpassung für Buster
    /^deb http:\/\/download.proxmox.com\/debian\/pve buster/!s|http://|https://|g
    ' {} +
elif grep -qi 'debian' /etc/os-release; then
    echo "Debian-System erkannt."
    # Anpassungen für Debian-Repositories
    sudo find /etc/apt -type f -name "*.list" -exec sed -i '
    # Debian Repository Anpassung für Bookworm
    /^deb http:\/\/deb.debian.org\/debian bookworm/!s|http://|https://|g
    # Debian Repository Anpassung für Bullseye
    /^deb http:\/\/deb.debian.org\/debian bullseye/!s|http://|https://|g
    # Debian Repository Anpassung für Buster
    /^deb http:\/\/deb.debian.org\/debian buster/!s|http://|https://|g
    ' {} +
else
    echo "Kein Proxmox- oder Debian-System erkannt. Keine Änderungen vorgenommen."
fi

# Update, upgrade, and remove unnecessary packages
apt update && apt dist-upgrade -y && apt autoremove -y
