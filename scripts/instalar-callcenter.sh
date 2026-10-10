#!/bin/bash
# Instala el Call Center Community (V5) desde el repositorio OFICIAL, siempre en su ultima version.
#   bash scripts/instalar-callcenter.sh
# NO uses el RPM "issabel-callcenter" de los repositorios: es la linea 4.0 (vieja). El proyecto ya no publica RPM;
# el unico camino soportado es el instalador del repositorio. Ver docs/03-call-center.md.
# Idempotente: si ya esta instalado, te dice la version y que uses actualizar-callcenter.sh.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Ejecuta como root."; exit 1; }
REPO=https://github.com/ISSABELPBX/callcenter-issabel5.git
DEST=/usr/src/callcenter-issabel5
STAMP=/usr/share/issabel/module_installer/callcenter/VERSION

rpm -q issabel-pbx >/dev/null 2>&1 || { echo "ABORTA: esto no es un Issabel 5."; exit 1; }
if [ -f "$STAMP" ] && [ -d /opt/issabel/dialer ]; then
  echo "El Call Center ya esta instalado (version $(cat $STAMP)). Para actualizar: bash scripts/actualizar-callcenter.sh --si"
  exit 0
fi
echo "Asterisk: $(asterisk -rx 'core show version' | cut -c1-30)"

# La linea 4.0 (RPM) deja /opt/issabel/dialer con un log y el instalador V5 se niega si el directorio existe
if rpm -q issabel-callcenter >/dev/null 2>&1; then
  echo "AVISO: tienes el RPM issabel-callcenter (linea 4.0). Quitalo antes: dnf remove issabel-callcenter"; exit 1
fi
if [ -d /opt/issabel/dialer ] && [ ! -e /opt/issabel/dialer/dialerd ]; then rm -rf /opt/issabel/dialer; fi

command -v git >/dev/null 2>&1 || dnf -y install git 2>&1 | tail -1
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" fetch --quiet origin && git -C "$DEST" merge --ff-only origin/master 2>&1 | tail -1
else
  git clone "$REPO" "$DEST" 2>&1 | tail -1
fi
echo "VERSION oficial: $(cat "$DEST/VERSION")   commit: $(git -C "$DEST" log -1 --format='%h %ad' --date=short)"

echo "== Instalando (el instalador detecta tu version de Asterisk) =="
( cd "$DEST" && bash build/5.0/install-issabel-callcenter.sh -l ) 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^INFO: (Ya existe|La longitud)' | tail -40 | cut -c1-200
RC=${PIPESTATUS[0]}
sleep 5
echo "== Verificacion =="
echo -n "version instalada: "; cat "$STAMP" 2>/dev/null || echo "?"
echo -n "issabeldialer: "; systemctl is-active issabeldialer
echo -n "puerto ECCP 20005 escuchando: "; ss -ltn | grep -c ':20005' || true
echo "Cierra sesion y vuelve a entrar en la web de Issabel: veras el menu Call Center."
exit $RC
