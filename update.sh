#!/bin/bash

# System Console leeren zur besseren Übersicht
clear

echo "Version: 1.8"
echo ""

# Funktion, um den freien Speicherplatz in Kilobytes auszulesen
get_free_space() {
	df --output=avail / | tail -n 1
}

# Funktion, um nach einem Neustart zu fragen
ask_for_reboot() {
	read -p "Möchten Sie das System jetzt neu starten? (ja/nein): " answer
	case $answer in
		[Jj][Aa]|[Jj]) 
			echo "System wird neu gestartet..."
			sudo reboot
			;;
		[Nn][Ee][Ii][Nn]|[Nn]) 
			echo "System wird nicht neu gestartet."
			;;
		*) 
			echo "Ungültige Eingabe. System wird nicht neu gestartet."
			;;
	esac
}

ask_to_clear_cache() {
	read -p "Möchten Sie den $1 Cache leeren? (ja/nein): " answer
	case $answer in
		[Jj][Aa]|[Jj]) 
			return 0  # Zustimmung
			# Initialen freien Speicherplatz erfassen
			initial_free_space=$(get_free_space)
			
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
			
			# Finalen freien Speicherplatz erfassen
			final_free_space=$(get_free_space)
			
			# Berechnen, wie viel Speicherplatz freigegeben wurde
			freed_space=$((final_free_space - initial_free_space))
			
			# Ausgabe des freigegebenen Speicherplatzes in MB
			echo "Freigegebener Speicherplatz: $((freed_space / 1024)) MB"
			;;
		*) 
			echo "$1 Cache wird nicht geleert."
			return 1  # Ablehnung
			;;
	esac
}

ask_for_updates() {
	read -p "Möchten Sie nach Updates suchen und diese installieren? (ja/nein): " answer
	case $answer in
		[Jj][Aa]|[Jj]) 
			echo "Suche nach Updates und installiere diese..."
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
			;;
		*) 
			echo "Updates werden nicht durchgeführt."
			;;
	esac
}

# Beispiel für die Nutzung bei Page Cache
ask_to_clear_cache "Page"

# Nutzung der Funktion
ask_for_updates

# Frage nach Neustart
ask_for_reboot
