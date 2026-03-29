#!/bin/bash
set -euo pipefail

SCRIPT_VERSION="2.1.2"
LOG_DIR="/var/log/xanic/xupdate"
LOG_FILE=""

log() { echo -e "\033[1;32m[*]\033[0m $*"; }
err() { echo -e "\033[1;31m[!]\033[0m $*" >&2; }

require_root() {
  [ "$(id -u)" -eq 0 ] || { err "Nur als root."; exit 1; }
}

setup_logging() {
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/update-$(date +%Y%m%d-%H%M%S).log"
  ls -1t "$LOG_DIR"/update-*.log 2>/dev/null | awk 'NR>3' | xargs -r rm -f || true
  exec > >(tee -a "$LOG_FILE") 2>&1
}

get_debian_version() {
  . /etc/os-release
  echo "${VERSION_ID%%.*}"
}

# -------- PREREQS --------
install_prereqs() {
  local pkgs=(ca-certificates tzdata curl)

  # apt-transport-https nur für alte Systeme
  if [ "$DEB_VER" -lt 10 ]; then
    pkgs+=(apt-transport-https)
  fi

  log "Prüfe benötigte Pakete..."
  for pkg in "${pkgs[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      log "Installiere $pkg"
      apt-get install -y "$pkg"
    else
      log "$pkg bereits installiert"
    fi
  done
}

# -------- APT HTTPS --------
switch_apt_to_https() {
  log "Prüfe ob HTTP-Repos existieren..."

  local changed=0

  while IFS= read -r -d '' file; do
    if grep -qE '^deb .*http://' "$file"; then
      log "Bearbeite $file"

      sed -i -E \
        '/download\.proxmox\.com/! s|http://|https://|g' \
        "$file"

      changed=1
    fi
  done < <(find /etc/apt -type f -name '*.list' -print0)

  if [ "$changed" -eq 1 ]; then
    log "APT Quellen wurden angepasst"
    apt-get update
  else
    log "Keine HTTP Quellen gefunden"
  fi
}

# -------- UPDATE CHECK --------
updates_available() {
  apt-get update -qq

  local upgrades
  upgrades=$(apt-get -s upgrade | grep -c "^Inst" || true)

  [ "$upgrades" -gt 0 ]
}

do_upgrade_if_needed() {
  if updates_available; then
    log "Updates verfügbar → installiere"
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
  else
    log "Keine Updates vorhanden → überspringe"
  fi
}

# -------- CLEANUP --------
apt_cleanup() {
  log "Bereinige APT nur wenn nötig"

  if [ -n "$(apt-get autoremove --dry-run | grep '^Remv')" ]; then
    apt-get autoremove -y
  else
    log "Nichts zu autoremove"
  fi

  apt-get autoclean -y
}

# -------- TIMEZONE --------
set_timezone() {
  local tz="Europe/Berlin"

  if [ "$(cat /etc/timezone 2>/dev/null || true)" != "$tz" ]; then
    log "Setze Zeitzone"
    echo "$tz" > /etc/timezone
    ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
    dpkg-reconfigure -f noninteractive tzdata
  else
    log "Zeitzone bereits korrekt"
  fi
}

# -------- POSTFIX --------
reload_postfix() {
  if systemctl is-active postfix >/dev/null 2>&1; then
    log "Reload Postfix"
    systemctl reload postfix || systemctl restart postfix
  else
    log "Postfix nicht aktiv"
  fi
}

# -------- CLEAN FILES --------
cleanup_if_needed() {
  log "Prüfe ob Cleanup sinnvoll ist"

  local size
  size=$(du -s /var/log | awk '{print $1}')

  if [ "$size" -gt 500000 ]; then
    log "Logs groß → bereinige"
    journalctl --vacuum-time=7d || true
  else
    log "Logs klein → überspringe"
  fi
}

# -------- LAUNCHER --------
install_launcher() {
  if [ ! -f /usr/local/bin/xupdate ]; then
    log "Installiere xupdate"
    cat > /usr/local/bin/xupdate <<'EOF'
#!/bin/bash
set -e
curl -fsSL https://update.xanic.eu/ | bash
EOF
    chmod +x /usr/local/bin/xupdate
  else
    log "xupdate existiert bereits"
  fi
}

# -------- HEALTH CHECK --------
healthcheck() {
  log "Starte Healthcheck..."

  # RAM
  log "RAM-Auslastung:"
  free -h

  # Load
  log "Systemlast:"
  uptime

  # Disk Usage
  log "Speicherplatz:"
  df -h

  # SMART (nur wenn installiert)
  if command -v smartctl >/dev/null 2>&1; then
    log "SMART Status (sda):"
    smartctl -H /dev/sda || true
  else
    log "smartctl nicht installiert – überspringe Disk Health"
  fi

  log "Healthcheck abgeschlossen"
}

# -------- Check Reboot Requiered --------
check_reboot_required() {
  if [ -f /var/run/reboot-required ]; then
    echo
    echo "############################################################"
    echo "#                                                          #"
    echo "#   ⚠️  NEUSTART ERFORDERLICH!                             #"
    echo "#                                                          #"
    echo "#   Es wurden sicherheitsrelevante Updates installiert.    #"
    echo "#   Das System läuft noch mit alten Komponenten.           #"
    echo "#                                                          #"
    echo "#   → Ein Neustart wird dringend empfohlen!                #"
    echo "#                                                          #"
    echo "############################################################"
    echo
  else
    log "Kein Neustart erforderlich"
  fi
}



# -------- MAIN --------
main() {
  require_root
  setup_logging

  log "Skript-Version: $SCRIPT_VERSION"

  DEB_VER=$(get_debian_version)
  log "Debian Version: $DEB_VER"

  install_prereqs
  switch_apt_to_https
  do_upgrade_if_needed
  apt_cleanup
  cleanup_if_needed
  set_timezone
  reload_postfix
  install_launcher

  echo
  if [ -r /dev/tty ]; then
    read -r -p "Healthcheck durchführen? [y/N] " answer < /dev/tty
  else
    answer="n"
  fi

  case "$answer" in
    [yY]|[yY][eE][sS])
      healthcheck
      ;;
    *)
      log "Healthcheck übersprungen"
      ;;
  esac

  check_reboot_required

  log "Fertig"
}

main "$@"
