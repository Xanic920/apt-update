#!/bin/bash
# Wartungs-Skript für Debian >= 12
# - Bricht ab, wenn Debian-Version < 12
# - Apt-Repos von http -> https (ohne Proxmox)
# - System-Update & Upgrade
# - APT-Cache bereinigen
# - Optionale Log-/Temp-Bereinigung
# - Timezone auf Europe/Berlin setzen
# - Postfix neu laden, falls vorhanden
# - apt-transport-https auf Debian 12+ als Altlast entfernt
# - Ausgabe in Logdatei, max. 3 Logs werden aufbewahrt
# - Installiert globalen Befehl "xupdate" für künftige Updates

set -euo pipefail

SCRIPT_VERSION="1.2.1"

LOG_DIR="/var/log/xanic/xupdate"
LOG_FILE=""

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

setup_logging() {
  mkdir -p "$LOG_DIR"

  local ts
  ts="$(date +"%Y%m%d-%H%M%S")"
  LOG_FILE="$LOG_DIR/update-$ts.log"

  # Logrotation: max. 3 Logdateien behalten
  ls -1t "$LOG_DIR"/update-*.log 2>/dev/null | awk 'NR>3' | xargs -r rm -f || true

  exec > >(tee -a "$LOG_FILE") 2>&1

  log "Starte Skript-Log: $LOG_FILE"
  log "Skript-Version: $SCRIPT_VERSION"
}

get_debian_version() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" = "debian" ] && [ -n "${VERSION_ID:-}" ]; then
      echo "$VERSION_ID"
      return 0
    fi
  fi
  echo ""
  return 1
}

require_min_debian_12() {
  local deb_ver
  deb_ver="$(get_debian_version || echo "")"

  if [ -z "$deb_ver" ]; then
    err "Dieses Skript ist nur für Debian 12 oder höher vorgesehen. System konnte nicht eindeutig als Debian erkannt werden."
    exit 1
  fi

  local deb_major="${deb_ver%%.*}"

  if [ "$deb_major" -lt 12 ]; then
    err "Debian-Version $deb_ver erkannt. Dieses Skript setzt mindestens Debian 12 voraus. Abbruch."
    exit 1
  fi

  log "Debian $deb_ver erkannt – Mindestanforderung (>= 12) erfüllt."
}

install_prereqs() {
  log "Führe apt update aus..."
  apt-get update

  log "Installiere benötigte Pakete (ca-certificates, tzdata, curl)..."
  local pkgs="ca-certificates tzdata curl"

  DEBIAN_FRONTEND=noninteractive apt-get install -y $pkgs
}

install_update_launcher() {
  log "Installiere globalen Update-Befehl 'xupdate'..."

  cat > /usr/local/bin/xupdate <<'EOF'
#!/bin/bash
set -euo pipefail
curl -fsSL https://update.xanic.eu/ | bash
EOF
  chmod +x /usr/local/bin/xupdate

  # Optional: zusätzlicher Shortcut im Root-Verzeichnis
  cat > /root/update <<'EOF'
#!/bin/bash
set -euo pipefail
curl -fsSL https://update.xanic.eu/ | bash
EOF
  chmod +x /root/update

  log "Launcher erstellt:"
  log " - /usr/local/bin/xupdate"
  log " - /root/update"
}

switch_apt_to_https() {
  log "Stelle APT-Repositories von http auf https um (ohne Proxmox)..."

  find /etc/apt -type f -name '*.list' -print0 | while IFS= read -r -d '' file; do
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
  apt-get autoremove -y || true
  apt-get autoclean -y || true
  apt-get clean || true
}

disk_overview() {
  log "Speicherplatz-Übersicht (nur Verzeichnisse >= 1G):"

  show_top() {
    local path="$1"
    if [ -d "$path" ]; then
      echo "Top-Verzeichnisse unter $path (>= 1G):"
      local out
      out="$(du -xh -d1 --threshold=1G "$path" 2>/dev/null | sort -h || true)"
      if [ -n "$out" ]; then
        echo "$out"
      else
        echo "  (keine Verzeichnisse >= 1G)"
      fi
      echo
    fi
  }

  show_top "/"
  show_top "/var"
  show_top "/home"
}

heavy_cleanup() {
  log "Bereinige systemd-Journal (bewahre letzte 7 Tage)..."
  if command -v journalctl >/dev/null 2>&1; then
    journalctl --vacuum-time=7d || true
  fi

  log "Bereinige klassische Logfiles in /var/log..."
  if [ -d /var/log ]; then
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
  setup_logging
  require_min_debian_12

  log "Starte Systempflege..."
  install_prereqs
  install_update_launcher
  switch_apt_to_https
  do_system_upgrade
  apt_cache_cleanup

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

  disk_overview

  set_timezone_berlin
  reload_postfix_if_present

  log "Fertig. System wurde aktualisiert und bereinigt."
  log "Künftige Updates können mit 'xupdate' ausgeführt werden."
}

main "$@"
