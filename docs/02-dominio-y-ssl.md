# Dominio y certificado HTTPS con el módulo Let's Encrypt de Issabel

Issabel trae de fábrica un certificado **autofirmado**: la web funciona, pero el navegador te avisa en rojo, y lo que es peor, **el webphone y cualquier WebRTC no funcionan sin un certificado válido** (el navegador se niega a abrir el WebSocket seguro). Aquí lo resolvemos con un dominio y un certificado gratuito de Let's Encrypt, usando el módulo que el propio Issabel ya incluye. En los ejemplos el dominio es `pbx.tu-dominio.com`: sustitúyelo por el tuyo.

## 1. Qué necesitas

| Requisito | Por qué |
|---|---|
| Un **dominio** (o subdominio) que apunte a la IP pública de tu VPS | Let's Encrypt comprueba que controlas ese nombre entrando a `http://TU-DOMINIO/` desde internet |
| Los puertos **80 y 443** abiertos, en el firewall del proveedor **y** en el de Issabel | El 80 es para la comprobación, el 443 para usar el certificado |
| Un **correo** real | Let's Encrypt avisa si el certificado está por vencer |
| Acceso a la web **por el nombre de dominio**, no por la IP | El módulo lo exige: sin nombre válido no puede pedir el certificado |

> El certificado de una IP existe (Let's Encrypt los emite desde 2026), pero el módulo de Issabel trabaja con dominios y no con IP. Aquí, dominio.

## 2. Crear el nombre en el DNS

En el panel de tu proveedor de dominio (o de DNS) crea un registro **A**:

| Tipo | Nombre | Valor | TTL |
|---|---|---|---|
| A | `pbx` (para `pbx.tu-dominio.com`) | `IP pública del VPS` | 300 |

Comprueba desde tu computadora, no desde el servidor, que ya resuelve (puede tardar unos minutos):

```bash
dig +short pbx.tu-dominio.com        # debe mostrar la IP de tu VPS
# o, sin dig:  nslookup pbx.tu-dominio.com
```

**Si usas Cloudflare:** pon el registro en **"solo DNS" (nube gris)**, no "proxy" (nube naranja). Con el proxy activo, la comprobación y el audio/WebSocket no llegan a tu servidor.

## 3. Ponerle ese nombre al servidor (recomendado)

El módulo toma el nombre del servidor de `/etc/hostname` para preparar Apache. Si ya tienes el dominio, ponlo de una vez:

```bash
hostnamectl set-hostname pbx.tu-dominio.com
echo "$(hostname -I | awk '{print $1}') pbx.tu-dominio.com" >> /etc/hosts
hostname -f            # debe mostrar el nombre completo
```

(Aunque no lo hagas, al terminar bien el módulo escribe el dominio como nombre del equipo.)

## 4. Los puertos (aquí fallan casi todos)

Let's Encrypt entra a `http://tu-dominio/.well-known/acme-challenge/...` **desde varios países a la vez** y sin una IP fija que puedas permitir. Issabel redirige HTTP a HTTPS, y el validador sigue la redirección: necesita **el 80 y el 443**.

- **Firewall del proveedor** (panel del VPS): abrir TCP 80 y 443.
- **Firewall de Issabel**: trae 80 y 443 aceptados de fábrica, pero **si activaste el bloqueo por país (GeoIP) en *Security > Firewall*, esa regla se evalúa ANTES y rechaza países enteros**. En el servidor real de pruebas esa fue la causa real del primer fallo: `Fetching http://.../.well-known/...: Connection refused`, aunque `ss -ltn` mostraba Apache escuchando.
- Cómo comprobarlo antes de pedir nada: desde **otra** máquina (otro país, o un servicio de comprobación de puertos) `curl -I http://tu-dominio/`. Si desde el propio servidor a su IP pública da `000` y por `127.0.0.1` da `302`, es el firewall.

Para emitir y para renovar hay dos caminos:

1. **Dejar 80 y 443 abiertos a todos** en el firewall de Issabel (los puertos web ya son públicos de por sí). Es lo más simple.
2. **Abrirlos solo durante la validación**, con el script de este repositorio, sin tocar tu configuración permanente (la regla vive en memoria):

```bash
bash scripts/hook-abrir-puertos.sh abrir     # antes de emitir
# ... emitir el certificado ...
bash scripts/hook-abrir-puertos.sh cerrar    # después
```

Para la renovación automática (sección 7) el mismo script se instala como gancho de certbot y hace esto solo.

## 5. Emitir el certificado desde la web

1. Entra a Issabel **por el dominio**: `https://pbx.tu-dominio.com/` (ahora todavía con el aviso de certificado; acéptalo). Si entras por la IP, el módulo te avisa de que uses el nombre.
2. Menú **Security > HTTPS Certificate (Let's Encrypt)**.
3. Campo **Domain**: `pbx.tu-dominio.com`. Se pueden poner varios separados por comas.
4. Campo **Email**: tu correo.
5. **Pulsa Install.** No uses la casilla **Staging Certificate** salvo que dudes del DNS o de los puertos: **el certificado de prueba bloquea al definitivo**. Verificado en un servidor real: si ya existe uno de prueba, al pedir el definitivo certbot dice *"Certificate not yet due for renewal"* y **conserva el de prueba**; y borrarlo con `certbot delete` mientras Apache todavía apunta a sus archivos **deja a Apache sin arrancar**. Si necesitas probar, haz la comprobación del apartado 4 con `curl` desde fuera, que no cuenta en ningún límite.
6. El resultado aparece en pantalla ("Output log"). Al terminar, **recarga la página con el nombre de dominio**: el candado debe estar verde.

Lo que pasa por debajo (el helper `issabel-helper ssl_certbot` del módulo):

```bash
certbot -n -i apache -a webroot -w /var/www/html --agree-tos --email TU_CORREO -d pbx.tu-dominio.com
```

1. Pone `ServerName pbx.tu-dominio.com` en `/etc/httpd/conf.d/ssl.conf`. **Sin esta línea certbot obtiene el certificado pero no puede instalarlo** (`Encountered vhost ambiguity ... Could not install certificate`); el módulo la añade solo, pero si pides el certificado por línea de comandos, hazlo antes: `/usr/bin/issabel-helper ssl_certbot insertservername tu-dominio`.
2. `certbot` comprueba el dominio dejando un archivo en `/var/www/html/.well-known/` y pidiéndolo por el puerto 80 (por eso el 80 tiene que llegar).
3. Instala el certificado en Apache: cambia `SSLCertificateFile` y `SSLCertificateKeyFile` de `ssl.conf` para que apunten a `/etc/letsencrypt/live/pbx.tu-dominio.com/`.
4. **Escribe `/etc/asterisk/keys/asterisk.pem`** (cadena completa + clave) y recarga Asterisk: es el certificado que usa el WebSocket seguro de Asterisk en el puerto **8089**. Gracias a eso el webphone (`wss://`) funciona con el mismo certificado.
5. Guarda tu dominio y correo en `/etc/letsencrypt/values` y pone el dominio como nombre del equipo.

## 6. Comprobar

```bash
certbot certificates                                   # dominio, fecha de vencimiento (90 días)
echo | openssl s_client -connect pbx.tu-dominio.com:443 -servername pbx.tu-dominio.com 2>/dev/null | openssl x509 -noout -issuer -enddate
curl -sI https://pbx.tu-dominio.com/ | head -1      # HTTP/1.1 200 (o 302), sin -k
openssl x509 -in /etc/asterisk/keys/asterisk.pem -noout -subject -enddate    # el mismo dominio y fecha
```

El emisor debe decir `Let's Encrypt`. Si dice "(STAGING)", emitiste el de prueba: repite sin marcar la casilla.

## 7. Renovación (y las dos trampas)

El certificado dura **90 días**. Issabel ya trae `certbot-renew.timer`, que corre dos veces al día y renueva cuando faltan menos de 30 días:

```bash
systemctl list-timers | grep certbot       # debe estar activo
```

**Trampa 1, el certificado de Asterisk.** Esa renovación automática renueva el certificado de **Apache**, pero **no** reescribe `/etc/asterisk/keys/asterisk.pem` (el del WebSocket seguro, puerto 8089), porque eso solo lo hace el botón *Renew* del módulo. A los 90 días la web seguiría bien y el webphone dejaría de conectar.

**Trampa 2, el firewall.** Si usas bloqueo GeoIP, la renovación falla igual que la emisión, y falla en silencio a los 60 días.

Las dos se cierran con ganchos de certbot (se ejecutan en cada renovación):

```bash
install -d /etc/letsencrypt/renewal-hooks/pre /etc/letsencrypt/renewal-hooks/post /etc/letsencrypt/renewal-hooks/deploy
install -m 755 scripts/hook-abrir-puertos.sh        /etc/letsencrypt/renewal-hooks/pre/abrir-puertos.sh
install -m 755 scripts/hook-abrir-puertos.sh        /etc/letsencrypt/renewal-hooks/post/cerrar-puertos.sh
install -m 755 scripts/hook-renovar-asterisk-pem.sh /etc/letsencrypt/renewal-hooks/deploy/asterisk-pem.sh
bash /etc/letsencrypt/renewal-hooks/deploy/asterisk-pem.sh      # prueba: imprime la fecha de vencimiento
certbot renew --dry-run                                         # prueba completa, sin emitir nada
```

Resultado verificado en un servidor real: `Hook 'pre-hook' ran ... 80 y 443 abiertos temporalmente`, `Congratulations, all simulated renewals succeeded`, `Hook 'post-hook' ran ... 80 y 443 como estaban`, y ninguna regla temporal queda después. El gancho de Asterisk usa la misma receta que el módulo (cadena completa + clave, en el orden de `ssl.conf`), deja el archivo en `640 root:asterisk` y recarga el módulo `http` de Asterisk.

## 8. Si algo falla

| Mensaje o síntoma | Causa y arreglo |
|---|---|
| El módulo dice que accedas "via a valid name" | Entraste por la IP. Entra por `https://tu-dominio/` |
| `DNS problem: NXDOMAIN` o `no valid A records` | El registro A no existe todavía o no propagó: `dig +short tu-dominio` desde fuera |
| `Timeout during connect` / `Connection refused` | El 80 o el 443 no llegan: firewall del proveedor, **bloqueo GeoIP de Issabel** (apartado 4) o Cloudflare con proxy naranja. Ojo con el 443: la redirección a HTTPS también cuenta |
| `Certificate not yet due for renewal` y el candado sigue en rojo | Hay un certificado de prueba (Staging) que bloquea al definitivo. No lo borres con `certbot delete` sin antes devolver `SSLCertificateFile` y `SSLCertificateKeyFile` de `ssl.conf` a `/etc/pki/tls/certs/localhost.crt` y `/etc/pki/tls/private/localhost.key`: sin esos archivos Apache no arranca |
| `Could not find a VirtualHost for ...` | El `ServerName` de `ssl.conf` no coincide con el dominio que escribiste. Corrígelo: `grep -n ServerName /etc/httpd/conf.d/ssl.conf` |
| `too many failed authorizations recently` | Superaste el límite. Espera una hora y usa **Staging** para probar |
| Certificado emitido pero el navegador sigue con aviso | Recarga con Ctrl+F5 y entra por el dominio, no por la IP; si ves "(STAGING)" emite el definitivo |
| El webphone no conecta aunque la web tiene candado | `asterisk.pem` desactualizado: ejecuta el gancho de la sección 7; comprueba `asterisk -rx 'http show status'` |

## Qué se verificó y qué no

Se emitió un certificado **real** de Let's Encrypt en un servidor real (`pbx.tu-dominio.com`, válido 89 días, emisor Let's Encrypt, comprobado desde otra máquina con el candado verde), con el mismo helper (`issabel-helper ssl_certbot`) que ejecuta el módulo; Asterisk quedó con el mismo certificado en `https://...:8089`; se probó la renovación en seco con los tres ganchos. Los errores de las secciones 4, 5 y 7 salen de esa emisión real.

**No se probó** pulsando el botón del módulo en la web (se ejecutó su comando por línea de comandos), y la renovación real a los 60 días solo se simuló.
