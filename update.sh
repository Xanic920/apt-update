#!/bin/bash

# System Console leeren zur besseren Übersicht
clear

echo "Version: 2.0"
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

# Funktion, um den Cache zu leeren
ask_to_clear_cache() {
    read -p "Möchten Sie den Cache leeren? (ja/nein): " answer
    case $answer in
        [Jj][Aa]|[Jj]) 
            initial_free_space=$(get_free_space)

            echo "Leere Cache..."
            sudo sync
            echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
            [[ "$(command -v apt)" ]] && sudo apt clean
            sudo journalctl --vacuum-time=1d
            [[ "$(uname)" == "Darwin" ]] && sudo killall -HUP mDNSResponder

            echo "System-Caches wurden erfolgreich geleert."

            final_free_space=$(get_free_space)
            freed_space=$((final_free_space - initial_free_space))
            echo "Freigegebener Speicherplatz: $((freed_space / 1024)) MB"
            ;;
        *) 
            echo "Cache wird nicht geleert."
            return 1
            ;;
    esac
}

# Funktion, um nach Updates zu suchen
ask_for_updates() {
    read -p "Möchten Sie nach Updates suchen und diese installieren? (ja/nein): " answer
    case $answer in
        [Jj][Aa]|[Jj]) 
            echo "Suche nach Updates und installiere diese..."
            sudo apt update -qq && echo -e "\e[32mPaketliste erfolgreich aktualisiert.\e[0m" || echo -e "\e[31mFehler beim Aktualisieren der Paketliste!\e[0m"
            sudo apt install -y -qq apt-transport-https ca-certificates sudo curl \
                && echo -e "\e[32mNotwendige Pakete erfolgreich installiert.\e[0m" \
                || echo -e "\e[31mFehler beim Installieren der Pakete!\e[0m"
            
            if grep -qi 'proxmox' /etc/os-release; then
                echo "Proxmox-System erkannt."
                sudo find /etc/apt -type f -name "*.list" -exec sed -i 's|http://|https://|g' {} +
            elif grep -qi 'debian' /etc/os-release; then
                echo "Debian-System erkannt."
                sudo find /etc/apt -type f -name "*.list" -exec sed -i 's|http://|https://|g' {} +
            else
                echo "Kein Proxmox- oder Debian-System erkannt. Keine Änderungen vorgenommen."
            fi
            
            sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y
            ;;
        *) 
            echo "Updates werden nicht durchgeführt."
            ;;
    esac
}

# Menü zur Auswahl der Aktion
show_menu() {
    clear
    echo "Bitte wählen Sie eine Option:"
    echo "1) Cache leeren"
    echo "2) Nach Updates suchen und installieren"
    echo "3) System neu starten"
    echo "4) Beenden"
}

# Hauptprogramm
while true; do
    show_menu
    read -p "Ihre Wahl: " choice
    case $choice in
        1) ask_to_clear_cache ;;
        2) ask_for_updates ;;
        3) ask_for_reboot ;;
        4) echo "Beenden..." && exit 0 ;;
        *) echo "Ungültige Auswahl. Bitte versuchen Sie es erneut." ;;
    esac
done
