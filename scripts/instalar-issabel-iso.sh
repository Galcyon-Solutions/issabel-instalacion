#!/bin/bash
# Instala la ULTIMA version de Issabel 5 (ISO 20261001, con Asterisk 20) sobre un Rocky Linux 8 minimal,
# SIN usar el instalador grafico: la ISO oficial se monta como repositorio local y se instalan los mismos
# grupos de paquetes que instala su kickstart. Es el camino a la version mas nueva con script, porque el
# netinstall oficial solo ofrece Asterisk 16 o 18 (ver docs/01-instalar-issabel.md).
#
#   bash scripts/instalar-issabel-iso.sh --iso /root/issabel5-USB-DVD-x86_64-20261001.iso
#   bash scripts/instalar-issabel-iso.sh --descargar            # baja la ISO (3,7 GB) y la verifica
#   bash scripts/instalar-issabel-iso.sh --repo-dir /mnt/iso     # si ya montaste o extrajiste la ISO tu
#
# Opciones:
#   --grupo "Issabel with Asterisk 20"   entorno a instalar (por defecto el de Asterisk 20)
#   --sin-rbl                            no instala la lista de bloqueo comunitaria (RBL)
#   --con-licenciados                    instala tambien los modulos de pago de Issabel Network (no hace falta)
#   --sin-passwords                      no lanza el asistente de contrasenas al final (lo haras tu)
# Ejecutar como root, en un Rocky Linux 8.x minimal con IP fija y nombre de equipo. Reinicia al terminar.
set -uo pipefail

ISO_NAME="issabel5-USB-DVD-x86_64-20261001.iso"
ISO_URL="https://sourceforge.net/projects/issabelpbx/files/Issabel%205/issabel5-USB-DVD-x86_64-20261001.iso/download"
ISO_SHA256="c63b7512d3ba05af645e144c58bf00c87353ddf2b3318e2fda8c262c057c07f9"
MNT=/mnt/issabel-iso
GRUPO="Issabel with Asterisk 20"
ISO=""; REPO_DIR=""; DESCARGAR=0; RBL=1; LICENCIADOS=0; PASSWORDS=1

while [ $# -gt 0 ]; do
  case "$1" in
    --iso) ISO="$2"; shift ;;
    --repo-dir) REPO_DIR="$2"; shift ;;
    --descargar) DESCARGAR=1 ;;
    --grupo) GRUPO="$2"; shift ;;
    --sin-rbl) RBL=0 ;;
    --con-licenciados) LICENCIADOS=1 ;;
    --sin-passwords) PASSWORDS=0 ;;
    *) echo "Argumento desconocido: $1"; exit 2 ;;
  esac; shift
done

die() { echo "ABORTA: $*"; exit 1; }
[ "$(id -u)" = 0 ] || die "ejecuta como root."
grep -q "Rocky Linux release 8" /etc/redhat-release || die "este script es para Rocky Linux 8 (Issabel 5 no soporta Rocky 9)."
rpm -q issabel-pbx >/dev/null 2>&1 && die "este servidor ya tiene Issabel instalado."
FREE=$(df -P / | awk 'NR==2{print int($4/1048576)}'); [ "$FREE" -ge 12 ] || die "hay ${FREE} GB libres en / (se necesitan al menos 12 GB, mejor 20)."
MEM=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo); [ "$MEM" -ge 1800 ] || echo "AVISO: ${MEM} MB de RAM. Issabel pide 2 GB o mas para ir comodo."
getent hosts "$(hostname)" >/dev/null || echo "$(hostname -I | awk '{print $1}') $(hostname)" >> /etc/hosts

echo "== 1. La ISO como repositorio local =="
if [ -n "$REPO_DIR" ]; then
  MNT="$REPO_DIR"
else
  if [ -z "$ISO" ]; then
    [ "$DESCARGAR" = 1 ] || die "indica --iso <archivo>, --repo-dir <carpeta> o --descargar."
    ISO=/root/$ISO_NAME
    dnf -y install curl >/dev/null 2>&1
    curl -L -C - --fail -o "$ISO" "$ISO_URL" || die "la descarga fallo (puedes repetir el comando: reanuda donde quedo)."
  fi
  [ -f "$ISO" ] || die "no existe $ISO"
  echo "Verificando SHA-256 (tarda un minuto)..."
  H=$(sha256sum "$ISO" | cut -d' ' -f1)
  [ "$H" = "$ISO_SHA256" ] || die "el SHA-256 no coincide ($H). Descarga de nuevo o usa la ISO que indica este script."
  mkdir -p "$MNT"; mountpoint -q "$MNT" || mount -o loop,ro "$ISO" "$MNT" || die "no se pudo montar la ISO."
fi
[ -f "$MNT/repodata/repomd.xml" ] || die "$MNT no contiene el repositorio de la ISO (falta repodata/repomd.xml)."
printf '[iso-issabel]\nname=ISO oficial de Issabel 5\nbaseurl=file://%s\nenabled=1\ngpgcheck=0\n' "$MNT" > /etc/yum.repos.d/iso-issabel.repo
# gpgcheck=0: es un repositorio local y la ISO se verifico por hash arriba

echo "== 2. Instalando '$GRUPO' (cientos de paquetes; tarda 15 a 40 minutos) =="
GRUPOS=("$GRUPO")
[ "$RBL" = 1 ] && GRUPOS+=("Issabel.guru community RBL (Realtime Blackhole List)")
[ "$LICENCIADOS" = 1 ] && GRUPOS+=("Issabel Network Licensed modules (http://issabel.guru)")
if ! dnf -y --disablerepo='*' --enablerepo=iso-issabel group install "${GRUPOS[@]}"; then
  # Algunas imagenes de VPS traen libcurl-minimal o coreutils-single, que chocan con los paquetes completos de la ISO
  echo "AVISO: conflicto con paquetes minimos de la imagen; reintento permitiendo reemplazarlos (--allowerasing)"
  dnf -y --disablerepo='*' --enablerepo=iso-issabel --allowerasing group install "${GRUPOS[@]}" || die "dnf termino con error (revisa el mensaje de arriba)."
fi

echo "== 3. Pasos de %post del kickstart oficial =="
mkdir -p /var/log/asterisk/cdr-csv /var/lib/asterisk/sounds/custom
echo " " >> /etc/asterisk/res_odbc_additional.conf
echo " " >> /etc/asterisk/res_odbc_custom.conf
chown -R asterisk:asterisk /var/www/html /etc/asterisk /var/lib/asterisk /var/log/asterisk
chmod 755 /var/lib/asterisk/agi-bin/* 2>/dev/null
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config; setenforce 0 2>/dev/null
# El %post del paquete phpx-loader corre con "|| :" y puede fallar en silencio: sin esto la pagina Usuarios no abre
[ -x /usr/sbin/phpx-loader-select ] && /usr/sbin/phpx-loader-select --quiet || true
systemctl daemon-reload
systemctl enable --now mariadb || die "mariadb no arranca"
systemctl start asterisk || echo "AVISO: asterisk no arranco todavia (IssabelPBX lo reiniciara)"

echo "== 4. Primer arranque: IssabelPBX y contrasenas =="
if [ "$PASSWORDS" = 1 ]; then
  [ -f /etc/amportal.conf ] || touch /installamp
  echo "Se abre el asistente: te pide la clave de root de MariaDB y la clave del usuario admin de la web."
  /usr/bin/issabel-admin-passwords --init
  command -v amportal >/dev/null 2>&1 && amportal chown >/dev/null 2>&1
else
  touch /installamp
  echo "Omitido. Ejecuta tu despues: /usr/bin/issabel-admin-passwords --init"
fi

# La ISO solo hace falta durante la instalacion; las actualizaciones salen de los repositorios de Issabel
rm -f /etc/yum.repos.d/iso-issabel.repo; dnf clean all >/dev/null 2>&1
echo
echo "Instalacion terminada. Version de Asterisk: $(asterisk -rx 'core show version' 2>/dev/null | cut -c1-30)"
echo "Reinicia el servidor (reboot) y entra a https://<ip-del-servidor>/ con el usuario admin."
echo "Si quieres poder volver atras en el parche de Asterisk, conserva el archivo ISO."
