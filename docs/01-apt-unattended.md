# Fase 1: Actualizaciones Desatendidas de APT

Esta guía detalla la configuración de actualizaciones automáticas para paquetes nativos gestionados por APT en **Debian 13 (Trixie)** utilizando la herramienta oficial `unattended-upgrades`.

---

## 1. Instalación de paquetes necesarios

Instalamos el motor de actualizaciones desatendidas y la utilidad de registro de cambios:

```bash
sudo apt update
sudo apt install unattended-upgrades apt-listchanges
```

---

## 2. Activación del servicio

Para generar la configuración base que indica a APT que descargue e instale paquetes de forma periódica:

```bash
sudo dpkg-reconfigure -plow unattended-upgrades
```

Selecciona **Sí** en la pantalla interactiva. Esto creará o actualizará el archivo `/etc/apt/apt.conf.d/20auto-upgrades` con las siguientes directivas:

```apt
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```
* `1` indica que la comprobación e instalación se ejecutarán con una frecuencia diaria.

---

## 3. Configuración avanzada (`50unattended-upgrades`)

El archivo principal de directivas se encuentra en `/etc/apt/apt.conf.d/50unattended-upgrades`.

Edítalo con tu editor preferido:
```bash
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

### 3.1. Orígenes a actualizar (`Origins-Pattern`)
Por defecto en Debian, solo se actualizan los parches procedentes del repositorio de seguridad. Si deseas que se actualice todo el software del sistema (incluidos los repositorios estables o añadidos):

```apt
Unattended-Upgrade::Origins-Pattern {
        // Parches de seguridad (recomendado siempre activo)
        "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
        
        // Paquetes estándar de Debian
        "origin=Debian,codename=${distro_codename}";
        
        // Repositorios de terceros en /etc/apt/sources.list.d/ (descomentar si aplica)
        //"origin=Google LLC";
        //"origin=HashiCorp";
        //"origin=Tailscale";
};
```

### 3.2. Limpieza de dependencias huérfanas
Para evitar que se acumulen librerías y kernels antiguos que ya no se usan:

```apt
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
```

### 3.3. Control de reinicios automáticos
Si se actualiza un componente crítico (como el kernel o glibc), puedes decidir si el equipo debe reiniciarse solo o esperar a que lo hagas tú:

```apt
// No reiniciar automáticamente:
Unattended-Upgrade::Automatic-Reboot "false";

// O si prefieres reinicio automático de madrugada:
// Unattended-Upgrade::Automatic-Reboot "true";
// Unattended-Upgrade::Automatic-Reboot-Time "04:00";
```

---

## 4. Temporizadores de Systemd

APT utiliza dos temporizadores en Debian para orquestar este proceso:
1. `apt-daily.timer`: Se encarga de descargar la lista de paquetes (`apt update`) y los ficheros `.deb`.
2. `apt-daily-upgrade.timer`: Ejecuta la instalación real de los paquetes descargados (`unattended-upgrade`).

Verifica su estado:
```bash
systemctl status apt-daily-upgrade.timer
```

Para consultar cuándo está programada la próxima ejecución:
```bash
systemctl list-timers apt-daily-upgrade.timer
```

---

## 5. Pruebas y Diagnóstico

### Simulación (Dry-Run)
Puedes simular una ejecución para verificar que las reglas y orígenes están bien definidos sin modificar el sistema:
```bash
sudo unattended-upgrade -d --dry-run
```

### Revisión de Logs
Las acciones realizadas quedan registradas en:
* Log de actualizaciones: `/var/log/unattended-upgrades/unattended-upgrades.log`
* Log de terminal/dpkg: `/var/log/unattended-upgrades/unattended-upgrades-dpkg.log`
