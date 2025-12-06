#!/bin/bash
# Debian 13 Wartungs-Skript:
# - Apt-Repos von http -> https (ohne Proxmox)
# - System-Update & Upgrade
# - APT-Cache bereinigen
# - Optionale Log-/Temp-Bereinigung
# - Timezone auf Europe/Berlin setzen
# - Postfix neu laden, falls vorhanden

set -euo pipefail

log() {
  echo -e "\033[1;32m[*]\033[0m $*"
}

err() {
  echo -e "\033[1;31m[!]\033[0m $*" >&2
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "Dieses Skript muss als root ausgeführt werden."
    exit 1
  fi
}

install_prereqs() {
  log "Führe apt update aus..."
  apt-get update

  log "Installiere benötigte Pakete (ca-certificates, tzdata, optional apt-transport-https)..."
  local pkgs="ca-certificates tzdata"
  if apt-cache show apt-transport-https >/dev/null 2>&1; then
    pkgs="$pkgs apt-transport-https"
  else
    log "Hinweis: Paket 'apt-transport-https' ist nicht verfügbar oder überflüssig, wird übersprungen."
  fi

  DEBIAN_FRONTEND=noninteractive apt-get install -y $pkgs
}

switch_apt_to_https() {
  log "Stelle APT-Repositories von http auf https um (ohne Proxmox)..."

  # Alle .list-Dateien unter /etc/apt durchsuchen
  find /etc/apt -type f -name '*.list' -print0 | while IFS= read -r -d '' file; do
    # In allen Zeilen, die NICHT Proxmox sind, http:// -> https://
    sed -i -E \
      '/^[[:space:]]*deb(-src)?[[:space:]].*http:\/\/download\.proxmox\.com/!s|http://|https://|g' \
      "$file"
  done
}

do_system_upgrade() {
  log "Führe apt update nach Repository-Umstellung aus..."
  apt-get update

  log "Führe dist-upgrade (vollständiges Upgrade) aus..."
  DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
}

apt_cache_cleanup() {
  log "Bereinige APT-Cache und unbenutzte Pakete..."
  # Entfernt überflüssige Pakete und alten Paket-Cache, ist laut Doku sicher. 
  apt-get autoremove -y || true
  apt-get autoclean -y || true
  apt-get clean || true
}

disk_overview() {
  log "Speicherplatz-Übersicht (ähnlich ncdu, aber nicht interaktiv):"
  echo "Top-Verzeichnisse unter /:"
  du -xh -d1 / 2>/dev/null | sort -h | tail -n 20
  echo

  if [ -d /var ]; then
    echo
    echo "Top-Verzeichnisse unter /var:"
    du -xh -d1 /var 2>/dev/null | sort -h | tail -n 20
    echo
  fi

  if [ -d /home ]; then
    echo "Top-Verzeichnisse unter /home:"
    du -xh -d1 /home 2>/dev/null | sort -h | tail -n 20
    echo
  fi
}

heavy_cleanup() {
  log "Bereinige systemd-Journal (bewahre letzte 7 Tage)..."
  if command -v journalctl >/dev/null 2>&1; then
    journalctl --vacuum-time=7d || true
  fi

  log "Bereinige klassische Logfiles in /var/log..."
  if [ -d /var/log ]; then
    # Aktuelle Logs leeren, rotierte/komprimierte entfernen
    for f in syslog messages kern.log daemon.log auth.log; do
      if [ -f "/var/log/$f" ]; then
        : > "/var/log/$f"
      fi
    done

    find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -delete 2>/dev/null || true
  fi

  log "Bereinige temporäre Verzeichnisse (/tmp, /var/tmp, /var/crash)..."
  find /tmp -mindepth 1 -mtime +7 -exec rm -rf {} + 2>/dev/null || true
  find /var/tmp -mindepth 1 -mtime +7 -exec rm -rf {} + 2>/dev/null || true

  if [ -d /var/crash ]; then
    rm -rf /var/crash/* 2>/dev/null || true
  fi
}

set_timezone_berlin() {
  log "Setze Zeitzone auf Europe/Berlin..."
  local tz="Europe/Berlin"

  if [ -f "/usr/share/zoneinfo/$tz" ]; then
    echo "$tz" > /etc/timezone
    ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime

    # Nicht-interaktive Re-Konfiguration von tzdata
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure tzdata >/dev/null 2>&1 || true
  else
    err "Zeitzonendatei /usr/share/zoneinfo/$tz wurde nicht gefunden."
  fi
}

reload_postfix_if_present() {
  if dpkg -l postfix 2>/dev/null | grep -q '^ii'; then
    log "Postfix gefunden – lade Dienst neu..."
    systemctl reload postfix 2>/dev/null || systemctl restart postfix 2>/dev/null || true
  else
    log "Postfix ist nicht installiert – überspringe Reload."
  fi
}

main() {
  require_root

  log "Starte Systempflege für Debian..."
  install_prereqs
  switch_apt_to_https
  do_system_upgrade
  apt_cache_cleanup

  # Übersicht vor optionaler Tiefenreinigung
  disk_overview

  echo
  read -r -p "Nicht benötigte Dateien (alte Logs, Temp-Dateien) löschen, um Speicherplatz freizugeben? [y/N] " answer
  case "$answer" in
    [yY][eE][sS]|[yY])
      heavy_cleanup
      ;;
    *)
      log "Tiefe Bereinigung übersprungen."
      ;;
  esac

  # Übersicht nach Bereinigung
  disk_overview

  set_timezone_berlin
  reload_postfix_if_present

  log "Fertig. System wurde aktualisiert und bereinigt."
}

main "$@"
