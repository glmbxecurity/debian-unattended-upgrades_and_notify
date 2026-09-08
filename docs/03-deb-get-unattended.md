# Fase 3: Gestión y Actualización Desatendida de Paquetes `.deb` con `deb-get`

Muchos programas populares (Discord, Obsidian, Heroic Games Launcher, Ente Auth, OpenRGB, Spotify) se instalan a menudo descargando archivos `.deb` sueltos desde páginas web o GitHub Releases mediante `dpkg -i` o instaladores gráficos.

---

## 1. El Problema: Paquetes `.deb` Huérfanos

Cuando instalas un `.deb` descargado a mano:
1. `dpkg` descomprime y registra el software en `/var/lib/dpkg/status`.
2. **No se crea ningún origen remoto**: APT solo puede actualizar paquetes consultando los servidores definidos en `/etc/apt/sources.list` y `/etc/apt/sources.list.d/`.
3. Al no existir un repositorio remoto asociado, APT considera estos paquetes como locales/huérfanos y **nunca notificará ni instalará versiones nuevas**.
4. En aplicaciones como **Discord**, esto es especialmente problemático porque el cliente bloquea su uso cuando detecta que hay una versión nueva disponible, obligando a descargar el nuevo `.deb` manualmente.

---

## 2. Auditoría: ¿Cómo identificar paquetes manuales?

Para saber exactamente qué paquetes instalados carecen de repositorio asociado, creamos un script en Python (`scripts/audit-manual-debs.py`) que consulta la API de `python-apt`:

```bash
python3 scripts/audit-manual-debs.py
```

En nuestro sistema Debian 13 encontramos:
* **Aplicaciones de escritorio**: `discord`, `obsidian`, `enteauth`, `heroic`, `hydralauncher`, `openrgb`, `antigravity`, `spotify-client`.
* **Software institucional**: `autofirma`, `dnieremotesetup`, `libssl1.1` (dependencia de compatibilidad).
* **Otros**: `cloudflare-warp`, `sunshine`.

---

## 3. La Solución: `deb-get`

[**deb-get**](https://github.com/wimpysworld/deb-get) es una utilidad desarrollada por Martin Wimpress que actúa de forma similar a `apt-get`, pero pensada específicamente para software publicado en GitHub Releases o páginas web sin repositorio oficial de Debian.

### 3.1. Instalación de `deb-get`
```bash
curl -sL https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get | sudo -E bash -s install deb-get
```

### 3.2. Proceso Universal de Adopción (Para cualquier usuario)

> [!NOTE]
> **El motor de actualización es 100% genérico y universal**:  
> El servicio `deb-get-upgrade.service` **no tiene ningún programa predefinido ni escrito en piedra**. Ejecuta `deb-get upgrade --dg-only`, lo cual lee dinámicamente el archivo `/etc/deb-get/installed` de la máquina. Cualquier usuario que configure este repositorio puede gestionar su propia lista personalizada de programas sin modificar los scripts ni los servicios de systemd.

Para adaptar este sistema al software particular de cada persona:

#### Paso 1: Escanear el sistema
Ejecuta el script incluido en este repositorio:
```bash
python3 scripts/audit-manual-debs.py
```
Este script analiza la base de datos de paquetes de la máquina en la que se ejecuta e imprime qué paquetes locales existen y cuáles están soportados por el catálogo de `deb-get` (columna `EN DEB-GET?`).

#### Paso 2: Consultar el catálogo de deb-get
Si quieres ver si un programa específico está soportado:
```bash
deb-get search <nombre-del-programa>
# O listar todos los programas compatibles disponibles (más de 250):
deb-get list
```
*(Ejemplos populares en el catálogo: `1password`, `bitwarden`, `google-chrome-stable`, `code`, `brave-browser`, `dbeaver-ce`, `docker-ce`, `zoom`, `zenith`, etc.)*.

#### Paso 3: Adoptar o instalar tus programas
Para que `deb-get` empiece a rastrear y actualizar tus programas existentes:
```bash
sudo deb-get install <paquete1> <paquete2> <paquete3> ...
```
Al ejecutar este comando:
1. `deb-get` detecta que ya los tienes instalados en el sistema y comprueba si hay versiones más recientes.
2. Descarga e instala la última versión si estabas desactualizado.
3. Los registra en el archivo `/etc/deb-get/installed`.

A partir de ese momento, el temporizador diario `deb-get-upgrade.timer` se encargará de comprobar y aplicar las actualizaciones de **tus** aplicaciones de forma desatendida.

---

### 3.3. Caso de Estudio: Aplicaciones adoptadas en este entorno
En nuestro entorno concreto de Debian 13, las aplicaciones detectadas y adoptadas fueron:

```bash
sudo deb-get install discord obsidian enteauth heroic hydralauncher openrgb antigravity spotify-client
```

* **`discord`**: Se actualizó inmediatamente de la versión `1.0.138` a la `1.0.156` (evitando el bloqueo al iniciar).
* **`openrgb`**: Se actualizó a la versión `1.0rc3.1`.
* **`antigravity`**: Se actualizó a la versión `2.12.2`.
* **`obsidian`, `enteauth`, `heroic`, `hydralauncher`**: Se vincularon exitosamente para actualizaciones futuras.

---

## 4. Resolución de Incidencia Crítica: Clave GPG de Spotify en Debian 13

Al adoptar `spotify-client`, se produjo el siguiente error en APT:

```text
Err:1 https://repository.spotify.com stable InRelease
  Sub-process /usr/bin/sqv returned an error code (1), error message is: Missing key E1096BCBFF6D418796DE78515384CE82BA52C83A, which is needed to verify signature.
W: OpenPGP signature verification failed: https://repository.spotify.com stable InRelease
E: El repositorio «http://repository.spotify.com stable InRelease» no está firmado.
```

### Diagnóstico
1. **Debian 13 (Trixie)** utiliza `sqv` (Sequoia-SQV) para una validación estricta de firmas OpenPGP.
2. La receta original de `deb-get` apuntaba a la clave `pubkey_C85668DF69375001.gpg`, la cual **caducó en febrero de 2026**.
3. Spotify renovó su repositorio firmándolo con su nueva clave oficial: `5384CE82BA52C83A` (huella completa `E1096BCBFF6D418796DE78515384CE82BA52C83A`), disponible en `https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.gpg` (con validez hasta febrero de 2027).

### Solución aplicada
Modificar la receta de `deb-get` para que utilice la clave vigente y reintentar la instalación:

```bash
sudo sed -i 's/pubkey_C85668DF69375001.gpg/pubkey_5384CE82BA52C83A.gpg/' /etc/deb-get/01-main.d/spotify-client
sudo deb-get install spotify-client
```

Tras la corrección, el repositorio se validó y Spotify quedó integrado en APT.

---

## 5. Automatización con Systemd (`deb-get-upgrade`)

Para actualizar desatendidamente estos paquetes sin interacción del usuario, creamos un servicio y un timer.

### 5.1. El Servicio (`/etc/systemd/system/deb-get-upgrade.service`)
```ini
[Unit]
Description=Actualizacion desatendida de paquetes gestionados por deb-get
After=network-online.target
Wants=network-online.target
OnFailure=notify-failure@%n.service

[Service]
Type=oneshot
Environment="DEBIAN_FRONTEND=noninteractive"
ExecStart=/usr/bin/deb-get update --quiet
ExecStart=/usr/bin/deb-get upgrade --dg-only
ExecStartPost=/usr/local/bin/notify-success.sh %n
StandardOutput=journal
StandardError=journal
```

> [!IMPORTANT]
> **Por qué usar `--dg-only`:**
> Por omisión, `deb-get upgrade` ejecuta primero un `apt-get upgrade` general de todo el sistema. Al añadir la bandera `--dg-only`, le indicamos que **solo** actualice los paquetes registrados en `deb-get`, dejando la actualización de los paquetes base de Debian en manos de `unattended-upgrades`. Esto evita ejecuciones redundantes o bloqueos de bloqueo de base de datos (`dpkg lock`).

### 5.2. El Temporizador (`/etc/systemd/system/deb-get-upgrade.timer`)
```ini
[Unit]
Description=Timer diario para actualizaciones de deb-get

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
```

### 5.3. Activación
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now deb-get-upgrade.timer
```
