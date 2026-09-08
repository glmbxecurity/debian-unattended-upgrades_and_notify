# Guía de Comprobaciones, Auditoría y Troubleshooting

Esta guía proporciona las instrucciones y comandos necesarios para auditar de forma independiente el comportamiento del sistema de actualizaciones desatendidas en **Debian 13**, sin necesidad de confiar ciegamente en scripts automatizados.

Aquí aprenderás a verificar si el sistema realmente se despierta, si comprobó novedades y no aplicó nada por estar al día, si aplicó actualizaciones reales o si ocurrió algún fallo técnico.

---

## 1. ¿Cómo saber si el sistema se está ejecutando según lo programado?

Systemd registra con precisión de milisegundos en el kernel el historial de ejecución de cada temporizador.

Ejecuta:
```bash
systemctl list-timers apt-daily-upgrade.timer flatpak-upgrade.timer deb-get-upgrade.timer
```

### Interpretación de columnas:
* **`LAST`**: Fecha y hora exacta en la que el temporizador se disparó por última vez.
* **`PASSED`**: Tiempo transcurrido desde la última ejecución (ej. *hace 3 horas* o *hace 20 minutos*).
* **`NEXT`**: Momento exacto en el que volverá a ejecutarse.
* **`LEFT`**: Cuenta atrás hasta la próxima ejecución.

> [!TIP]
> Si la columna `LAST` muestra una fecha y hora reciente (del día de hoy o tras encender el PC), tienes la certeza matemática de que el sistema se ha ejecutado.

---

## 2. Comprobar que buscó actualizaciones y NO aplicó nada (Sistema al día)

Cuando el sistema se ejecuta y todas las aplicaciones ya están en su última versión, cada gestor deja constancia en sus registros:

### A. En APT (`unattended-upgrades`)
Consulta el log oficial:
```bash
sudo tail -n 25 /var/log/unattended-upgrades/unattended-upgrades.log
```
* **Salida esperada cuando está al día:**
  ```text
  INFO Starting unattended-upgrades
  INFO Allowed origins are: origin=Debian,codename=trixie-security...
  INFO No packages found that can be upgraded
  ```

### B. En `deb-get`
Consulta el journal del servicio:
```bash
journalctl -u deb-get-upgrade.service -n 25 --no-pager
```
* **Salida esperada cuando está al día:**
  Verás la comprobación individual de cada aplicación registrada:
  ```text
  [+] discord-1.0.156.deb is up to date.
  [+] obsidian_1.13.7_amd64.deb is up to date.
  [+] Heroic-2.22.1-linux-amd64.deb is up to date.
  [+] ente-auth-v4.4.25-x86_64.deb is up to date.
  ```

### C. En Flatpak
Consulta el log del servicio de Flatpak:
```bash
journalctl -u flatpak-upgrade.service -n 15 --no-pager
```
* **Salida esperada cuando está al día:**
  ```text
  Actualizando appstream para el repositorio remoto flathub
  Nothing to do.
  ```

---

## 3. Comprobar que SÍ se aplicó una actualización real con éxito

Cuando una nueva versión se descarga e instala, queda grabada en registros inmutables del sistema operativo:

### A. Historial nativo de Flatpak
Flatpak cuenta con un registro cronológico de instalaciones y actualizaciones:
```bash
flatpak history
```
Muestra una tabla con:
* Fecha y hora exacta.
* Tipo de operación (`update` o `install`).
* Aplicación o runtime afectado.
* Commit anterior y nuevo.

### B. Historial de paquetes del sistema (DPKG)
Cualquier paquete instalado o actualizado en Debian (vía APT o `.deb`) queda registrado en `/var/log/dpkg.log`:
```bash
grep " upgrade " /var/log/dpkg.log
```
* Ejemplo de salida real:
  ```text
  2026-09-08 16:49:52 upgrade libde265-0:amd64 1.0.15-1+deb13u1 1.0.15-1+deb13u2
  2026-09-08 16:54:45 upgrade antigravity:amd64 1.23.2 2.12.2
  ```

### C. Notificación en tu pantalla
El script `/usr/local/bin/notify-success.sh` analiza estas salidas. Si detecta palabras clave como `Desempaquetando`, `Upgraded` o `Instalando`, hace aparecer la **burbuja verde informativa** en tu escritorio GNOME especificando qué software cambió.

---

## 4. Diagnóstico de Problemas (Troubleshooting)

Si algo sale mal durante una actualización desatendida, dispones de herramientas inmediatas para auditarlo:

### 4.1. Ver servicios en estado de fallo
Para saber si algún servicio del sistema se ha roto:
```bash
systemctl --failed
```
* Si todo está correcto: mostrará `0 loaded units listed`.
* Si falló una actualización: aparecerá listado en rojo (ej. `deb-get-upgrade.service failed`).

### 4.2. Inspeccionar el motivo exacto del fallo
Para ver el registro de errores con detalle y colores:
```bash
journalctl -u <nombre-del-servicio> -e
```
*Ejemplos:*
```bash
journalctl -u deb-get-upgrade.service -e
journalctl -u flatpak-upgrade.service -e
journalctl -u apt-daily-upgrade.service -e
```

---

## 5. Casos de Fallo Comunes y Soluciones

### Caso 1: Error de verificación OpenPGP / Clave GPG caducada
* **Síntoma:**
  ```text
  Sub-process /usr/bin/sqv returned an error code (1): Missing key...
  E: El repositorio «...» no está firmado.
  ```
* **Causa:** En Debian 13 (`sqv`), si un proveedor externo rota su clave de firma o deja caducar la anterior (como ocurrió con Spotify), APT bloquea el repositorio por seguridad.
* **Solución:** Descargar la clave renovada del proveedor y actualizar la receta o el archivo `.list` en `/etc/apt/sources.list.d/`.

### Caso 2: Error de red o Timeout del servidor remoto
* **Síntoma:**
  ```text
  504 Gateway Time-out
  Falló la conexión con codeberg.org / github.com
  ```
* **Causa:** El servidor de descargas del desarrollador está temporalmente caído o saturado.
* **Comportamiento:** Systemd marcará el servicio como fallido, lanzará la **notificación roja** en tu escritorio y lo volverá a intentar automáticamente en el siguiente ciclo diario. No requiere intervención a menos que persista durante varios días.

### Caso 3: Bloqueo de base de datos (`Could not get lock /var/lib/dpkg/lock-frontend`)
* **Síntoma:**
  ```text
  E: No se pudo bloquear /var/lib/dpkg/lock-frontend
  ```
* **Causa:** Dos procesos intentaron usar APT o DPKG a la vez (por ejemplo, si estabas instalando algo por consola mientras saltaba el timer).
* **Solución:**
  1. Comprobar qué proceso tiene el bloqueo:
     ```bash
     sudo lsof /var/lib/dpkg/lock-frontend
     ```
  2. Si no hay ningún proceso activo, el bloqueo se libera automáticamente. Gracias a la bandera `--dg-only`, `deb-get` minimiza el tiempo de uso del bloqueo de APT.

### Caso 4: No se muestran notificaciones en el escritorio
* **Síntoma:** El servicio se ejecuta pero no aparece ninguna burbuja en pantalla.
* **Causa:** La variable de sesión D-Bus no está apuntando al socket del usuario o no hay sesión gráfica abierta.
* **Solución:**
  Verificar que el socket existe:
  ```bash
  ls -l /run/user/1000/bus
  ```
  Probar el envío manual:
  ```bash
  sudo -u eddy DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" notify-send "Prueba" "Mensaje de prueba"
  ```

---

## 6. Tabla Resumen de Comandos de Inspección

| Qué necesitas saber | Comando |
| :--- | :--- |
| **¿Cuándo fue la última y cuándo es la próxima?** | `systemctl list-timers *upgrade*` |
| **¿Hay algún servicio caído en el sistema?** | `systemctl --failed` |
| **¿Qué ha pasado en el último intento de deb-get?** | `journalctl -u deb-get-upgrade.service -n 30` |
| **¿Qué ha pasado en el último intento de Flatpak?** | `journalctl -u flatpak-upgrade.service -n 30` |
| **¿Qué ha pasado en el último intento de APT?** | `sudo tail -n 30 /var/log/unattended-upgrades/unattended-upgrades.log` |
| **Historial de lo que realmente se ha actualizado** | `flatpak history` y `grep " upgrade " /var/log/dpkg.log` |
| **Lanzar la suite completa de diagnóstico** | `sudo ./scripts/test-and-verify.sh` |
