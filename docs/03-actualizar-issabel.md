# Actualizar Issabel (sistema y paquetes)

Un Issabel recién instalado desde una ISO nace desactualizado: un servidor real, por ejemplo, tenía **662 paquetes pendientes** (Rocky 8.8 que debía llegar a 8.10, un kernel nuevo, `httpd`, `mariadb`, y `issabel-framework`, `issabel-firstboot` y otros paquetes de Issabel con versión nueva). Esto es lo que se hace, en qué orden y qué cuidar.

## 1. El orden correcto (importa)

1. **Instalar Issabel y ponerle dominio y HTTPS** (documentos 01 y 02).
2. **Actualizar Asterisk** si quieres `chan_websocket` (manual `manual-actualizar-asterisk` del repositorio `issabel-voicebot`).
3. **Actualizar el sistema y los paquetes de Issabel** (este documento). Se comprobó que `dnf update` después de poner Asterisk 20.18 **no lo baja de versión**.
4. **Instalar o actualizar el Call Center** (documento 04). Va después de Asterisk porque su instalador detecta la versión de Asterisk para decidir cómo trabaja.
5. Probar.

Cada paso deja una copia de seguridad propia en `/root/respaldo-*`.

## 2. Qué se actualiza y qué no

| Componente | ¿Lo toca `dnf update`? |
|---|---|
| Rocky Linux 8.x (kernel, `httpd`, `mariadb`, PHP, librerías) | Sí, hasta la 8.10 (la última de la serie 8) |
| Paquetes de Issabel (`issabel-*`, `issabelPBX`) | Sí, desde los repositorios de Issabel |
| **Asterisk de Issabel** (`asterisk18`, `asterisk20`) | Solo si el repositorio tiene una versión más nueva de ese mismo paquete |
| **El Asterisk 20.18 que construiste tú** (`asterisk20-20.18.0`) | **No lo baja**: su número de versión es mayor que el del repositorio. Se comprobó: tras `dnf update` sigue `20.18.0` |
| Call Center Community | No (se instala desde git; no es un RPM) |
| Rocky 8 a Rocky 9 | **Nunca**: Issabel 5 no soporta Rocky 9 |

## 3. Con el script

```bash
bash scripts/actualizar-issabel.sh --si
```

En orden:

1. Aborta si hay **llamadas activas** o menos de 3 GB libres.
2. **Respaldo** en `/root/respaldo-actualizacion-<fecha>`: lista de paquetes, `/etc/asterisk`, `/etc/httpd/conf.d`, `/etc/issabel.conf`, `/etc/amportal.conf`, las bases SQLite de menús y permisos (`/var/www/db`) y los volcados de `asterisk`, `asteriskcdrdb` y `call_center`.
3. Lista los paquetes pendientes y cuántos son de Issabel o Asterisk.
4. `dnf -y update`.
5. Verifica que MariaDB, Apache y Asterisk sigan activos, que la web responda `200`, la versión de Asterisk y si hace falta reiniciar.

## 4. Si se actualizó el kernel: reinicia

```bash
uname -r ; rpm -q kernel | tail -1     # si no coinciden, hay kernel nuevo sin usar
reboot
```

Reinicia **en una ventana sin llamadas** y con acceso a la consola del VPS. Después del reinicio:

```bash
systemctl is-active mariadb httpd asterisk issabeldialer
asterisk -rx 'core show version'
asterisk -rx 'pjsip show endpoints' | tail -3      # o:  sip show peers
```

## 5. Si algo sale mal

- **Lo que de verdad te salva es el snapshot del VPS** que hiciste antes de empezar.
- Un paquete puntual: `dnf history` muestra la transacción; `dnf history undo <ID>` la revierte si las versiones anteriores siguen en los repositorios.
- La configuración: `tar -C / -xpf /root/respaldo-actualizacion-<fecha>/config.tar` y `systemctl restart asterisk httpd`.
- Las bases de datos: `mysql asterisk < /root/respaldo-actualizacion-<fecha>/asterisk.sql` (con la clave de root de MariaDB).

## 6. Dos avisos

- **No actives actualizaciones automáticas** (`dnf-automatic`) en una central que atiende llamadas: un reinicio de Asterisk o de Apache a media tarde cuesta llamadas.
- **Si `dnf` se queda quieto** (verificado en un servidor real: 530 de 662 paquetes descargados y una conexión colgada de un espejo, sin tráfico durante una hora), el script ya usa `--setopt=timeout=30 --setopt=minrate=5000 --setopt=retries=10`: dnf corta la descarga lenta y la reintenta. Si aun así se detiene, `Ctrl+C`, y repite el script: reanuda con lo ya descargado. Cuando se actualiza el kernel, la instalación tarda varios minutos más porque recompila los módulos de `xtables-addons` (DKMS) para el kernel nuevo: es normal.
- Los **repositorios de Issabel** (`mirror.issabel.org`) a veces responden lento o sin un paquete. Si `dnf` se queda esperando, repite; no cambies los archivos `.repo` por una URL de alguien más.
