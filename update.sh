#!/bin/bash

# System Console leeren zur besseren Übersicht
clear

current_year=$(date +"%Y")

echo -e "\e[1;34m=====================================\e[0m"
echo -e "\e[1;32m           System Wartung            \e[0m"
echo -e "\e[1;34m=====================================\e[0m"
echo -e "\nVersion: 2.9"
echo -e "\nProgrammer: Xanic\n© $current_year Xanic. Alle Rechte vorbehalten."
sleep 3

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

# Funktion, um die Paketliste zu aktualisieren und den Speicherplatz zu berechnen
update_package_list() {
    initial_free_space=$(get_free_space)

    echo -e "\n\e[1;33mAktualisiere die Paketliste...\e[0m"
    if sudo apt update -qq; then
        echo -e "\e[32mPaketliste erfolgreich aktualisiert.\e[0m"
    else
        echo -e "\e[31mFehler beim Aktualisieren der Paketliste!\e[0m"
        return 1
    fi

    final_free_space=$(get_free_space)
    freed_space=$((final_free_space - initial_free_space))
    echo -e "Speicherplatzverbrauch bei der Aktualisierung: \e[1;32m$((freed_space / 1024)) MB\e[0m"
}

# Funktion, um notwendige Pakete zu installieren und den Speicherplatz zu berechnen
install_essential_packages() {
    initial_free_space=$(get_free_space)

    echo -e "\n\e[1;33mInstalliere notwendige Pakete...\e[0m"
    if sudo apt install -y -qq apt-transport-https ca-certificates sudo curl; then
        echo -e "\e[32mNotwendige Pakete erfolgreich installiert.\e[0m"
    else
        echo -e "\e[31mFehler beim Installieren der Pakete!\e[0m"
        return 1
    fi

    final_free_space=$(get_free_space)
    freed_space=$((final_free_space - initial_free_space))
    echo -e "Speicherplatzverbrauch bei der Installation: \e[1;32m$((freed_space / 1024)) MB\e[0m"
}

# Funktion, um Proxmox- oder Debian-Systeme zu erkennen und Quellen zu ändern
adjust_repositories() {
    echo -e "\n\e[1;33mAnpassung der Repositories...\e[0m"
    if grep -qi 'proxmox' /etc/os-release; then
        echo "Proxmox-System erkannt."
        sudo find /etc/apt -type f -name "*.list" -exec sed -i 's|http://|https://|g' {} +
    elif grep -qi 'debian' /etc/os-release; then
        echo "Debian-System erkannt."
        sudo find /etc/apt -type f -name "*.list" -exec sed -i 's|http://|https://|g' {} +
    else
        echo "Kein Proxmox- oder Debian-System erkannt. Keine Änderungen vorgenommen."
    fi
}

# Funktion, um das System zu aktualisieren und zu bereinigen
upgrade_system() {
    initial_free_space=$(get_free_space)

    echo -e "\n\e[1;33mFühre Systemaktualisierung durch...\e[0m"
    if sudo apt dist-upgrade -y && sudo apt autoremove -y; then
        echo -e "\e[32mSystem erfolgreich aktualisiert und bereinigt.\e[0m"
    else
        echo -e "\e[31mFehler bei der Systemaktualisierung!\e[0m"
        return 1
    fi

    final_free_space=$(get_free_space)
    freed_space=$((final_free_space - initial_free_space))
    echo -e "Speicherplatzverbrauch bei der Aktualisierung: \e[1;32m$((freed_space / 1024)) MB\e[0m"
}

# Funktion, um nach Updates zu fragen und den Ablauf zu steuern
ask_for_updates() {
    read -p "Möchten Sie nach Updates suchen und diese installieren? (ja/nein): " answer
    case $answer in
        [Jj][Aa]|[Jj])
            echo -e "\n\e[1;33mSuche nach Updates und installiere diese...\e[0m"
            update_package_list && \
            install_essential_packages && \
            adjust_repositories && \
            upgrade_system
            ;;
        *)
            echo -e "\n\e[1;31mUpdates werden nicht durchgeführt.\e[0m"
            ;;
    esac
}

# Menü zur Auswahl der Aktion
show_menu() {
    echo -e "\n\e[1;34m=====================================\e[0m"
    echo -e "\e[1;32m         Bitte wählen Sie eine Option:\e[0m"
    echo -e "\e[1;34m=====================================\e[0m"
    echo -e "\n\e[1;36m   1) Cache leeren\e[0m"
    echo -e "\e[1;36m   2) Nach Updates suchen und installieren\e[0m"
    echo -e "\e[1;36m   3) System neu starten\e[0m"
    echo -e "\e[1;36m   4) Beenden\e[0m"
    echo -e "\n\e[1;34m=====================================\e[0m"
}

# Hauptprogramm
while true; do
    show_menu
    echo -e "\nBitte treffen Sie eine Auswahl:"
    read -p "Ihre Wahl: " choice
    echo "Eingegebene Wahl: '$choice'"
    case $choice in
        1) ask_to_clear_cache ;;
        2) ask_for_updates ;;
        3) ask_for_reboot ;;
        4) echo -e "\n\e[1;32mBeenden...\e[0m" && exit 0 ;;
        *) 
            echo -e "\n\e[1;31mUngültige Auswahl. Bitte versuchen Sie es erneut.\e[0m"
            sleep 2  # Warte 2 Sekunden, bevor das Menü erneut angezeigt wird
            ;;
    esac
done

