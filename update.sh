#!/bin/bash

# System Console leeren zur besseren Übersicht
clear

echo -e "\e[1;34m=====================================\e[0m"
echo -e "\e[1;32m           System Wartung            \e[0m"
echo -e "\e[1;34m=====================================\e[0m"
echo -e "\nVersion: 2.1\n"

# Funktion, um den freien Speicherplatz in Kilobytes auszulesen
get_free_space() {
    df --output=avail / | tail -n 1
}

# Funktion, um nach einem Neustart zu fragen
ask_for_reboot() {
    read -p "Möchten Sie das System jetzt neu starten? (ja/nein): " answer
    case $answer in
        [Jj][Aa]|[Jj]) 
            echo -e "\n\e[1;33mSystem wird neu gestartet...\e[0m"
            sudo reboot
            ;;
        [Nn][Ee][Ii][Nn]|[Nn]) 
            echo -e "\n\e[1;33mSystem wird nicht neu gestartet.\e[0m"
            ;;
        *) 
            echo -e "\n\e[1;31mUngültige Eingabe. System wird nicht neu gestartet.\e[0m"
            ;;
    esac
}

# Funktion, um den Cache zu leeren
ask_to_clear_cache() {
    read -p "Möchten Sie den Cache leeren? (ja/nein): " answer
    case $answer in
        [Jj][Aa]|[Jj]) 
            initial_free_space=$(get_free_space)

            echo -e "\n\e[1;33mLeere Cache...\e[0m"
            sudo sync
            echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
            [[ "$(command -v apt)" ]] && sudo apt clean
            sudo journalctl --vacuum-time=1d
            [[ "$(uname)" == "Darwin" ]] && sudo killall -HUP mDNSResponder

            echo -e "\n\e[1;32mSystem-Caches wurden erfolgreich geleert.\e[0m"

            final_free_space=$(get_free_space)
            freed_space=$((final_free_space - initial_free_space))
            echo -e "Freigegebener Speicherplatz: \e[1;32m$((freed_space / 1024)) MB\e[0m"
            ;;
        *) 
            echo -e "\n\e[1;31mCache wird nicht geleert.\e[0m"
            return 1
            ;;
    esac
}

# Funktion, um nach Updates zu suchen
ask_for_updates() {
    read -p "Möchten Sie nach Updates suchen und diese installieren? (ja/nein): " answer
    case $answer in
        [Jj][Aa]|[Jj]) 
            echo -e "\n\e[1;33mSuche nach Updates und installiere diese...\e[0m"
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
            echo -e "\n\e[1;31mUpdates werden nicht durchgeführt.\e[0m"
            ;;
    esac
}

# Menü zur Auswahl der Aktion
show_menu() {
    echo -e "\n\e[1;34mBitte wählen Sie eine Option:\e[0m"
    echo -e "\e[1;36m1) Cache leeren\e[0m"
    echo -e "\e[1;36m2) Nach Updates suchen und installieren\e[0m"
    echo -e "\e[1;36m3) System neu starten\e[0m"
    echo -e "\e[1;36m4) Beenden\e[0m"
}

# Hauptprogramm
while true; do
    show_menu
    read -p "Ihre Wahl: " choice
    case $choice in
        1) ask_to_clear_cache ;;
        2) ask_for_updates ;;
        3) ask_for_reboot ;;
        4) echo -e "\n\e[1;32mBeenden...\e[0m" && exit 0 ;;
        *) echo -e "\n\e[1;31mUngültige Auswahl. Bitte versuchen Sie es erneut.\e[0m" ;;
    esac
done
