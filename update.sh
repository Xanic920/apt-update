#!/bin/bash

# System Console leeren zur besseren Übersicht
clear

# Titel anzeigen
current_year=$(date +"%Y")
echo -e "\e[1;34m=====================================\e[0m"
echo -e "\e[1;32m       System Wartung (v4.0)         \e[0m"
echo -e "\e[1;34m=====================================\e[0m"
echo -e "Programmer: Xanic\n© $current_year Xanic. Alle Rechte vorbehalten."
echo -e "Program is loading...\n"
sleep 1

# Funktion, um den freien Speicherplatz anzuzeigen
get_free_space() {
    df --output=avail / | tail -n 1
}

# Cache leeren
clear_cache() {
    echo -e "\n\e[1;33mLeere Cache...\e[0m"
    sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    sudo apt clean && sudo journalctl --vacuum-time=1d
    echo -e "\e[1;32mCache erfolgreich geleert.\e[0m"
}

# System aktualisieren und notwendige Pakete installieren
update_system() {
    echo -e "\n\e[1;33mAktualisiere Paketliste und installiere notwendige Pakete...\e[0m"
    sudo apt update -qq && sudo apt install -y -qq apt-transport-https ca-certificates curl
    sudo apt dist-upgrade -y && sudo apt autoremove -y
    echo -e "\e[1;32mSystem erfolgreich aktualisiert.\e[0m"
}

# Repositories anpassen
adjust_repositories() {
    echo -e "\n\e[1;33mAnpassung der Repositories...\e[0m"
    if grep -qi 'proxmox' /etc/os-release; then
        echo "Proxmox erkannt."
    elif grep -qi 'debian' /etc/os-release; then
        echo "Debian erkannt."
    else
        echo "Kein bekanntes System erkannt."
    fi
    sudo find /etc/apt -type f -name "*.list" -exec sed -i 's|http://|https://|g' {} +
    echo -e "\e[1;32mRepositories angepasst.\e[0m"
}

# Neustart durchführen
reboot_system() {
    echo -e "\n\e[1;33mSystem wird neu gestartet...\e[0m"
    sudo reboot
}

# Hauptmenü anzeigen
show_menu() {
    echo -e "\n\e[1;34m=================== Menü ===================\e[0m"
    echo -e "\e[1;36m 1) System Update\e[0m"
    echo -e "\e[1;36m 2) Cache leeren\e[0m"
    echo -e "\e[1;36m 3) Repositories anpassen\e[0m"
    echo -e "\e[1;36m 4) Neustart\e[0m"
    echo -e "\e[1;31m 5) Beenden\e[0m"
}

# Hauptprogramm
while true; do
    show_menu
    read -p "Wählen Sie eine Option: " choice
    case $choice in
        1) update_system ;;
        2) clear_cache ;;
        3) adjust_repositories ;;
        4) reboot_system ;;
        5) echo -e "\n\e[1;32mBye, bye! :-(\e[0m" && exit 0 ;;
        *) echo -e "\e[1;31mUngültige Eingabe!\e[0m" ;;
    esac
done
