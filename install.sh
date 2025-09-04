#!/usr/bin/env bash
set -euo pipefail
trap 'err "Fehler in Zeile $LINENO: Befehl \"${BASH_COMMAND}\""; exit 1' ERR

### ──────────────── Configuration ────────────────

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
BIND_IPV6="false"


### ──────────────── Helper Functions ────────────────

# Displays a message in colored font
log() { echo -e "\033[1;32m[+] $*\033[0m"; }
warn(){ echo -e "\033[1;33m[!] $*\033[0m"; }
err() { echo -e "\033[1;31m[✗] $*\033[0m" >&2; }

# Ensures that the script is run with root privileges.
require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Please run script with sudo: sudo bash $0"
    exit 1
  fi
}

# Checks whether a command is available in the current PATH.
cmd_exists() { command -v "$1" &>/dev/null; }


### ──────────────── Start ────────────────

require_root

log "Update system packages …"
apt-get update -y

log "Install required packages (Python, Picamera2, GPIO, Blinka/libgpiod) …"
apt-get install -y --no-install-recommends \
  python3 python3-venv python3-pip \
  python3-picamera2 python3-rpi.gpio \
  libgpiod2 python3-libgpiod ca-certificates git curl

if [[ "${INSTALL_DEBUG_TOOLS}" == "true" ]]; then
  log "Install optional debug tools (libcamera-apps, i2c-tools) …"
  apt-get install -y --no-install-recommends libcamera-apps i2c-tools
fi

log "Activate camera & interfaces in raspi-config ..."
if cmd_exists raspi-config; then
  raspi-config nonint do_camera 0 || true
  raspi-config nonint do_i2c 0 || true
  raspi-config nonint do_spi 0 || true
else
  warn "raspi-config not found – please activate camera/I2C/SPI manually if necessary."
fi

log "Add user '${APP_USER}' to groups 'video' and 'gpio' (for camera/GPIO access) …"
usermod -aG video,gpio "${APP_USER}" || true

log "Set up repository under ${INSTALL_DIR} …"
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  CURRENT_BRANCH="$(git -C "${INSTALL_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  git -C "${INSTALL_DIR}" fetch --all --prune
  git -C "${INSTALL_DIR}" reset --hard "origin/${CURRENT_BRANCH}" || git -C "${INSTALL_DIR}" pull --rebase || true
else
  rm -rf "${INSTALL_DIR}"
  git clone "${REPO_URL}" "${INSTALL_DIR}"
fi

log "Set file permissions ..."
chown -R "${APP_USER}:${APP_GROUP}" "${INSTALL_DIR}"

log "Create Python virtual env ..."
if [[ ! -d "${VENV_DIR}" ]]; then
  sudo -u "${APP_USER}" "${PYTHON_BIN}" -m venv --system-site-packages "${VENV_DIR}"
fi

log "Update Pip & Install Python Dependencies …"
# requirements.txt optional – wir installieren minimal benötigte Pakete
if [[ -f "${INSTALL_DIR}/requirements.txt" ]]; then
  sudo -u "${APP_USER}" bash -lc "${VENV_DIR}/bin/pip install --upgrade pip"
  sudo -u "${APP_USER}" bash -lc "${VENV_DIR}/bin/pip install -r '${INSTALL_DIR}/requirements.txt'"
else
  sudo -u "${APP_USER}" bash -lc "${VENV_DIR}/bin/pip install --upgrade pip"
  # Deine konkret benötigten Py-Pakete:
  PKGS=("Flask>=2.3" "Adafruit-Blinka>=8.0" "adafruit-circuitpython-dht>=4.0")
  if [[ "${USE_GUNICORN}" == "true" ]]; then PKGS+=("gunicorn>=21.2"); fi
  sudo -u "${APP_USER}" bash -lc "${VENV_DIR}/bin/pip install ${PKGS[*]}"
fi

log "Create/check .env …"
if [[ ! -f "${ENV_FILE}" ]]; then
  cat > "${ENV_FILE}" <<'EOF'
# ─── App-Umgebung ───────────────────────────────────────────
FLASK_DEBUG=0
HOST=0.0.0.0
PORT=5000

# ─── Hardware-Pins/Settings (kannst du hier überschreiben) ─
# GPIO-Pins für Relais (BCM)
RELAIS1_PIN=23
RELAIS2_PIN=24

# DHT-Pin (Adafruit Blinka-Bezeichner, z. B. D4)
DHT_PIN=D4
EOF
  chown "${APP_USER}:${APP_GROUP}" "${ENV_FILE}"
  chmod 640 "${ENV_FILE}"
  log ".env angelegt unter ${ENV_FILE}"
else
  warn ".env existiert bereits – unverändert gelassen."
fi

# Startkommando bestimmen
if [[ "${USE_GUNICORN}" == "true" ]]; then
  START_CMD="${VENV_DIR}/bin/gunicorn --access-logfile - -w 2 -b 0.0.0.0:${SERVICE_PORT} app:app"
  if [[ "${BIND_IPV6}" == "true" ]]; then
    START_CMD="${START_CMD} -b [::]:${SERVICE_PORT}"
  fi
else
  START_CMD="${VENV_DIR}/bin/python ${INSTALL_DIR}/${ENTRYPOINT}"
fi



systemctl stop "${APP_NAME}.service" 2>/dev/null || true
systemctl disable "${APP_NAME}.service" 2>/dev/null || true
rm -f "/etc/systemd/system/${APP_NAME}.service"
systemctl daemon-reload
fuser -k ${SERVICE_PORT}/tcp 2>/dev/null || true
pkill -f "gunicorn.*:${SERVICE_PORT}" 2>/dev/null || true




log "systemd-Service erstellen …"
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
# Direkt im Web-Unterordner arbeiten, damit Flask Templates/Static sauber findet
WorkingDirectory=${INSTALL_DIR}/webapp
EnvironmentFile=${ENV_FILE}
# Sofortige Logausgabe (ohne Buffering) + Access-Log ist bereits im START_CMD gesetzt
Environment=PYTHONUNBUFFERED=1
# WICHTIG: Gruppen mitschicken, damit Kamera/GPIO ohne Reboot funktionieren
SupplementaryGroups=video gpio
ExecStart=${START_CMD}
Restart=on-failure
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

log "systemd neu laden & Service aktivieren …"
systemctl daemon-reload
systemctl enable "${APP_NAME}.service"

log "Service starten …"
systemctl restart "${APP_NAME}.service" || true

IP="$(hostname -I | awk '{print $1}')"
echo
log "Fertig. Prüfe Service-Status und rufe die App im Browser auf:"
echo "→ Status:  journalctl -u ${APP_NAME}.service -f"
echo "→ URL:     http://${IP}:${SERVICE_PORT}"
echo "Hinweis: Gruppenänderungen (video/gpio) greifen ggf. erst nach Re-Login/Neustart."