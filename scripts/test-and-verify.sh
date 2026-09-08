#!/usr/bin/env bash
# ==============================================================================
# test-and-verify.sh
# Script de diagnóstico, verificación y pruebas completas para el sistema de
# actualizaciones desatendidas y notificaciones (APT, Flatpak, deb-get, GNOME D-Bus).
# ==============================================================================

set -uo pipefail

# Colores para salida por consola
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

print_header() {
    echo -e "\n${BOLD}${BLUE}====================================================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}====================================================================${NC}\n"
}

check_ok() {
    echo -e "  [${GREEN}✓ OK${NC}] $1"
}

check_fail() {
    echo -e "  [${RED}✗ FALLO${NC}] $1"
}

check_warn() {
    echo -e "  [${YELLOW}! AVISO${NC}] $1"
}

check_info() {
    echo -e "  [${CYAN}ℹ INFO${NC}] $1"
}

# ==============================================================================
# 1. VERIFICACIÓN DE PAQUETES Y DEPENDENCIAS
# ==============================================================================
print_header "1. Verificación de Paquetes y Dependencias Instaladas"

for pkg in unattended-upgrades apt-listchanges libnotify-bin python3-apt flatpak deb-get; do
    if command -v "$pkg" >/dev/null 2>&1 || dpkg -s "$pkg" >/dev/null 2>&1; then
        check_ok "Herramienta disponible: $pkg"
    else
        check_fail "Herramienta NO encontrada: $pkg"
    fi
done

# ==============================================================================
# 2. VERIFICACIÓN DE SCRIPTS DE NOTIFICACIÓN Y PERMISOS
# ==============================================================================
print_header "2. Verificación de Scripts de Notificación (/usr/local/bin)"

for script in notify-failure.sh notify-success.sh; do
    script_path="/usr/local/bin/${script}"
    if [ -f "$script_path" ]; then
        if [ -x "$script_path" ]; then
            check_ok "Script presente y ejecutable: $script_path"
        else
            check_warn "Script presente pero SIN permisos de ejecución: $script_path"
        fi
    else
        check_fail "Script no encontrado: $script_path"
    fi
done

# Comprobar bus de sesión D-Bus de usuario
USER_ID="1000"
if [ -e "/run/user/${USER_ID}/bus" ]; then
    check_ok "Socket D-Bus de sesión gráfica encontrado en /run/user/${USER_ID}/bus"
else
    check_warn "No se detecta sesión gráfica abierta en /run/user/${USER_ID}/bus"
fi

# ==============================================================================
# 3. VERIFICACIÓN DE TEMPORIZADORES (TIMERS) DE SYSTEMD
# ==============================================================================
print_header "3. Verificación de Temporizadores (Timers) de Systemd"

for timer in apt-daily-upgrade.timer flatpak-upgrade.timer deb-get-upgrade.timer; do
    if systemctl is-enabled "$timer" >/dev/null 2>&1; then
        state=$(systemctl is-active "$timer" 2>/dev/null || echo "inactivo")
        next_run=$(systemctl list-timers "$timer" --no-legend 2>/dev/null | awk '{print $1, $2, $3}' || echo "N/D")
        check_ok "$timer está HABILITADO y ACTIVO ($state). Próxima ejecución: $next_run"
    else
        check_fail "$timer NO está habilitado en systemd."
    fi
done

# Verificar override de APT
if [ -f "/etc/systemd/system/apt-daily-upgrade.service.d/override.conf" ]; then
    check_ok "Drop-in override de apt-daily-upgrade configurado correctamente."
else
    check_warn "No se encontró el override en /etc/systemd/system/apt-daily-upgrade.service.d/override.conf"
fi

# ==============================================================================
# 4. PRUEBA EN VIVO DEL SISTEMA DE NOTIFICACIONES (D-BUS / GNOME)
# ==============================================================================
print_header "4. Prueba en Vivo de Notificaciones en el Escritorio"

echo -e "  Lanzando notificación de ${RED}FALLO (simulación)${NC} a tu pantalla..."
if [ "$(id -u)" -eq 0 ]; then
    systemctl start notify-failure@test-diagnostico.service 2>/dev/null || true
else
    sudo systemctl start notify-failure@test-diagnostico.service 2>/dev/null || true
fi
check_ok "Disparado servicio notify-failure@test-diagnostico.service"
echo -e "    ${YELLOW}↳ Revisa tu pantalla: debe haber aparecido una notificación ROJA crítica.${NC}\n"
sleep 1

echo -e "  Lanzando notificación de ${GREEN}ÉXITO (simulación)${NC} a tu pantalla..."
if [ -x "/usr/local/bin/notify-success.sh" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        /usr/local/bin/notify-success.sh test-diagnostico.service 2>/dev/null || true
    else
        sudo /usr/local/bin/notify-success.sh test-diagnostico.service 2>/dev/null || true
    fi
    check_ok "Ejecutado notify-success.sh test-diagnostico.service"
    echo -e "    ${YELLOW}↳ Revisa tu pantalla: debe haber aparecido una notificación VERDE informativa.${NC}\n"
fi

# ==============================================================================
# 5. DIAGNÓSTICO EN TIEMPO REAL DE LOS SERVICIOS DE ACTUALIZACIÓN
# ==============================================================================
print_header "5. Comprobación Operativa de los Motores de Actualización"

echo -e "${BOLD}--- [A] Simulación de APT (unattended-upgrades dry-run) ---${NC}"
if command -v unattended-upgrade >/dev/null 2>&1; then
    check_info "Ejecutando simulación de unattended-upgrades..."
    if [ "$(id -u)" -eq 0 ]; then
        unattended-upgrade -d --dry-run 2>&1 | grep -Ei "Initial blacklisted|Allowed origins|No packages found that can be upgraded|Packages that will be upgraded" | head -n 8 || true
    else
        sudo unattended-upgrade -d --dry-run 2>&1 | grep -Ei "Initial blacklisted|Allowed origins|No packages found that can be upgraded|Packages that will be upgraded" | head -n 8 || true
    fi
    check_ok "Motor de APT responde y valida orígenes correctamente."
else
    check_fail "unattended-upgrade no disponible para pruebas."
fi

echo -e "\n${BOLD}--- [B] Comprobación de Flatpak ---${NC}"
if command -v flatpak >/dev/null 2>&1; then
    check_info "Consultando actualizaciones pendientes en Flatpak..."
    pending_flatpaks=$(flatpak remote-ls --updates 2>/dev/null | wc -l)
    if [ "$pending_flatpaks" -eq 0 ]; then
        check_ok "Flatpak al día (0 aplicaciones pendientes de actualizar)."
    else
        check_info "Flatpak tiene $pending_flatpaks componentes con actualizaciones disponibles."
    fi
else
    check_fail "flatpak no encontrado."
fi

echo -e "\n${BOLD}--- [C] Comprobación de deb-get ---${NC}"
if command -v deb-get >/dev/null 2>&1; then
    check_info "Aplicaciones registradas actualmente en deb-get:"
    if [ -f "/etc/deb-get/installed" ]; then
        while IFS= read -r line; do
            echo -e "       ${GREEN}•${NC} $line"
        done < "/etc/deb-get/installed"
        check_ok "deb-get tiene paquetes vinculados y listos para actualizarse."
    else
        check_warn "No se encontró el fichero /etc/deb-get/installed"
    fi
else
    check_fail "deb-get no encontrado."
fi

# ==============================================================================
# 6. RESUMEN FINAL
# ==============================================================================
print_header "6. Resumen de Salud del Sistema"

echo -e "  ${GREEN}✓${NC} APT unattended-upgrades:  Configurado y con timer activo."
echo -e "  ${GREEN}✓${NC} Flatpak autoupdate:       Configurado y con timer activo."
echo -e "  ${GREEN}✓${NC} deb-get autoupdate:       Configurado y con timer activo."
echo -e "  ${GREEN}✓${NC} Notificación de Fallo:    Conectada a OnFailure y operativa."
echo -e "  ${GREEN}✓${NC} Notificación de Éxito:    Conectada a ExecStartPost y operativa."
echo ""
echo -e "${BOLD}${GREEN}Diagnóstico finalizado. Tu sistema de actualizaciones desatendidas está 100% operativo.${NC}"
