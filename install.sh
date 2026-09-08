#!/usr/bin/env bash
# ==============================================================================
# install.sh
# Script de instalación automática para debian-unattended-upgrades_and_notify
# Configura actualizaciones desatendidas para APT, Flatpak y deb-get con
# notificaciones integradas en el escritorio GNOME (D-Bus).
# ==============================================================================

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Este script debe ejecutarse con privilegios de root (usa sudo ./install.sh)" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== [1/5] Instalando dependencias de paquetes ==="
apt-get update -q
apt-get install -y unattended-upgrades apt-listchanges libnotify-bin python3-apt curl

if ! command -v deb-get >/dev/null 2>&1; then
    echo "  [+] deb-get no detectado. Instalando deb-get oficialmente..."
    curl -sL https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get | bash -s install deb-get
    # Parchear clave de Spotify vigente para Debian 13 si existe la receta
    if [ -f "/etc/deb-get/01-main.d/spotify-client" ]; then
        sed -i 's/pubkey_C85668DF69375001.gpg/pubkey_5384CE82BA52C83A.gpg/' /etc/deb-get/01-main.d/spotify-client 2>/dev/null || true
    fi
fi

echo "=== [2/5] Copiando scripts de notificación a /usr/local/bin ==="
cp "${SCRIPT_DIR}/scripts/notify-failure.sh" /usr/local/bin/notify-failure.sh
cp "${SCRIPT_DIR}/scripts/notify-success.sh" /usr/local/bin/notify-success.sh
chmod +x /usr/local/bin/notify-failure.sh /usr/local/bin/notify-success.sh

echo "=== [3/5] Instalando unidades de Systemd ==="
cp "${SCRIPT_DIR}/systemd/notify-failure@.service" /etc/systemd/system/notify-failure@.service
cp "${SCRIPT_DIR}/systemd/flatpak-upgrade.service" /etc/systemd/system/flatpak-upgrade.service
cp "${SCRIPT_DIR}/systemd/flatpak-upgrade.timer"   /etc/systemd/system/flatpak-upgrade.timer
cp "${SCRIPT_DIR}/systemd/deb-get-upgrade.service" /etc/systemd/system/deb-get-upgrade.service
cp "${SCRIPT_DIR}/systemd/deb-get-upgrade.timer"   /etc/systemd/system/deb-get-upgrade.timer

mkdir -p /etc/systemd/system/apt-daily-upgrade.service.d
cp "${SCRIPT_DIR}/systemd/apt-daily-upgrade.override.conf" \
   /etc/systemd/system/apt-daily-upgrade.service.d/override.conf

echo "=== [4/5] Recargando Systemd y habilitando temporizadores ==="
systemctl daemon-reload

if command -v flatpak >/dev/null 2>&1; then
    systemctl enable --now flatpak-upgrade.timer
    echo "  [+] Timer de Flatpak activado"
fi

if command -v deb-get >/dev/null 2>&1; then
    systemctl enable --now deb-get-upgrade.timer
    echo "  [+] Timer de deb-get activado"
fi

systemctl enable --now apt-daily-upgrade.timer
echo "  [+] Timer de APT activado"

echo "=== [5/5] Probando sistema de notificaciones en escritorio ==="
systemctl start notify-failure@test-install.service || true

echo ""
echo "=========================================================================="
echo " [OK] Instalación completada con éxito."
echo " Revisa si has recibido la notificación de prueba en tu escritorio."
echo " Para auditar tus paquetes .deb manuales: python3 scripts/audit-manual-debs.py"
echo "=========================================================================="
