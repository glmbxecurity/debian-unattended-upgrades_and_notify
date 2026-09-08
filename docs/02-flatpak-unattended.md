# Fase 2: Actualizaciones Automáticas de Flatpak

A diferencia de Snap, que incluye un demonio con actualización automática obligatoria, **Flatpak** no dispone de un proceso desatendido nativo a nivel de CLI a menos que un entorno gráfico (como GNOME Software) lo gestione en segundo plano.

Para garantizar actualizaciones fiables, silenciosas y desatendidas tanto en servidores como en estaciones de trabajo, la solución óptima es un **servicio y temporizador de systemd**.

---

## 1. Consideraciones de permisos (Root vs Usuario)

Las aplicaciones Flatpak pueden instalarse a nivel de usuario (`--user`) o a nivel de sistema (`--system`, la opción por omisión).
* Si un script intenta actualizar paquetes del sistema desde una sesión de usuario sin permisos interactivos, fallará con errores como:
  `Flatpak system operation Deploy not allowed for user`.
* Al ejecutar el servicio como **servicio del sistema en systemd** (que corre como `root`), tiene permisos completos para actualizar sin fricciones runtimes críticos (drivers Nvidia, códecs VAAPI, Mesa, etc.) y las aplicaciones de todos los usuarios.

---

## 2. Creación del Servicio Systemd

Crea el archivo `/etc/systemd/system/flatpak-upgrade.service`:

```ini
[Unit]
Description=Actualizar Flatpaks automaticamente
After=network-online.target
Wants=network-online.target
OnFailure=notify-failure@%n.service

[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak update -y --noninteractive
ExecStartPost=/usr/local/bin/notify-success.sh %n
```

### Explicación de las directivas:
* `Type=oneshot`: El servicio ejecuta el comando y se detiene una vez finalizado.
* `ExecStart`: Lanza la actualización automática con `-y` (asumir sí) y `--noninteractive` (no esperar prompts).
* `OnFailure`: Si la actualización devuelve un código de error, dispara el servicio de notificación de fallo.
* `ExecStartPost`: Si la actualización finaliza con éxito (código 0), ejecuta el script de notificación de éxito.

---

## 3. Creación del Temporizador (Timer)

Crea el archivo `/etc/systemd/system/flatpak-upgrade.timer`:

```ini
[Unit]
Description=Timer diario para actualizar Flatpaks

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
```

### Explicación de las directivas:
* `OnCalendar=daily`: Se ejecuta todos los días a medianoche (00:00:00).
* `Persistent=true`: Si el equipo estaba apagado en el momento de la ejecución programada, se lanzará inmediatamente al volver a encenderlo.
* `RandomizedDelaySec=1h`: Añade un retardo aleatorio de hasta 1 hora para evitar saturar el ancho de banda y no sobrecargar los servidores de Flathub.

---

## 4. Activación del Temporizador

Aplica los cambios en el demonio de systemd y activa el temporizador:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now flatpak-upgrade.timer
```

---

## 5. Verificación y Diagnóstico

### Comprobar la programación
```bash
systemctl list-timers flatpak-upgrade.timer
```

### Ejecutar una prueba inmediata
```bash
sudo systemctl start flatpak-upgrade.service
```

### Ver logs de ejecución
```bash
journalctl -u flatpak-upgrade.service -e
```
