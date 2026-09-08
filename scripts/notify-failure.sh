#!/bin/bash
# ==============================================================================
# notify-failure.sh
# Se ejecuta automáticamente mediante systemd OnFailure= cuando un servicio falla.
# Envía una notificación crítica de error a la sesión gráfica del usuario.
# ==============================================================================

FAILED_UNIT="${1:-servicio-desconocido}"
LOG_SNIPPET=$(journalctl -u "$FAILED_UNIT" -n 8 --no-pager -o cat 2>/dev/null)

# Detectar usuario de sesión gráfica activa (por defecto UID 1000)
USER_ID="${SUDO_UID:-1000}"
USER_NAME="$(id -un "$USER_ID" 2>/dev/null || echo "eddy")"

# 1. Notificación en el escritorio GNOME / X11 / Wayland
if [ -e "/run/user/${USER_ID}/bus" ]; then
    sudo -u "$USER_NAME" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus" \
        notify-send -u critical -i dialog-error \
        "⚠️ Fallo en Actualización Desatendida" \
        "El servicio ${FAILED_UNIT} ha fallado.\nRevisa el log con: journalctl -u ${FAILED_UNIT} -e"
fi

# 2. (Opcional) Notificación a móvil vía Webhook de Discord
# DISCORD_WEBHOOK="https://discord.com/api/webhooks/TU/WEBHOOK"
# if [ -n "$DISCORD_WEBHOOK" ]; then
#     curl -s -H "Content-Type: application/json" -X POST \
#         -d "{\"content\": \"⚠️ **Error en actualización en tu sistema:** \`${FAILED_UNIT}\`\n\`\`\`\n${LOG_SNIPPET}\n\`\`\`\"}" \
#         "$DISCORD_WEBHOOK" > /dev/null
# fi
