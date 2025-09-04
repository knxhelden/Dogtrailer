#!/usr/bin/env bash
set -euo pipefail
trap 'echo -e "\033[1;31m[✗] Error in line $LINENO: ${BASH_COMMAND}\033[0m"; exit 1' ERR

### ────────── App Configuration ──────────
APP_NAME="dogtrailer"
REPO_URL="https://github.com/knxhelden/Dogtrailer.git"
APP_USER="${SUDO_USER:-${USER}}"
APP_GROUP="${APP_USER}"

INSTALL_DIR="/opt/${APP_NAME}"
VENV_DIR="${INSTALL_DIR}/.venv"
PYTHON_BIN="python3"
ENTRYPOINT="webapp/app.py"
SERVICE_PORT="5000"
ENV_FILE="${INSTALL_DIR}/.env"
USE_GUNICORN="true"
BIND_IPV6="false"


# ─── Access Point (NetworkManager) ─────────────────────────
HOTSPOT_IF="wlan0"
HOTSPOT_CON_NAME="Hotspot"
HOTSPOT_SSID="Dogtrailer"
HOTSPOT_PASSWORD="dogtrailer"
HOTSPOT_BAND="bg"
HOTSPOT_CHANNEL="3"
HOTSPOT_IPV4_CIDR="192.168.1.1/24"
HOTSPOT_GATEWAY="${HOTSPOT_IPV4_CIDR%/*}"


### ────────── Helpers ──────────
log()  { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err()  { echo -e "\033[1;31m[✗] $*\033[0m" >&2; }
require_root() { [[ $EUID -eq 0 ]] || { err "Please run with sudo"; exit 1; }; }
cmd_exists() { command -v "$1" &>/dev/null; }


### ────────── Start ──────────
require_root
export DEBIAN_FRONTEND=noninteractive

log "Updating system packages …"
apt-get update -y

log "Installing required packages …"
apt-get install -y --no-install-recommends \
  python3 python3-venv python3-pip \
  python3-dev build-essential \
  python3-picamera2 python3-rpi.gpio \
  libgpiod2 python3-libgpiod ca-certificates git curl

log "Installing debug tools …"
apt-get install -y --no-install-recommends libcamera-apps i2c-tools

log "Activating camera & interfaces on Raspberry Pi …"
if cmd_exists raspi-config; then
  raspi-config nonint do_camera 0 || true
  raspi-config nonint do_i2c 0 || true
  raspi-config nonint do_spi 0 || true
else
  warn "raspi-config not found – if necessary, activate camera/I2C/SPI manually."
fi

log "Adding user '${APP_USER}' to groups 'video' and 'gpio' …"
usermod -aG video,gpio "${APP_USER}" || true

log "Setting up GitHub repository in ${INSTALL_DIR} …"
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  CURRENT_BRANCH="$(git -C "${INSTALL_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  git -C "${INSTALL_DIR}" fetch --all --prune
  git -C "${INSTALL_DIR}" reset --hard "origin/${CURRENT_BRANCH}" || git -C "${INSTALL_DIR}" pull --rebase || true
else
  rm -rf "${INSTALL_DIR}"
  git clone "${REPO_URL}" "${INSTALL_DIR}"
fi

log "Fixing ownership of local repository directory …"
chown -R "${APP_USER}:${APP_GROUP}" "${INSTALL_DIR}"

log "Creating Python virtual environment …"
if [[ ! -d "${VENV_DIR}" ]]; then
  sudo -u "${APP_USER}" "${PYTHON_BIN}" -m venv --system-site-packages "${VENV_DIR}"
else
  warn "Virtualenv already exists – skipping creation."
fi

log "Installing Python dependencies from requirements.txt …"
export PIP_PREFER_BINARY=1
if [[ ! -f "${INSTALL_DIR}/requirements.txt" ]]; then
  err "requirements.txt not found in ${INSTALL_DIR}/requirements.txt"
  exit 1
fi
sudo -u "${APP_USER}" bash -lc "${VENV_DIR}/bin/pip install --upgrade pip"
sudo -u "${APP_USER}" bash -lc "${VENV_DIR}/bin/pip install -r '${INSTALL_DIR}/requirements.txt'"

log "Creating and checking .env …"
if [[ ! -f "${ENV_FILE}" ]]; then
  cat > "${ENV_FILE}" <<'EOF'
FLASK_DEBUG=0
HOST=0.0.0.0
PORT=5000
RELAIS1_PIN=23
RELAIS2_PIN=24
DHT_PIN=D4
EOF
  chown "${APP_USER}:${APP_GROUP}" "${ENV_FILE}"
  chmod 640 "${ENV_FILE}"
  log ".env created at ${ENV_FILE}"
else
  warn ".env already exists – skipping creation."
fi

# Build ExecStart
if [[ "${USE_GUNICORN}" == "true" ]]; then
  START_CMD="${VENV_DIR}/bin/gunicorn --access-logfile - -w 2 -b 0.0.0.0:${SERVICE_PORT} app:app"
  [[ "${BIND_IPV6}" == "true" ]] && START_CMD="${START_CMD} -b [::]:${SERVICE_PORT}"
else
  START_CMD="${VENV_DIR}/bin/python ${INSTALL_DIR}/${ENTRYPOINT}"
fi

# Cleanup old unit/port
systemctl stop "${APP_NAME}.service" 2>/dev/null || true
systemctl disable "${APP_NAME}.service" 2>/dev/null || true
rm -f "/etc/systemd/system/${APP_NAME}.service"
systemctl daemon-reload
fuser -k ${SERVICE_PORT}/tcp 2>/dev/null || true
pkill -f "gunicorn.*:${SERVICE_PORT}" 2>/dev/null || true

log "Creating systemd service …"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=${APP_NAME} service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${INSTALL_DIR}/webapp
EnvironmentFile=${ENV_FILE}
Environment=PYTHONUNBUFFERED=1
SupplementaryGroups=video gpio
ExecStart=${START_CMD}
Restart=on-failure
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

log "Enabling & starting service …"
systemctl daemon-reload
systemctl enable "${APP_NAME}.service"
systemctl restart "${APP_NAME}.service" || true

# UFW: Only open port if UFW is active
if cmd_exists ufw && ufw status | grep -q "Status: active"; then
  log "UFW active – allowing port ${SERVICE_PORT}/tcp …"
  ufw allow ${SERVICE_PORT}/tcp || true
fi


# Access Point
log "Configuring Access Point (NetworkManager) …"

# 0) Unblock WLAN & enable radio (idempotent)
if cmd_exists rfkill; then rfkill unblock wifi || true; fi
nmcli radio wifi on || true

# 1) Check if NetworkManager is running
if ! systemctl is-active --quiet NetworkManager; then
  err "NetworkManager is not active. Please use Raspberry Pi OS (Bookworm) with NetworkManager."
  # Do not exit hard: continue with the rest
fi

# 2) Check if interface supports AP mode (optional, just a warning)
if nmcli -f WIFI-PROPERTIES device show "${HOTSPOT_IF}" 2>/dev/null | grep -q 'WIFI-PROPERTIES.AP:\s\+yes'; then
  :
else
  warn "Interface ${HOTSPOT_IF} may not report AP support. Trying anyway."
fi

# 3) Create hotspot connection (profile only, do not activate immediately)
if ! nmcli -t -f NAME connection show | grep -Fxq "${HOTSPOT_CON_NAME}"; then
  log "Creating NM hotspot connection profile '${HOTSPOT_CON_NAME}' …"
  nmcli connection add type wifi ifname "${HOTSPOT_IF}" con-name "${HOTSPOT_CON_NAME}" \
    autoconnect no ssid "${HOTSPOT_SSID}"
  nmcli connection modify "${HOTSPOT_CON_NAME}" \
    802-11-wireless.mode ap \
    802-11-wireless.band "${HOTSPOT_BAND}" \
    802-11-wireless.channel "${HOTSPOT_CHANNEL}" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "${HOTSPOT_PASSWORD}"
else
  warn "Hotspot connection '${HOTSPOT_CON_NAME}' already exists – updating settings."
fi

# 4) IPv4/NAT sharing, static IP, autostart, IPv6 disabled
nmcli connection modify "${HOTSPOT_CON_NAME}" \
  ipv4.method shared \
  ipv4.addresses "${HOTSPOT_IPV4_CIDR}" \
  ipv4.gateway "${HOTSPOT_GATEWAY}" \
  ipv6.method disabled \
  connection.autoconnect yes \
  connection.autoconnect-priority 999 || warn "Could not fully set hotspot parameters."

# 6) Show summary
nmcli -t -f NAME,UUID,DEVICE,TYPE,STATE connection show --active || true
log "Access Point setup completed: SSID='${HOTSPOT_SSID}', IP ${HOTSPOT_GATEWAY} (NAT)."


IP="$(hostname -I | awk '{print $1}')"
echo
echo
echo
log "DONE! Check status & open app in browser:"
echo "→ Service logs:  journalctl -u ${APP_NAME}.service -f"
echo "→ LAN URL:       http://${IP}:${SERVICE_PORT}"
echo "→ Start Access Point manually: sudo nmcli connection up ${HOTSPOT_CON_NAME}"
echo
warn "Note: Group changes (video/gpio) may require reboot."
echo
echo
echo