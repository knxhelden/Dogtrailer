#!/usr/bin/env bash
set -euo pipefail

### ───────── Konfiguration ─────────
APP_NAME="dogtrailer"
INSTALL_DIR="/opt/${APP_NAME}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
SERVICE_PORT="5000"

### ───────── Helpers ─────────
log()  { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err()  { echo -e "\033[1;31m[✗] $*\033[0m" >&2; }
require_root() { [[ $EUID -eq 0 ]] || { err "Bitte mit sudo ausführen."; exit 1; }; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

### ───────── Start ─────────
require_root

log "Stoppe Dienst (falls aktiv) …"
systemctl stop "${APP_NAME}.service" 2>/dev/null || true

log "Deaktiviere Dienst (Autostart entfernen) …"
systemctl disable "${APP_NAME}.service" 2>/dev/null || true

if [[ -f "${SERVICE_FILE}" ]]; then
  log "Entferne systemd-Unit ${SERVICE_FILE} …"
  rm -f "${SERVICE_FILE}"
  log "systemd neu laden …"
  systemctl daemon-reload
else
  warn "Keine Unit-Datei gefunden unter ${SERVICE_FILE} – überspringe."
fi

# Installationsverzeichnis weg
if [[ -d "${INSTALL_DIR}" ]]; then
  log "Entferne Installationsverzeichnis ${INSTALL_DIR} …"
  rm -rf "${INSTALL_DIR}"
else
  warn "Installationsverzeichnis ${INSTALL_DIR} existiert nicht – überspringe."
fi

log "Uninstall abgeschlossen."
echo "• Falls du Gruppenrechte manuell gesetzt hattest (video/gpio), bleiben diese beim Nutzer bestehen."
echo "• Prüfe mit: sudo systemctl status ${APP_NAME}.service (sollte 'not-found' melden)"