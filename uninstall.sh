#!/usr/bin/env bash
set -euo pipefail

### ───────── Configuration ─────────
APP_NAME="dogtrailer"
INSTALL_DIR="/opt/${APP_NAME}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
SERVICE_PORT="5000"

# Access Point (must match install.sh)
HOTSPOT_IF="wlan0"
HOTSPOT_CON_NAME="Hotspot"
HOTSPOT_HELPER_UNIT="/etc/systemd/system/dogtrailer-hotspot.service"  # if ever created

### ───────── Helpers ─────────
log()  { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err()  { echo -e "\033[1;31m[✗] $*\033[0m" >&2; }
require_root() { [[ $EUID -eq 0 ]] || { err "Please run with sudo."; exit 1; }; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

### ───────── Start ─────────
require_root

log "Stopping service (if running) …"
systemctl stop "${APP_NAME}.service" 2>/dev/null || true

log "Disabling service (remove autostart) …"
systemctl disable "${APP_NAME}.service" 2>/dev/null || true

# Disable/remove optional Hotspot helper unit
if [[ -f "${HOTSPOT_HELPER_UNIT}" ]]; then
  log "Disabling & removing Hotspot helper unit …"
  systemctl disable "$(basename "${HOTSPOT_HELPER_UNIT}")" 2>/dev/null || true
  rm -f "${HOTSPOT_HELPER_UNIT}"
fi

# Remove systemd unit file
if [[ -f "${SERVICE_FILE}" ]]; then
  log "Removing unit file ${SERVICE_FILE} …"
  rm -f "${SERVICE_FILE}"
else
  warn "No unit file found at ${SERVICE_FILE} – skipping."
fi

log "Reloading systemd daemon …"
systemctl daemon-reload

# Free TCP port
log "Freeing port ${SERVICE_PORT}/tcp …"
fuser -k ${SERVICE_PORT}/tcp 2>/dev/null || true
pkill -f "gunicorn.*:${SERVICE_PORT}" 2>/dev/null || true

# Remove UFW rule if active
if cmd_exists ufw && ufw status | grep -q "Status: active"; then
  log "Removing UFW rule for port ${SERVICE_PORT}/tcp (if present) …"
  ufw delete allow ${SERVICE_PORT}/tcp >/dev/null 2>&1 || true
fi

# Remove NetworkManager Hotspot profile safely
if cmd_exists nmcli; then
  if nmcli -t -f NAME connection show | grep -Fxq "${HOTSPOT_CON_NAME}"; then
    # Is the Hotspot active?
    if nmcli -t -f NAME,DEVICE,TYPE,STATE connection show --active 2>/dev/null \
       | awk -F: -v n="${HOTSPOT_CON_NAME}" '$1==n && $3=="wifi" && $4=="activated"{f=1} END{exit !f}'; then
      warn "Hotspot '${HOTSPOT_CON_NAME}' is ACTIVE – not removing the connection profile for safety."
      warn "Manually deactivate with: nmcli connection down ${HOTSPOT_CON_NAME}  (Warning: SSH may disconnect)"
    else
      log "Deleting Hotspot connection '${HOTSPOT_CON_NAME}' …"
      nmcli connection delete "${HOTSPOT_CON_NAME}" || true
    fi
  else
    warn "No Hotspot connection '${HOTSPOT_CON_NAME}' found – skipping."
  fi
fi

# Remove installation directory
if [[ -d "${INSTALL_DIR}" ]]; then
  log "Removing installation directory ${INSTALL_DIR} …"
  rm -rf "${INSTALL_DIR}"
else
  warn "Installation directory ${INSTALL_DIR} does not exist – skipping."
fi

echo
log "Uninstall finished."
echo "• Check: sudo systemctl status ${APP_NAME}.service   (should report 'not-found')"
echo "• If the Hotspot was active and you want to keep it: no further action required."
echo "• If you want to remove it: run 'nmcli connection down ${HOTSPOT_CON_NAME}' and then run this script again."