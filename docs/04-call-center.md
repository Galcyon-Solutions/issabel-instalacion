# Call Center Community: instalar y actualizar siempre la última versión

El Call Center que se usa hoy con Issabel 5 es el de la comunidad: **Call Center Community V5**, mantenido en `https://github.com/ISSABELPBX/callcenter-issabel5`. Estado verificado el 10 de octubre de 2026: **versión 5.1.13** (commit `d225ab1`, 6 de octubre de 2026).

## 1. La trampa que ya costó tiempo: NO uses el RPM

```bash
dnf install issabel-callcenter      # NO
```

El paquete `issabel-callcenter` de los repositorios de Issabel es la **línea 4.0** (la última, `4.0.0-5`). No es el que se quiere en Issabel 5. El proyecto eliminó los RPM de su repositorio y **solo soporta el instalador del repositorio**. Si instalas el RPM, además de tener el módulo viejo, tus pruebas y conclusiones serán sobre el software equivocado (por ejemplo, "esto no es compatible con Asterisk 20", cuando la V5 sí lo es).

Regla general que sirve para todo componente de terceros: **antes de instalar, mira su repositorio oficial** (`VERSION`, `CHANGES.md`, últimos commits) y usa la última versión.

## 2. Qué versión de Asterisk necesita

| Versión del Call Center | Asterisk |
|---|---|
| 5.1.1 (la que traía ese servidor) | Solo Asterisk 18: su instalador **abortaba** con cualquier otra versión |
| **5.1.13 (actual)** | **Asterisk 20 (y 18)**: el instalador detecta tu versión y elige el modo `app_agent_pool`. La 5.1.13 se instaló limpia sobre Asterisk 20.12 y se actualizó desde la 5.1.1 sobre Asterisk 20.18 y 20.12; la detección de Asterisk 18 la hace desde la 5.1.1 |

Ya no hay que parchear el instalador (eso era necesario con la 5.1.1). Por eso el orden recomendado es: **actualiza Asterisk primero y el Call Center después**.

## 3. Instalar (si no lo tienes)

```bash
bash scripts/instalar-callcenter.sh
```

Hace lo que documenta el proyecto, con comprobaciones:

```bash
dnf -y install git
cd /usr/src && git clone https://github.com/ISSABELPBX/callcenter-issabel5.git
cd callcenter-issabel5
bash build/5.0/install-issabel-callcenter.sh -l       # -l: instala lo que acabas de clonar, sin volver a descargar
```

Salida esperada (verificada en un Issabel limpio con Asterisk 20):

```
Info: Detected Asterisk 20. Using app_agent_pool mode.
  - Agent authentication: via ECCP/database
  - Agent interface: Local/XXXX@agents
  - Agent logout: Hangup login channel
...
version instalada: 5.1.13
issabeldialer: active
puerto ECCP 20005 escuchando: 1
```

Cierra sesión y vuelve a entrar en la web: aparece el menú **Call Center**.

### Lo que el instalador te pide configurar tú

Al final imprime un aviso importante sobre las **colas** (PBX > Queues), que él no cambia:

| Ajuste de la cola | Valor | Por qué |
|---|---|---|
| Ring Strategy | **No uses `ringall`**; cualquier estrategia de un solo agente | Con `ringall` el marcador no sabe qué agente tomará la llamada y su ritmo se descontrola |
| Autofill | **Yes** | Sin él, la cola entrega una llamada a la vez y los llamados ya contestados esperan con agentes libres |
| Skip Busy Agents | **Yes + (ringinuse=no)** | Evita ofrecer una llamada nueva a un agente que ya está en una |

## 4. Actualizar (desde una versión anterior)

```bash
bash scripts/actualizar-callcenter.sh --si
```

En orden:

1. **Respaldo** en `/root/respaldo-callcenter-<fecha>`: base `call_center`, el marcador (`/opt/issabel/dialer`), los módulos web, el menú y los permisos (`menu.db`, `acl.db`).
2. `git fetch` y `git merge --ff-only` del clon oficial: trae la última versión sin pisar nada local.
3. **Prueba en seco** del actualizador oficial (`update-issabel-callcenter.sh --dry-run`) y luego la actualización de verdad. Aplica los parches intermedios uno por uno (`5.1.2 ... 5.1.13`).
4. Reinicia `issabeldialer` y verifica: versión, servicio, puerto 20005, agentes y menús.

Verificado: **5.1.1 a 5.1.13 con código de salida 0** sobre Asterisk 20.18 (un Issabel que venía con Asterisk 18 y Call Center 5.1.1, migrado a 20.18) y sobre 20.12. El marcador se reconecta a Asterisk tras reiniciar este.

**Cuidado:** el actualizador oficial **sobrescribe** los archivos del Call Center que actualiza. Si personalizaste las pantallas del módulo, esas modificaciones se pierden (están en el respaldo).

Volver atrás: `bash scripts/actualizar-callcenter.sh --restore /root/respaldo-callcenter-<fecha> --si`.

## 5. Comprobar que funciona

```bash
cat /usr/share/issabel/module_installer/callcenter/VERSION      # 5.1.13
systemctl status issabeldialer
ss -tlnp | grep 20005                                           # puerto ECCP (solo TLS)
```

Dentro de la web:

1. **Call Center > Agents**: crea un agente (por ejemplo el 8000).
2. **PBX > Queues**: crea una cola con los ajustes de arriba.
3. Abre la **Consola de agente** (`Agent Console`), inicia sesión con el agente y una extensión. Para eso la extensión tiene que estar registrada: usa el **webphone** (repositorio `issabel-webphone-lite`), que contesta solo el login del agente.

Desinstalar (sin borrar tus datos): `bash build/5.0/remove-issabel-callcenter.sh` en el clon oficial, y responde **`n`** cuando pregunte por la base de datos.

## 6. Cuando algo no arranca

| Síntoma | Qué mirar |
|---|---|
| El instalador se niega: "/opt/issabel/dialer exists" | Quedó de la línea 4.0. Si no contiene `dialerd`, es solo un log: `rm -rf /opt/issabel/dialer` y repite (el script lo hace) |
| `issabeldialer` activo pero en el registro "no se puede conectar a Asterisk Manager" | Asterisk está reiniciando o la clave AMI cambió. Espera 10 s; si sigue, `grep -A3 'issabelcallcenter\|dialer' /etc/asterisk/manager.conf` |
| No aparece el menú | Cierra sesión de la web y vuelve a entrar (el menú vive en `menu.db` y la sesión lo cachea) |
| El agente no puede iniciar sesión | Su extensión debe estar registrada (`pjsip show endpoints`), y si usas WebRTC, con `transport-wss` |
