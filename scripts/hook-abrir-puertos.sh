#!/bin/bash
# Abre los puertos 80 y 443 SOLO durante la validacion de Let's Encrypt (en memoria, no persiste).
#
# POR QUE: el firewall de Issabel con bloqueo por pais (GeoIP) rechaza paises enteros, y los validadores de
# Let's Encrypt llegan desde varios paises distintos y SIN una IP fija que puedas permitir. Si el 80 y el 443 estan
# cerrados para ellos, la emision y la RENOVACION fallan con "Connection refused" (la renovacion falla a los 60 dias
# sin que nadie lo note). Se necesita el 443 ademas del 80 porque Issabel redirige HTTP a HTTPS y el validador sigue
# la redireccion.
#
# USO MANUAL (para emitir):
#   bash hook-abrir-puertos.sh abrir      # antes de pedir el certificado
#   bash hook-abrir-puertos.sh cerrar     # despues
# USO AUTOMATICO (para renovar): se instala como gancho de certbot (ver docs/02-dominio-y-ssl.md):
#   install -m 755 hook-abrir-puertos.sh /etc/letsencrypt/renewal-hooks/pre/abrir-puertos.sh   (se ejecuta como "abrir")
#   install -m 755 hook-abrir-puertos.sh /etc/letsencrypt/renewal-hooks/post/cerrar-puertos.sh (se ejecuta como "cerrar")
set -uo pipefail
ACCION="${1:-}"
if [ -z "$ACCION" ]; then
  case "$(basename "$0")" in *abrir*) ACCION=abrir ;; *cerrar*) ACCION=cerrar ;; esac
fi
REGLA=(-p tcp -m multiport --dports 80,443 -m comment --comment temporal-letsencrypt -j ACCEPT)
case "$ACCION" in
  abrir)  iptables -C INPUT "${REGLA[@]}" 2>/dev/null || iptables -I INPUT 1 "${REGLA[@]}"; echo "80 y 443 abiertos temporalmente" ;;
  cerrar) while iptables -C INPUT "${REGLA[@]}" 2>/dev/null; do iptables -D INPUT "${REGLA[@]}"; done; echo "80 y 443 como estaban" ;;
  *) echo "Uso: $0 abrir|cerrar"; exit 1 ;;
esac
