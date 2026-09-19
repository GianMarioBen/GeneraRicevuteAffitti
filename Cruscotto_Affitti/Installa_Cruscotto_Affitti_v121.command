#!/bin/bash
# Installer Cruscotto Affitti v121 — per il Mac della Mammetta (bless, High Sierra 10.13.6)
#
# Cosa fa:
#   1. Fa un BACKUP con data/ora di tutto quello che sta per sostituire.
#   2. Compila WhatsApp_Engine_v121.applescript -> WhatsApp_Engine.scpt
#      e lo installa in ~/Library/Application Support/CruscottoAffitti/
#   3. Installa Generatore_Ricevute_Condominio_v120.html come
#      Generatore_Ricevute_Condominio.html nella cartella principale.
#   4. Installa il runner del server (Avvia_Cruscotto_Affitti_Server.sh)
#      e il server Python (Cruscotto_Affitti_Server.py).
#   5. Installa il LaunchAgent (plist) e riavvia il server.
#
# Cosa NON tocca MAI (nessuna riga di questo script scrive lì dentro):
#   - ElencoRicevute/  (Affittuari.json, Ricevute_Dati.json, i PDF, i log,
#     WhatsApp_Destinatario.json, WhatsApp_Inviati.log, ecc.)
#   - ~/Applications/Invia Ricevuta WhatsApp.app  (il guscio Helper
#     autorizzato in Accessibilità: NON va mai ricreato o rifirmato,
#     altrimenti si perde il consenso Accessibilità di High Sierra)
#
# Si può rilanciare più volte in sicurezza: ogni volta fa un nuovo backup
# datato prima di sovrascrivere.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT_DIR="/Users/bless/Archivio/Appart/Ricevute Affittuari"
DATA_DIR="$ROOT_DIR/ElencoRicevute"
HTML_NAME="Generatore_Ricevute_Condominio.html"
HTML_TARGET="$ROOT_DIR/$HTML_NAME"

APP_SUPPORT="$HOME/Library/Application Support/CruscottoAffitti"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST_NAME="com.letmar.cruscottoaffitti.server.plist"
PLIST_TARGET="$LAUNCH_AGENTS/$PLIST_NAME"

STAMP="$(date '+%Y%m%d_%H%M%S')"
BACKUP_DIR="$APP_SUPPORT/Backup_Installer/$STAMP"

INSTALL_LOG="/tmp/Cruscotto_Affitti_Installer.log"

log() {
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$INSTALL_LOG"
}

fail() {
  log "ERRORE: $*"
  osascript -e "display alert \"Installazione non riuscita\" message \"$*\" as critical" >/dev/null 2>&1
  exit 1
}

: > /dev/null
log "=== Installer Cruscotto Affitti v121 avviato da $SCRIPT_DIR ==="

# --- 0. Controlli di base -----------------------------------------------

if [ "$(whoami)" != "bless" ]; then
  log "ATTENZIONE: utente attuale è $(whoami), non 'bless'. Proseguo comunque perché i percorsi restano quelli previsti per bless, ma verificare che sia il Mac giusto."
fi

for f in \
  "$SCRIPT_DIR/WhatsApp_Engine_v121.applescript" \
  "$SCRIPT_DIR/Generatore_Ricevute_Condominio_v120.html" \
  "$SCRIPT_DIR/Avvia_Cruscotto_Affitti_Server.sh" \
  "$SCRIPT_DIR/Cruscotto_Affitti_Server.py" \
  "$SCRIPT_DIR/com.letmar.cruscottoaffitti.server.plist"
do
  if [ ! -f "$f" ]; then
    fail "File mancante nel pacchetto: $f\n\nAssicurati di aver scompattato TUTTO lo zip nella stessa cartella prima di lanciare l'installer."
  fi
done

if [ ! -d "$ROOT_DIR" ]; then
  fail "Non trovo la cartella principale:\n$ROOT_DIR\n\nQuesto installer è pensato per il Mac della Mammetta. Se i percorsi sono cambiati, avvisa Mario prima di continuare."
fi

if [ ! -d "$DATA_DIR" ]; then
  fail "Non trovo ElencoRicevute dentro:\n$ROOT_DIR\n\nPer sicurezza mi fermo: non voglio installare nulla se i dati degli affittuari non sono al loro posto."
fi

mkdir -p "$APP_SUPPORT" "$LAUNCH_AGENTS" "$BACKUP_DIR" || fail "Non riesco a creare le cartelle di destinazione/backup."
log "Backup di questa installazione in: $BACKUP_DIR"

# --- 1. Backup di tutto ciò che sto per sovrascrivere --------------------
# (mai un 'mv', sempre 'cp': l'originale resta comunque dov'era finché
#  non lo sostituisco esplicitamente più sotto)

backup_if_exists() {
  local src="$1"
  local label="$2"
  if [ -e "$src" ]; then
    mkdir -p "$BACKUP_DIR/$label"
    cp -p "$src" "$BACKUP_DIR/$label/" 2>>"$INSTALL_LOG"
    log "Backup: $src -> $BACKUP_DIR/$label/"
  else
    log "Nessun file preesistente da salvare per: $src (prima installazione, ok)."
  fi
}

backup_if_exists "$APP_SUPPORT/WhatsApp_Engine.scpt" "WhatsApp_Engine"
backup_if_exists "$APP_SUPPORT/Avvia_Cruscotto_Affitti_Server.sh" "Server_Runner"
backup_if_exists "$APP_SUPPORT/Cruscotto_Affitti_Server.py" "Server_Python"
backup_if_exists "$HTML_TARGET" "Generatore_HTML"
backup_if_exists "$PLIST_TARGET" "LaunchAgent_Plist"

# Nota IMPORTANTE: NON facciamo alcun backup/tocco di $DATA_DIR
# (ElencoRicevute) perché questo installer non lo scrive mai.
log "NON toccato (come da regola): $DATA_DIR"

# --- 2. Compila ed installa il motore WhatsApp v121 -----------------------

command -v osacompile >/dev/null 2>&1 || fail "osacompile non trovato: questo Mac non ha gli strumenti AppleScript. Impossibile compilare il motore WhatsApp."

TMP_SCPT="/tmp/WhatsApp_Engine_v121_$STAMP.scpt"
osacompile -o "$TMP_SCPT" "$SCRIPT_DIR/WhatsApp_Engine_v121.applescript" 2>>"$INSTALL_LOG" \
  || fail "osacompile ha fallito la compilazione di WhatsApp_Engine_v121.applescript. Dettagli in $INSTALL_LOG"

cp -p "$TMP_SCPT" "$APP_SUPPORT/WhatsApp_Engine.scpt" \
  || fail "Non riesco a copiare WhatsApp_Engine.scpt in $APP_SUPPORT"
rm -f "$TMP_SCPT"
log "Installato: $APP_SUPPORT/WhatsApp_Engine.scpt (da v121)"

# Scrive un file di versione che il server legge e mostra nel Generatore
# HTML (badge accanto al titolo), così si vede sempre "dietro le quinte"
# quale motore WhatsApp è davvero installato, senza doversi fidare a
# occhio del numero di versione della pagina HTML (che resta v120).
ENGINE_VERSION_FILE="$APP_SUPPORT/WhatsApp_Engine_Version.json"
INSTALLED_AT_HUMAN="$(date '+%d/%m/%Y %H:%M')"
cat > "$ENGINE_VERSION_FILE" <<EOF
{
  "version": "v121",
  "installedAt": "$INSTALLED_AT_HUMAN",
  "sourceFile": "WhatsApp_Engine_v121.applescript"
}
EOF
log "Scritto: $ENGINE_VERSION_FILE (badge versione motore nel Generatore)"

# --- 3. Installa Generatore HTML v120 -------------------------------------

cp -p "$SCRIPT_DIR/Generatore_Ricevute_Condominio_v120.html" "$HTML_TARGET" \
  || fail "Non riesco a copiare il Generatore HTML in $HTML_TARGET"
log "Installato: $HTML_TARGET (v120)"

# --- 4. Installa runner + server Python -----------------------------------

cp -p "$SCRIPT_DIR/Avvia_Cruscotto_Affitti_Server.sh" "$APP_SUPPORT/Avvia_Cruscotto_Affitti_Server.sh" \
  || fail "Non riesco a copiare Avvia_Cruscotto_Affitti_Server.sh"
chmod +x "$APP_SUPPORT/Avvia_Cruscotto_Affitti_Server.sh"
log "Installato: $APP_SUPPORT/Avvia_Cruscotto_Affitti_Server.sh"

cp -p "$SCRIPT_DIR/Cruscotto_Affitti_Server.py" "$APP_SUPPORT/Cruscotto_Affitti_Server.py" \
  || fail "Non riesco a copiare Cruscotto_Affitti_Server.py"
log "Installato: $APP_SUPPORT/Cruscotto_Affitti_Server.py"

# --- 5. Installa/aggiorna il LaunchAgent e riavvia il server --------------

cp -p "$SCRIPT_DIR/com.letmar.cruscottoaffitti.server.plist" "$PLIST_TARGET" \
  || fail "Non riesco a copiare il LaunchAgent in $PLIST_TARGET"
log "Installato: $PLIST_TARGET"

UID_NUM="$(id -u)"
if launchctl print "gui/$UID_NUM/com.letmar.cruscottoaffitti.server" >/dev/null 2>&1; then
  log "LaunchAgent già in esecuzione: lo ricarico per usare i nuovi file."
  launchctl bootout "gui/$UID_NUM" "$PLIST_TARGET" >>"$INSTALL_LOG" 2>&1
  sleep 1
fi
launchctl bootstrap "gui/$UID_NUM" "$PLIST_TARGET" >>"$INSTALL_LOG" 2>&1 \
  || launchctl load "$PLIST_TARGET" >>"$INSTALL_LOG" 2>&1
launchctl kickstart -k "gui/$UID_NUM/com.letmar.cruscottoaffitti.server" >>"$INSTALL_LOG" 2>&1 || true

log "LaunchAgent avviato/ricaricato."

# --- 6. Verifica finale ----------------------------------------------------

sleep 2
HEALTH="$(curl -s --max-time 5 http://127.0.0.1:8765/api/health 2>>"$INSTALL_LOG")"

if [ -n "$HEALTH" ]; then
  log "Server risponde: $HEALTH"
  MSG="Installazione completata.

Motore WhatsApp: v121 (fix apertura chat con SPACE)
Generatore: v120
Server: attivo su http://127.0.0.1:8765

Backup della versione precedente salvato in:
$BACKUP_DIR

I dati degli affittuari (ElencoRicevute) NON sono stati toccati."
  log "=== Installazione completata con successo ==="
  osascript -e "display dialog \"$MSG\" with title \"Cruscotto Affitti — Installazione v121\" buttons {\"OK\"} default button 1" >/dev/null 2>&1
else
  log "ATTENZIONE: il server non ha risposto entro 5 secondi su /api/health."
  MSG="I file sono stati installati e il backup è in:
$BACKUP_DIR

Ma il server su 127.0.0.1:8765 non ha ancora risposto.
Prova a riavviare il Mac, oppure controlla il log:
/tmp/Cruscotto_Affitti_Autostart.log"
  osascript -e "display dialog \"$MSG\" with title \"Cruscotto Affitti — Installazione v121\" buttons {\"OK\"} default button 1" >/dev/null 2>&1
fi

log "Log completo di questa installazione: $INSTALL_LOG"
exit 0
