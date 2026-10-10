#!/bin/bash
# Actualiza los paquetes de un Issabel 5 (Rocky Linux 8 y paquetes de Issabel) con respaldo antes y verificacion despues.
#   bash scripts/actualizar-issabel.sh --si
# NO cambia de version mayor de Rocky (8 a 9) ni toca el Call Center (eso es actualizar-callcenter.sh) ni el Asterisk
# que compilaste tu (esos RPM tienen un numero de version mayor que los del repositorio, asi que dnf no los baja).
# Hazlo en una ventana sin llamadas y con un snapshot del VPS: es lo que de verdad te salva si algo sale mal.
set -uo pipefail
[ "${1:-}" = "--si" ] || { echo "Uso: $0 --si"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "Ejecuta como root."; exit 1; }
rpm -q issabel-pbx >/dev/null 2>&1 || { echo "ABORTA: esto no es un Issabel 5."; exit 1; }
n=$(asterisk -rx 'core show channels count' 2>/dev/null | awk '/active channel/{print $1}')
[ "${n:-0}" = "0" ] || { echo "ABORTA: hay $n canal(es) activo(s). Espera a que no haya llamadas."; exit 1; }
FREE=$(df -P / | awk 'NR==2{print int($4/1048576)}'); [ "$FREE" -ge 3 ] || { echo "ABORTA: solo ${FREE} GB libres en /"; exit 1; }

BK=/root/respaldo-actualizacion-$(date +%Y%m%d-%H%M%S); install -d -m 700 "$BK"
echo "== Respaldo en $BK =="
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > "$BK/paquetes-antes.txt"
tar -C / -cpf "$BK/config.tar" etc/asterisk etc/httpd/conf.d etc/issabel.conf etc/amportal.conf var/www/db 2>/dev/null
PW=$(awk -F= '/^mysqlrootpwd/{print $2}' /etc/issabel.conf)
for db in asterisk asteriskcdrdb call_center; do
  MYSQL_PWD="$PW" mysqldump -uroot --single-transaction "$db" > "$BK/$db.sql" 2>/dev/null && chmod 600 "$BK/$db.sql"
done
echo "respaldo: $(du -sh "$BK" | cut -f1)"
echo -n "Asterisk antes: "; asterisk -rx 'core show version' | cut -c1-40
echo -n "Issabel antes:  "; rpm -q issabel-pbx issabel-framework | tr '\n' ' '; echo

echo "== Paquetes pendientes =="
dnf -q check-update 2>/dev/null | grep -E '^[a-zA-Z0-9]' | awk '{print $1}' > "$BK/pendientes.txt"
echo "$(wc -l < "$BK/pendientes.txt") paquetes; de Issabel: $(grep -c -E '^(issabel|asterisk)' "$BK/pendientes.txt")"

echo "== Actualizando =="
# timeout/minrate/retries: un espejo lento o colgado no debe dejar el comando esperando para siempre; dnf corta la
# descarga y la reintenta (con otro espejo si hay). Si se interrumpe, repetir el script reanuda con lo ya descargado.
dnf -y --setopt=timeout=30 --setopt=minrate=5000 --setopt=retries=10 update 2>&1 | tail -15
RC=${PIPESTATUS[0]}

echo "== Verificacion =="
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > "$BK/paquetes-despues.txt"
echo "paquetes cambiados: $(comm -13 "$BK/paquetes-antes.txt" "$BK/paquetes-despues.txt" | wc -l)"
for s in mariadb httpd asterisk; do echo -n "$s: "; systemctl is-active $s; done
echo -n "web https: "; curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1/
echo -n "Asterisk despues: "; asterisk -rx 'core show version' | cut -c1-40
if command -v needs-restarting >/dev/null 2>&1; then needs-restarting -r | tail -2; else echo "Si se actualizo el kernel (uname -r distinto de rpm -q kernel), reinicia el servidor."; fi
echo "RESPALDO EN: $BK"
exit $RC
