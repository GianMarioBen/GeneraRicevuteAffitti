#!/bin/bash

APP_SUPPORT="$HOME/Library/Application Support/CruscottoAffitti"
PY_SERVER="$APP_SUPPORT/Cruscotto_Affitti_Server.py"
RB_SERVER="$APP_SUPPORT/Cruscotto_Affitti_Server.rb"
PIDFILE="/tmp/Cruscotto_Affitti_Server.pid"
PORT="8765"
RUNLOG="/tmp/Cruscotto_Affitti_Autostart.log"

logmsg() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$RUNLOG"
}

logmsg "=== LaunchAgent Cruscotto Affitti avviato ==="

# Se la porta è momentaneamente occupata, NON entriamo in un restart-loop:
# restiamo vivi e aspettiamo che torni libera.
while /usr/sbin/lsof -nP -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; do
  PID="$(/usr/sbin/lsof -nP -iTCP:${PORT} -sTCP:LISTEN -t 2>/dev/null | head -n 1)"
  CMDLINE="$(ps -p "$PID" -o command= 2>/dev/null || true)"
  logmsg "Porta ${PORT} occupata da PID ${PID}: ${CMDLINE}. Attendo..."
  sleep 5
done

# Il PID dello shell diventerà il PID del server grazie a exec.
echo $$ > "$PIDFILE"

# Cerca Python 3 anche fuori dal PATH minimale di launchd.
for PY3 in /usr/local/bin/python3 /opt/homebrew/bin/python3 /usr/bin/python3; do
  if [ -x "$PY3" ] && "$PY3" -V >/dev/null 2>&1; then
    logmsg "Avvio server Python: $PY3"
    exec "$PY3" "$PY_SERVER"
  fi
done

# High Sierra della Mammetta: fallback storico Ruby/WEBrick.
if [ -x /usr/bin/ruby ]; then
  logmsg "Python 3 non disponibile: avvio fallback Ruby/WEBrick."
  exec /usr/bin/ruby "$RB_SERVER"
fi

logmsg "ERRORE: non trovo né Python 3 né Ruby."
exit 1
