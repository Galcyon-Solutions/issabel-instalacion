#!/bin/bash
# Gancho de renovacion de Let's Encrypt: regenera el certificado que Asterisk usa para WebSocket seguro (puerto 8089).
#
# POR QUE HACE FALTA: el modulo Seguridad > HTTPS Certificate (Let's Encrypt) de Issabel escribe
# /etc/asterisk/keys/asterisk.pem cuando emites o renuevas con SU boton. Pero la renovacion automatica diaria
# (certbot-renew.timer) NO pasa por el modulo: renueva el certificado de Apache y deja el de Asterisk viejo.
# A los ~90 dias el webphone (WSS) deja de conectar aunque la web siga bien. Este gancho cierra esa brecha.
#
# INSTALAR (una vez, despues de emitir el certificado):
#   install -d /etc/letsencrypt/renewal-hooks/deploy
#   install -m 755 scripts/hook-renovar-asterisk-pem.sh /etc/letsencrypt/renewal-hooks/deploy/asterisk-pem.sh
# PROBAR sin esperar 90 dias:  bash /etc/letsencrypt/renewal-hooks/deploy/asterisk-pem.sh
set -uo pipefail
SSL_CONF="${SSL_CONF:-/etc/httpd/conf.d/ssl.conf}"
PEM="${PEM:-/etc/asterisk/keys/asterisk.pem}"

install -d -m 751 "$(dirname "$PEM")"
TMP=$(mktemp "$PEM.XXXXXX")
# Misma receta que el modulo de Issabel: cadena completa (fullchain) + clave privada, en ese orden, tal como
# estan declaradas en ssl.conf (SSLCertificateFile y SSLCertificateKeyFile)
for A in $(grep '^SSLCert' "$SSL_CONF" | awk '{print $2}' | sed 's/cert.pem/fullchain.pem/g'); do
  [ -r "$A" ] || { echo "No puedo leer $A"; rm -f "$TMP"; exit 1; }
  cat "$A" >> "$TMP"
done
[ -s "$TMP" ] || { echo "El PEM quedo vacio: revisa SSLCertificateFile en $SSL_CONF"; rm -f "$TMP"; exit 1; }
chown root:asterisk "$TMP" 2>/dev/null; chmod 640 "$TMP"
mv -f "$TMP" "$PEM"
if command -v asterisk >/dev/null 2>&1 && asterisk -rx 'core waitfullybooted' >/dev/null 2>&1; then
  asterisk -rx 'module reload http' | tail -1
fi
echo "asterisk.pem regenerado: $(openssl x509 -in "$PEM" -noout -enddate 2>/dev/null)"
