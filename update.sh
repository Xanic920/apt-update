#!/bin/bash

# System Console leeren zur besseren Übersicht
clear

echo "Version: 1.1"
echo ""

echo "System-Caches werden geleert..."

# Page Cache, dentries und inodes leeren
echo "Leere Page Cache, dentries und inodes..."
sudo sync
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null

# APT Cache leeren (nur auf Debian-basierten Systemen wie Ubuntu)
if command -v apt >/dev/null 2>&1; then
    echo "Leere APT-Cache..."
    sudo apt clean
fi

# Systemd Journal Cache leeren
echo "Leere Systemd Journal..."
sudo journalctl --vacuum-time=1d

# DNS Cache leeren (macOS Beispiel, bei Linux je nach Distribution unterschiedlich)
if [[ "$(uname)" == "Darwin" ]]; then
    echo "Leere DNS-Cache auf macOS..."
    sudo killall -HUP mDNSResponder
else
    echo "DNS-Cache leeren auf Linux (falls notwendig, je nach Distribution unterschiedlich)"
fi

echo "System-Caches wurden erfolgreich geleert."

# Aktualisiere die Paketliste und installiere die notwendigen Pakete.
echo "Aktualisiere die Paketliste..."
sudo apt update -qq && echo -e "\e[32mPaketliste erfolgreich aktualisiert.\e[0m" || echo -e "\e[31mFehler beim Aktualisieren der Paketliste!\e[0m"

echo "Installiere notwendige Pakete..."
sudo apt install -y -qq apt-transport-https ca-certificates sudo curl \
  && echo -e "\e[32mNotwendige Pakete erfolgreich installiert.\e[0m" \
  || echo -e "\e[31mFehler beim Installieren der Pakete!\e[0m"

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
