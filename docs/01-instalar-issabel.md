# Instalar la última versión de Issabel 5 en un VPS

Tres caminos para llegar a un Issabel 5 funcionando. Los tres terminan en lo mismo (web en `https://IP/`, Asterisk, MariaDB, IssabelPBX), pero **no instalan la misma versión de Asterisk**. Elige según lo que te permita tu proveedor.

## 1. Qué versión instala cada camino

| Camino | Qué es | Asterisk | Cuándo usarlo |
|---|---|---|---|
| **A. ISO oficial** (instalador gráfico) | `issabel5-USB-DVD-x86_64-20261001.iso`, la más reciente | **20.12.0** (o 18.23.1 si eliges el entorno "con Asterisk 18") | Tu proveedor deja montar una ISO propia. **El camino recomendado** |
| **B. ISO como repositorio, con script** | La misma ISO, pero sobre un Rocky Linux 8 que ya tienes en el VPS | **20.12.0** | El proveedor solo ofrece imágenes de Rocky 8 (no ISO propia) |
| **C. `netinstall` oficial** | Script que instala por internet desde los repositorios de Issabel | **16.30.1 o 18.19.0** (el menú solo ofrece 16 y 18) | No puedes ni montar ISO ni bajar 3,7 GB; o quieres el método "de siempre" |

Verificado el 10 de octubre de 2026: el repositorio en línea de Issabel **no tiene paquetes `asterisk20`**; solo la ISO los trae. Por eso el `netinstall` nunca te dará Asterisk 20 por sí mismo. Si empiezas por ahí, pasas a Asterisk 20.18 con el manual `manual-actualizar-asterisk` del repositorio `issabel-voicebot` (migración 18 a 20, probada).

Las tres cosas que nunca cambian:

- **Rocky Linux 8.x. Issabel 5 no funciona en Rocky 9** (ni en Debian). Si tu VPS trae Rocky 9, reinstálalo con Rocky 8.
- **2 vCPU, 4 GB de RAM, 40 GB de disco** es lo cómodo (mínimo oficial: 1 GB de RAM, pero la web va lenta y Asterisk se arrastra).
- **IP pública fija y un nombre de equipo** (FQDN). Para el certificado HTTPS (documento 02) necesitarás además un dominio.

## 2. Antes de empezar (los tres caminos)

1. **Snapshot del VPS** si tu proveedor lo ofrece. Es la red de seguridad de verdad.
2. Acceso a la **consola del VPS** (KVM/VNC del panel): si te equivocas con la red o el firewall, por SSH ya no entras.
3. Apunta tres contraseñas distintas: `root` del sistema operativo, `root` de MariaDB y `admin` de la web. Genera claves fuertes: `openssl rand -base64 18`. Lo correcto es guardarlas en un gestor de contraseñas, no en un papel pegado al monitor.

## 3. Camino A: ISO oficial en el VPS

1. Descarga la ISO desde SourceForge, proyecto **issabelpbx**, carpeta **Issabel 5**: `issabel5-USB-DVD-x86_64-20261001.iso` (3,68 GB). Comprueba el hash:

   ```bash
   sha256sum issabel5-USB-DVD-x86_64-20261001.iso
   # c63b7512d3ba05af645e144c58bf00c87353ddf2b3318e2fda8c262c057c07f9
   ```
2. Móntala en el VPS desde el panel de tu proveedor (la opción se llama "ISO", "Mount ISO", "CD virtual" o similar) y arranca desde ella.
3. En el instalador:
   - **Red y nombre del equipo**: IP fija y un nombre completo, por ejemplo `pbx.tu-dominio.com`.
   - **Entorno de software**: "Issabel with Asterisk 20".
   - **DESTILDA el complemento "Issabel Network"** (módulos licenciados, unos 8 USD al mes). No hace falta para nada de lo que sigue.
   - Crea la clave de `root`.
4. Al terminar y reiniciar, el **primer arranque** (`issabel-firstboot`) te pide en la consola: la clave de `root` de MariaDB y la clave del usuario `admin` de la web. Son distintas a la de `root` del sistema.
5. Quita la ISO del panel del proveedor para que no vuelva a arrancar desde ella.

## 4. Camino B: la ISO como repositorio, con script

Para un VPS con Rocky 8 ya instalado. En vez de arrancar el instalador gráfico, el script monta la ISO como **repositorio local** e instala los mismos grupos de paquetes que instala su kickstart. Es lo que se verificó con la ISO real y un Rocky 8 limpio: todos los paquetes se resuelven, el primer arranque se completa y queda Asterisk 20.12.0, la web contesta `200` y los servicios arrancan.

```bash
# En el VPS, como root, con la ISO ya descargada (o con --descargar para que el script la baje y la verifique)
bash scripts/instalar-issabel-iso.sh --iso /root/issabel5-USB-DVD-x86_64-20261001.iso
reboot
```

Qué hace, en orden:

1. Comprueba que sea Rocky 8, que no haya Issabel instalado y que haya disco y memoria.
2. Verifica el SHA-256 y **monta la ISO** (`mount -o loop,ro`) como repositorio `iso-issabel`.
3. `dnf group install "Issabel with Asterisk 20"` + la lista de bloqueo comunitaria (RBL). **No instala los módulos licenciados**; si los quieres, `--con-licenciados`.
4. Aplica los pasos de `%post` del kickstart: carpetas de Asterisk, permisos, SELinux deshabilitado, **`firewalld` deshabilitado** (igual que el netinstall) y `phpx-loader-select` (sin esto la página *Usuarios* puede fallar con "PHPX Loader is required").
5. Arranca MariaDB y Asterisk y lanza el asistente de contraseñas (`issabel-admin-passwords --init`): te pide las dos claves de la sección anterior.

Si dnf se queja de `libcurl-minimal` o `coreutils-single`, el script **reintenta solo** con `--allowerasing`: algunas imágenes de VPS traen esas versiones mínimas, que chocan con las completas de la ISO.

> **Por qué se deshabilita `firewalld`.** El grupo de paquetes de Issabel lo instala y lo deja activo con la zona `public`, que solo deja pasar SSH: la web daría *timeout* desde fuera aunque el firewall de tu proveedor esté abierto. El `netinstall` oficial lo deshabilita y deja el cortafuegos al módulo propio de Issabel (*Security > Firewall*); el script hace lo mismo para que los dos caminos den el mismo resultado.

> **No instales paquetes sueltos antes del grupo.** En un Rocky recién creado, ejecuta primero este script y deja para después el idioma y las herramientas extra. Un `dnf install` previo desde los repositorios en línea puede subir `glibc` por encima de la versión que trae la ISO y el grupo falla con `cannot install both glibc-2.28-251.el8_10.40 from iso-issabel and ...el8_10.43 from @System`. `--allowerasing` no lo resuelve (sería un *downgrade*). Un `dnf upgrade` completo antes sí funcionó en la prueba.

**Conserva el archivo ISO.** Montada de nuevo como repositorio te permite volver a la versión original de Asterisk (`dnf downgrade`) si una actualización sale mal.

## 5. Camino C: el `netinstall` oficial

Es el método "por script" que publica el propio proyecto, pensado para convertir un Rocky 8 minimal en Issabel con un solo comando. **No lo ejecutes a ciegas**: el lanzador oficial es `curl http://repo.issabel.org/issabel5-netinstall.sh | bash`, y descarga un script que luego ejecuta como root sin que lo hayas visto. Hazlo en tres pasos:

```bash
dnf -y install wget dialog
wget -O netinstall.sh "https://sourceforge.net/projects/issabelpbx/files/Issabel%205/issabel5-netinstall.sh/download"
sha256sum netinstall.sh        # el script que se probó para este manual: b2d68b1ee478485e303557f11a8b811fbc8b2dd74f5563be48cb18d4137d23e7
less netinstall.sh             # léelo: son unas 500 líneas
bash netinstall.sh
```

El archivo es el que publica el proyecto en SourceForge (carpeta *Issabel 5*, `issabel5-netinstall.sh`, actualizado el 1 de octubre de 2026, el mismo día que la ISO 20261001). Si el hash es otro, Issabel publicó una versión nueva del script: léela antes de ejecutarla.

El asistente (con `dialog`, pantalla azul) te pregunta tres cosas:

1. **Idioma** de la web.
2. **Versión de Asterisk**: `16` o `18`. Elige **18**. (La 20 no está en el menú porque no está en el repositorio.)
3. **Paquetes adicionales**: viene marcado "Issabel Network Licensed modules". **Desmárcalo.** Deja marcada la lista de bloqueo comunitaria (RBL) y no marques `wanpipe` si no tienes tarjetas Sangoma.

Lo que hace por debajo (lo que se leyó en el script y se verificó al ejecutarlo):

- Escribe `Issabel.repo` e `Issabel5.repo` (con `gpgcheck=0` en el repositorio de la 4) y activa **Remi**, **PHP 7.4**, **powertools** y **devel**.
- Actualiza **todo el sistema** (`yum update`) e instala las dos listas de paquetes (Apache, MariaDB, PHP, Asterisk, `issabel`, `issabel-pbx`, `RoundCubeMail`, `fop2`...).
- **Desactiva SELinux** y **firewalld**, y abre el 443. Issabel usa su propio cortafuegos (módulo Security > Firewall).
- Pone una contraseña temporal a MariaDB y la quita; deja el primer arranque para el asistente de contraseñas.
- **Reinicia el servidor** al terminar. Avisa antes de lanzarlo a quien más use ese VPS.

Resultado verificado (Rocky 8 limpio, elegido Asterisk 18): `issabel-pbx 5.0.0-4`, `asterisk18 18.19.0`, la web responde `200`, MariaDB, Apache y Asterisk activos, y sin ningún error en `/tmp/netinstall_errors.txt`. Tarda unos 25 minutos.

**Limitaciones que debes conocer:**

- El script **no se actualiza solo**: apunta a `release=4` y `release=5` del espejo de Issabel, y su menú solo conoce las versiones 16 y 18.
- Termina en Asterisk 18 o 16. Para el voicebot necesitas Asterisk 20.16 o más: ver el manual de actualización de Asterisk.
- No crea dominio ni certificado: sigue al documento 02.

## 6. Primer acceso y comprobaciones

Entra a `https://IP-DEL-SERVIDOR/` (el navegador avisará de que el certificado no es de confianza; es el autofirmado de fábrica, lo cambias en el documento 02) con el usuario **admin** y la clave de la web.

```bash
cat /etc/redhat-release                       # Rocky Linux release 8.x
rpm -q issabel-pbx issabel-framework          # versiones de Issabel
asterisk -rx 'core show version'              # 20.12.0, 18.19.0...
systemctl is-active mariadb httpd asterisk    # los tres: active
ss -ltn | grep -E ':(22|80|443|5060|5038)\b'  # SSH, web, SIP, AMI
```

## 7. Si algo falla

| Síntoma | Qué mirar |
|---|---|
| `dnf` dice "No match for argument: asterisk20" en el netinstall | Normal: el repositorio en línea no tiene Asterisk 20. Usa el camino A o B, o instala 18 y migra |
| La página *Usuarios* de la web muestra "PHPX Loader ... is required" | `/usr/sbin/phpx-loader-select` y `systemctl restart php-fpm`. El script del camino B ya lo hace |
| `ERR_CONNECTION_CLOSED` tras varios intentos de login fallidos | `fail2ban` te baneó: `fail2ban-client status issabel-gui` y `fail2ban-client set issabel-gui unbanip TU_IP` |
| El primer arranque no aparece por SSH | `issabel-admin-passwords --init` a mano. Necesita `dialog` y un terminal (no funciona sin TTY) |
| No llega nadie a la web desde fuera | El firewall del proveedor (panel del VPS) debe abrir 22, 80, 443 y, para telefonía, 5060 UDP y el rango RTP |
