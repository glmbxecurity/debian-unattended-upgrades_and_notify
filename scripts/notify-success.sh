#!/bin/bash
# ==============================================================================
# notify-success.sh
# Se ejecuta automáticamente mediante systemd ExecStartPost= tras completar un servicio.
# Envía una notificación a la sesión gráfica informando del estado de la actualización.
# ==============================================================================

UNIT="${1:-servicio-desconocido}"
USER_ID="${SUDO_UID:-1000}"
USER_NAME="$(id -un "$USER_ID" 2>/dev/null || echo "eddy")"

# Si no hay sesión gráfica abierta para este usuario, salir silenciosamente
if [ ! -e "/run/user/${USER_ID}/bus" ]; then
    exit 0
fi

# ==============================================================================
# Configuración:
# NOTIFY_ALWAYS=false -> Solo notifica cuando REALMENTE se instalaron actualizaciones
# NOTIFY_ALWAYS=true  -> Notifica siempre, incluso si no había paquetes pendientes
# ==============================================================================
NOTIFY_ALWAYS=false

LOG_LINES=$(journalctl -u "$UNIT" -n 35 --no-pager -o cat 2>/dev/null)
DID_UPDATE=false
DETAILS=""

case "$UNIT" in
    *flatpak*)
        if echo "$LOG_LINES" | grep -Ei "Instalando|Actualizando|Installing|Updating" | grep -v "appstream" > /dev/null; then
            DID_UPDATE=true
            DETAILS="Flatpak ha actualizado aplicaciones y componentes con éxito."
        else
            DETAILS="Flatpak: Todo el software está al día."
        fi
        ;;
    *deb-get*)
        if echo "$LOG_LINES" | grep -Ei "Desempaquetando|Unpacking|was updated|Configurando|Setting up" > /dev/null; then
            DID_UPDATE=true
            DETAILS="deb-get ha instalado nuevas versiones de tus aplicaciones con éxito."
        else
            DETAILS="deb-get: Todas las aplicaciones compatibles están al día."
        fi
        ;;
    *apt*)
        APT_LOG="/var/log/unattended-upgrades/unattended-upgrades.log"
        if [ -f "$APT_LOG" ] && grep -Ei "All upgrades installed|Instalados|Upgrade:" "$APT_LOG" 2>/dev/null | tail -n 5 | grep -qv "No packages"; then
            DID_UPDATE=true
            DETAILS="APT: Se han aplicado actualizaciones y parches de Debian con éxito."
        else
            DETAILS="APT: El sistema Debian está al día."
        fi
        ;;
    *)
        DID_UPDATE=true
        DETAILS="El servicio ${UNIT} se ha completado con éxito."
        ;;
esac

# Enviar la notificación solo si hubo novedades o si está configurado en modo siempre
if [ "$DID_UPDATE" = true ] || [ "$NOTIFY_ALWAYS" = true ]; then
    sudo -u "$USER_NAME" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus" \
        notify-send -u normal -t 6000 -i software-update-available \
        "✅ Actualización completada" \
        "$DETAILS"
fi
