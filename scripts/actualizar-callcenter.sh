#!/bin/bash
# Actualiza el Call Center Community a la ultima version del repositorio OFICIAL con su propio actualizador
# (build/5.0/update-issabel-callcenter.sh), con respaldo previo, prueba en seco y verificacion.
#   bash scripts/actualizar-callcenter.sh --si
#   bash scripts/actualizar-callcenter.sh --restore /root/respaldo-callcenter-<fecha> --si
# Ejecutar EN el servidor, como root. Siempre la ultima version del repositorio oficial.
# El clon oficial /usr/src/callcenter-issabel5 no tiene cambios locales, asi que se actualiza con fast-forward. El actualizador
# SOBRESCRIBE los archivos que actualiza (no hay personalizaciones del Call Center en esta unidad) y reinicia issabeldialer.
# Reversa: --restore con el directorio de respaldo que imprime este script (base de datos, dialer, modulos, menu y ACL).
set -uo pipefail
MODE=update; BK=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --si) YES=1 ;;
    --restore) MODE=restore; BK="${2:-}"; shift ;;
    *) echo "Argumento desconocido: $1"; exit 2 ;;
  esac
  shift
done
[ "${YES:-0}" = 1 ] || { echo "Falta --si. No se hizo nada."; exit 1; }
REPO=/usr/src/callcenter-issabel5
STAMP=/usr/share/issabel/module_installer/callcenter/VERSION
mysqlr() { MYSQL_PWD=$(awk -F= '/^mysqlrootpwd/{print $2}' /etc/issabel.conf) mysql -uroot "$@"; }
mysqldumpr() { MYSQL_PWD=$(awk -F= '/^mysqlrootpwd/{print $2}' /etc/issabel.conf) mysqldump -uroot "$@"; }

estado() {
  echo -n "version instalada: "; cat "$STAMP" 2>/dev/null || echo "?"
  echo -n "issabeldialer: "; systemctl is-active issabeldialer 2>&1 | tail -1
  echo -n "puerto 20005: "; ss -ltn | grep -c ':20005' || true
  echo -n "agentes en call_center: "; mysqlr -N -e "select count(*) from call_center.agent" 2>&1 | tail -1
  echo -n "menus call_center: "; sqlite3 /var/www/db/menu.db "select count(*) from menu where id like 'call_center%' or IdParent='call_center'" 2>&1 | tail -1
  echo -n "canales activos: "; asterisk -rx 'core show channels count' | awk '/active channel/{print $1}'
}

if [ "$MODE" = restore ]; then
  [ -d "$BK" ] && [ -f "$BK/call_center.sql" ] || { echo "ABORTA: respaldo invalido: $BK"; exit 1; }
  [ "$(grep -c '^CREATE TABLE' "$BK/call_center.sql")" -gt 0 ] || { echo "ABORTA: el respaldo de la base no tiene tablas (esta vacio): restaurarlo borraria call_center."; exit 1; }
  echo "== Restaurando desde $BK =="
  systemctl stop issabeldialer 2>&1 | grep -v -E '^(Bus|Sent|Got|Executing|Adding)' || true
  mysqlr -e "DROP DATABASE IF EXISTS call_center; CREATE DATABASE call_center CHARACTER SET utf8 COLLATE utf8_general_ci" && mysqlr call_center < "$BK/call_center.sql" && echo "base restaurada"
  tar -C / -xpf "$BK/archivos.tar" && echo "archivos restaurados"
  cp -a "$BK/menu.db" /var/www/db/menu.db; cp -a "$BK/acl.db" /var/www/db/acl.db
  cp -a "$BK/VERSION" "$STAMP"
  systemctl daemon-reload; systemctl start issabeldialer 2>&1 | grep -v -E '^(Bus|Sent|Got|Executing|Adding)' || true
  sleep 5; estado; exit 0
fi

[ -d "$REPO/.git" ] || { echo "ABORTA: falta el clon oficial $REPO"; exit 1; }
echo "== Antes =="; estado
n=$(asterisk -rx 'core show channels count' | awk '/active channel/{print $1}')
[ "$n" = "0" ] || { echo "ABORTA: hay $n canal(es) activo(s)"; exit 1; }
[ "$(git -C "$REPO" status --porcelain | wc -l)" = 0 ] || { echo "ABORTA: el clon oficial tiene cambios locales"; exit 1; }

echo "== Respaldo =="
BK=/root/respaldo-callcenter-$(date +%Y%m%d-%H%M%S); install -d -m 700 "$BK"
mysqldumpr --single-transaction --routines call_center > "$BK/call_center.sql" && chmod 600 "$BK/call_center.sql"
# Un respaldo vacio es peor que ninguno: --restore borraria la base y la dejaria sin tablas
[ "$(grep -c '^CREATE TABLE' "$BK/call_center.sql")" -gt 0 ] || { echo "ABORTA: el respaldo de la base call_center salio vacio; no se toca nada."; exit 1; }
echo "base: $(wc -c < "$BK/call_center.sql") bytes, $(grep -c '^CREATE TABLE' "$BK/call_center.sql") tablas"
cp -a "$STAMP" "$BK/VERSION"; cp -a /var/www/db/menu.db /var/www/db/acl.db "$BK/"
LIST="opt/issabel/dialer usr/share/issabel/module_installer/callcenter etc/asterisk/agents.conf etc/asterisk/extensions_custom.conf etc/systemd/system/issabeldialer.service"
for m in $(ls "$REPO/modules" 2>/dev/null); do [ -e "/var/www/html/modules/$m" ] && LIST="$LIST var/www/html/modules/$m"; done
( cd / && tar -cpf "$BK/archivos.tar" $LIST 2>/dev/null ) && echo "archivos: $(wc -c < "$BK/archivos.tar") bytes"
echo "RESPALDO EN: $BK"

echo "== Traer la ultima version oficial =="
git -C "$REPO" fetch --quiet origin && git -C "$REPO" merge --ff-only origin/master 2>&1 | tail -2
echo -n "VERSION del clon: "; cat "$REPO/VERSION"; git -C "$REPO" log -1 --format='commit %h %ad %s' --date=short

echo "== Prueba en seco del actualizador oficial =="
bash "$REPO/build/5.0/update-issabel-callcenter.sh" --dry-run 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -20 | cut -c1-200

echo "== Actualizando (confirmacion automatica 'yes') =="
printf 'yes\n' | bash "$REPO/build/5.0/update-issabel-callcenter.sh" > "$BK/update.log" 2>&1; RC=$?
sed 's/\x1b\[[0-9;]*m//g' "$BK/update.log" | tail -25 | cut -c1-200
echo "codigo de salida del actualizador: $RC"
sleep 6
echo "== Despues =="; estado
echo "--- errores recientes del dialer"; grep -E " ERR| FATAL|Fatal error" /opt/issabel/dialer/dialerd.log 2>/dev/null | tail -5 | cut -c1-200
echo "--- Asterisk ERROR nuevos (ultimos 20 s)"; grep -E "ERROR" /var/log/asterisk/full | tail -3 | cut -c1-200
echo "RESPALDO EN: $BK (reversa: --restore $BK --si)"
exit $RC
