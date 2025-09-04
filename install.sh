#!/usr/bin/env bash
set -euo pipefail
trap 'echo -e "\033[1;31m[✗] Fehler in Zeile $LINENO: ${BASH_COMMAND}\033[0m"; exit 1' ERR

### ────────── Configuration ──────────
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
INSTALL_DEBUG_TOOLS="true"
BIND_IPV6="false"   # true = zusätzlich auf [::]:PORT binden

### ────────── Helpers ──────────
log()  { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err()  { echo -e "\033[1;31m[✗] $*\033[0m" >&2; }
require_root() { [[ $EUID -eq 0 ]] || { err "Bitte mit sudo ausführen"; exit 1; }; }
cmd_exists() { command -v "$1" &>/dev/null; }

### ────────── Start ──────────
require_root
export DEBIAN_FRONTEND=noninteractive

log "Update system packages …"
apt-get update -y

log "Install required packages (Python, Picamera2, GPIO, Blinka/libgpiod) …"
apt-get install -y --no-install-recommends \
  python3 python3-venv python3-pip \
  python3-dev build-essential \
  python3-picamera2 python3-rpi.gpio \
  libgpiod2 python3-libgpiod ca-certificates git curl

if [[ "${INSTALL_DEBUG_TOOLS}" == "true" ]]; then
  log "Install optional debug tools (libcamera-apps, i2c-tools) …"
  apt-get install -y --no-install-recommends libcamera-apps i2c-tools
fi

log "Activate camera & interfaces …"
if cmd_exists raspi-config; then
  raspi-config nonint do_camera 0 || true
  raspi-config nonint do_i2c 0 || true
  raspi-config nonint do_spi 0 || true
else
  warn "raspi-config not found – ggf. Kamera/I2C/SPI manuell aktivieren."
fi

log "Add user '${APP_USER}' to groups 'video' and 'gpio' …"
usermod -aG video,gpio "${APP_USER}" || true

log "Setup repository in ${INSTALL_DIR} …"
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  CURRENT_BRANCH="$(git -C "${INSTALL_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  git -C "${INSTALL_DIR}" fetch --all --prune
  git -C "${INSTALL_DIR}" reset --hard "origin/${CURRENT_BRANCH}" || git -C "${INSTALL_DIR}" pull --rebase || true
else
  rm -rf "${INSTALL_DIR}"
  git clone "${REPO_URL}" "${INSTALL_DIR}"
fi

log "Fix ownership …"
chown -R "${APP_USER}:${APP_GROUP}" "${INSTALL_DIR}"

log "Create Python venv …"
if [[ ! -d "${VENV_DIR}" ]]; then
  sudo -u "${APP_USER}" "${PYTHON_BIN}" -m venv --system-site-packages "${VENV_DIR}"
fi

log "Install Python dependencies from requirements.txt …"
export PIP_PREFER_BINARY=1
if [[ ! -f "${INSTALL_DIR}/requirements.txt" ]]; then
  err "requirements.txt not found in ${INSTALL_DIR}/requirements.txt"
  exit 1
fi
sudo -u "${APP_USER}" bash -lc "${VENV_DIR}/bin/pip install --upgrade pip"
sudo -u "${APP_USER}" bash -lc "${VENV_DIR}/bin/pip install -r '${INSTALL_DIR}/requirements.txt'"

log "Create/check .env …"
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
  warn ".env already exists – unchanged."
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

log "Create systemd service …"
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

log "Enable & start service …"
systemctl daemon-reload
systemctl enable "${APP_NAME}.service"
systemctl restart "${APP_NAME}.service" || true

# UFW: Port nur öffnen, wenn UFW aktiv ist
if cmd_exists ufw && ufw status | grep -q "Status: active"; then
  log "UFW aktiv – erlaube Port ${SERVICE_PORT}/tcp …"
  ufw allow ${SERVICE_PORT}/tcp || true
fi

IP="$(hostname -I | awk '{print $1}')"
echo
log "Done. Check status & open in browser:"
echo "→ Status:  journalctl -u ${APP_NAME}.service -f"
echo "→ URL:     http://${IP}:${SERVICE_PORT}"
echo "Note: Group changes (video/gpio) may require re-login/reboot."
