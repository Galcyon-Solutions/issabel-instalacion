# issabel-instalacion

Instalar, actualizar y dejar listo un **Issabel 5** con la última versión de todo: Issabel, HTTPS con Let's Encrypt y Call Center Community. Manuales paso a paso y scripts probados. Sin Docker: todo corre directamente en tu servidor Rocky Linux 8.

> Es parte de un conjunto de tres repositorios para aprender Issabel y voz con IA. Los otros: `issabel-voicebot` (Asterisk 20.18 + voicebot con IA) e `issabel-webphone-lite` (teléfono en el navegador).

## Qué hay

| Documento | Para qué |
|---|---|
| [`docs/01-instalar-issabel.md`](docs/01-instalar-issabel.md) | Tres caminos para instalar: ISO oficial, la ISO como repositorio (con script) y el `netinstall` oficial. Qué Asterisk trae cada uno |
| [`docs/02-dominio-y-ssl.md`](docs/02-dominio-y-ssl.md) | Crear el dominio y el certificado HTTPS con el módulo Let's Encrypt que Issabel ya incluye; renovación y el webphone |
| [`docs/03-actualizar-issabel.md`](docs/03-actualizar-issabel.md) | Actualizar el sistema y los paquetes de Issabel con respaldo y verificación |
| [`docs/04-call-center.md`](docs/04-call-center.md) | Instalar y actualizar el Call Center Community V5 a la última versión (5.1.13) |

| Script | Qué hace |
|---|---|
| `scripts/instalar-issabel-iso.sh` | Instala Issabel 5 con Asterisk 20 desde la ISO, sobre un Rocky 8 minimal |
| `scripts/actualizar-issabel.sh` | `dnf update` con respaldo antes y comprobaciones después |
| `scripts/instalar-callcenter.sh` | Call Center Community desde el repositorio oficial |
| `scripts/actualizar-callcenter.sh` | Actualiza el Call Center con su actualizador oficial; `--restore` para volver |
| `scripts/hook-renovar-asterisk-pem.sh` | Mantiene al día el certificado del WebSocket seguro de Asterisk tras cada renovación |

## Orden recomendado

1. `docs/01` Instalar Issabel (camino A, B o C).
2. `docs/02` Dominio y certificado (sin esto el webphone no funciona).
3. **Actualizar Asterisk** (repositorio `issabel-voicebot`) si quieres el voicebot.
4. `docs/03` Actualizar el sistema y los paquetes.
5. `docs/04` Call Center (después de Asterisk: su instalador detecta la versión).

## Reglas que verás repetidas (a propósito)

- **Snapshot del VPS antes de tocar nada.** Es lo único que te salva de verdad.
- **Cero llamadas activas** al actualizar: todos los scripts se niegan a continuar si las hay.
- **Respaldo → cambio → verificación → reversa.** Cada script crea su respaldo en `/root/respaldo-*` y dice cómo volver atrás.
- **Nunca edites `extensions_additional.conf`, `sip_additional.conf` ni `pjsip*_additional.conf`**: IssabelPBX los regenera. Lo tuyo va en los `*_custom.conf`.
- **Instala siempre la última versión desde el repositorio oficial del proyecto**, no lo que ofrezca el gestor de paquetes.

## Qué se probó y qué no

Probado en contenedores Rocky 8 desechables con systemd (sin tocar ningún servidor de producción):

- `instalar-issabel-iso.sh` con la ISO oficial `20261001` real: instala, el primer arranque termina, Asterisk 20.12.0, la web responde 200 y los servicios arrancan.
- El `netinstall` oficial ejecutado entero (con Asterisk 18): Issabel 5 y Asterisk 18.19.0 funcionando.
- `instalar-callcenter.sh`, `actualizar-callcenter.sh` (5.1.1 a 5.1.13) y `actualizar-issabel.sh`.
- `hook-renovar-asterisk-pem.sh` con certificados de prueba.

**No probado:**

- Una **VM o VPS real** (arranque desde la ISO con el instalador gráfico; montaje `loop` de la ISO).
- La **emisión real** de un certificado de Let's Encrypt (hace falta un dominio real).
- El asistente interactivo de contraseñas (`issabel-admin-passwords --init`) con una persona escribiendo; en las pruebas se usó un sustituto no interactivo.

## Licencia

Apache-2.0 (ver `LICENSE`). Autor: Gian Diego Javes, Galcyon Solutions.
