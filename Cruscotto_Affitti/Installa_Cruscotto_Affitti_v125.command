#!/bin/bash
# Installer Cruscotto Affitti v125 — TUTTO-IN-UNO — per il Mac della Mammetta
# (bless, High Sierra 10.13.6). Un solo file, nessuno zip, nessun altro file
# da scaricare a parte: tutti i contenuti sono incorporati qui dentro.
#
# Cosa fa:
#   1. Fa un BACKUP con data/ora di tutto quello che sta per sostituire.
#   2. Estrae dai propri dati incorporati e installa:
#      - WhatsApp_Engine.scpt (compilato da v125 — diagnostica a scaglioni)
#      - Generatore_Ricevute_Condominio.html (v120, con badge versione motore)
#      - Cruscotto_Affitti_Server.py (con endpoint /api/health esteso)
#      - Avvia_Cruscotto_Affitti_Server.sh (runner del LaunchAgent)
#      - com.letmar.cruscottoaffitti.server.plist (LaunchAgent)
#   3. Scrive WhatsApp_Engine_Version.json così il badge nel Generatore
#      mostra sempre la versione del motore realmente installata.
#   4. Ricarica il LaunchAgent e verifica /api/health.
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
PAYLOAD_DIR="/tmp/Cruscotto_Affitti_Installer_Payload_$STAMP"

INSTALL_LOG="/tmp/Cruscotto_Affitti_Installer.log"

log() {
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$INSTALL_LOG"
}

fail() {
  log "ERRORE: $*"
  osascript -e "display alert \"Installazione non riuscita\" message \"$*\" as critical" >/dev/null 2>&1
  exit 1
}

log "=== Installer Cruscotto Affitti v125 (tutto-in-uno) avviato ==="

# --- 0. Controlli di base -----------------------------------------------

if [ "$(whoami)" != "bless" ]; then
  log "ATTENZIONE: utente attuale è $(whoami), non 'bless'. Proseguo comunque perché i percorsi restano quelli previsti per bless, ma verificare che sia il Mac giusto."
fi

if [ ! -d "$ROOT_DIR" ]; then
  fail "Non trovo la cartella principale:\n$ROOT_DIR\n\nQuesto installer è pensato per il Mac della Mammetta. Se i percorsi sono cambiati, avvisa Mario prima di continuare."
fi

if [ ! -d "$DATA_DIR" ]; then
  fail "Non trovo ElencoRicevute dentro:\n$ROOT_DIR\n\nPer sicurezza mi fermo: non voglio installare nulla se i dati degli affittuari non sono al loro posto."
fi

mkdir -p "$APP_SUPPORT" "$LAUNCH_AGENTS" "$BACKUP_DIR" "$PAYLOAD_DIR" || fail "Non riesco a creare le cartelle di destinazione/backup/lavoro."
log "Backup di questa installazione in: $BACKUP_DIR"
log "Cartella di lavoro temporanea: $PAYLOAD_DIR"

# --- 1. Estrae i file incorporati in questo installer ---------------------

cat > "$PAYLOAD_DIR/WhatsApp_Engine_v125.applescript" <<'___CRUSCOTTO_PAYLOAD_APPLESCRIPT_9f3c1a___'
property dataDir : "/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute"
property pointerPath : "/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute/Ricevuta_Da_Inviare.txt"
property messagePath : "/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute/Messaggio_Da_Inviare.txt"
property configPath : "/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute/WhatsApp_Destinatario.json"
property sentLogPath : "/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute/WhatsApp_Inviati.log"
property runLogPath : "/tmp/Invia_Ricevuta_WhatsApp_Helper_v97.log"

on appendLog(msg)
	try
		set ts to do shell script "/bin/date '+%Y-%m-%d %H:%M:%S'"
		do shell script "/usr/bin/printf '%s  %s\\n' " & quoted form of ts & " " & quoted form of (msg as text) & " >> " & quoted form of runLogPath
	end try
end appendLog

on readTextFile(thePath)
	try
		return do shell script "/bin/cat " & quoted form of thePath
	on error
		return ""
	end try
end readTextFile

on getRecipientName()
	set recipientName to "Ahmed"
	try
		set shellCmd to "/usr/bin/sed -n 's/.*\"name\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' " & quoted form of configPath & " | /usr/bin/head -n 1"
		set parsedName to do shell script shellCmd
		if parsedName is not "" then set recipientName to parsedName
	end try
	return recipientName
end getRecipientName

on getRecipientPhone()
	set recipientPhone to ""
	try
		set shellCmd to "/usr/bin/sed -n 's/.*\"phone\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' " & quoted form of configPath & " | /usr/bin/head -n 1 | /usr/bin/tr -cd '0-9'"
		set recipientPhone to do shell script shellCmd
	end try
	return recipientPhone
end getRecipientPhone

on focusWhatsAppTab()
	tell application "Google Chrome"
		set foundWindow to missing value
		set foundTabIndex to 0

		repeat with w in windows
			repeat with i from 1 to (count of tabs of w)
				try
					set u to URL of tab i of w
					if u contains "web.whatsapp.com" then
						set foundWindow to w
						set foundTabIndex to i
						exit repeat
					end if
				end try
			end repeat
			if foundWindow is not missing value then exit repeat
		end repeat

		if foundWindow is missing value then return false

		set active tab index of foundWindow to foundTabIndex
		set index of foundWindow to 1
		activate
	end tell
	return true
end focusWhatsAppTab

on openWhatsAppOnlyIfMissing()
	if my focusWhatsAppTab() then
		my appendLog("Riutilizzo la finestra WhatsApp già aperta.")
		return true
	end if

	my appendLog("Nessuna scheda WhatsApp trovata: ne apro UNA.")
	tell application "Google Chrome"
		set w to make new window
		set URL of active tab of w to "https://web.whatsapp.com/"
		set index of w to 1
		activate
	end tell
	return true
end openWhatsAppOnlyIfMissing

on runWhatsAppJS(jsCode)
	tell application "Google Chrome"
		repeat with w in windows
			repeat with i from 1 to (count of tabs of w)
				try
					set u to URL of tab i of w
					if u contains "web.whatsapp.com" then
						set active tab index of w to i
						set index of w to 1
						activate
						return execute active tab of w javascript jsCode
					end if
				end try
			end repeat
		end repeat
	end tell
	return "WAIT"
end runWhatsAppJS

on whatsappState()
	set jsCode to "(function(){try{if(location.hostname!=='web.whatsapp.com')return 'WAIT';if(document.querySelector('#side'))return 'READY';const t=(document.body&&document.body.innerText||'').toLowerCase();const hints=['qr code','codice qr','link with phone','collega con il numero','use whatsapp on your phone','usa whatsapp sul telefono'];if(hints.some(x=>t.includes(x)))return 'LOGIN';return 'WAIT'}catch(e){return 'WAIT'}})()"
	try
		return my runWhatsAppJS(jsCode)
	on error
		return "WAIT"
	end try
end whatsappState

on waitForWhatsAppReady()
	repeat with attempt from 1 to 160
		set s to my whatsappState()
		if s is "READY" then return true
		if s is "LOGIN" then
			display alert "WhatsApp Web richiede l’accesso" message "Completa il collegamento di WhatsApp Web e poi riprova."
			return false
		end if
		delay 0.5
	end repeat
	display alert "WhatsApp Web non pronto" message "La pagina non ha terminato il caricamento entro il tempo previsto."
	return false
end waitForWhatsAppReady

on currentChatMatches(recipientName)
	if recipientName is "" then return false
	try
		set headerText to my runWhatsAppJS("(function(){const root=document.querySelector('#main');if(!root)return '';const h=root.querySelector('header');return h?(h.innerText||h.textContent||''):''})()")
		ignoring case
			if headerText contains recipientName then return true
		end ignoring
	end try
	return false
end currentChatMatches

on searchRecipientByName(recipientName)
	if recipientName is "" then return false
	if not my focusWhatsAppTab() then return false

	my appendLog("Ricerca destinatario: attivo Search all chats con Cmd+Ctrl+/.")

	-- Questa scorciatoia è stata verificata manualmente sul Mac della Mammetta:
	-- porta davvero il cursore dentro "Cerca o avvia una nuova chat".
	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			keystroke "/" using {command down, control down}
		end tell
	end tell
	delay 0.45

	-- v102: NON digitiamo più il nome carattere per carattere.
	-- Dallo screenshot il cursore era nel campo ma il nome non veniva scritto.
	-- Usiamo quindi clipboard + Cmd+V, che su questo Mac è più affidabile.
	set the clipboard to recipientName
	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			keystroke "a" using {command down}
			delay 0.12
			key code 51
			delay 0.12
			keystroke "v" using {command down}
		end tell
	end tell
	delay 0.45

	-- Verifica che il campo attivo contenga davvero il destinatario.
	set typedOK to false
	repeat with attempt from 1 to 20
		set jsCode to "(function(){try{const e=document.activeElement;if(!e)return 'NO';const t=((e.value||e.innerText||e.textContent||'')+'').trim().toLowerCase();return t.includes(" & quoted form of recipientName & ".toLowerCase())?'OK':'NO'}catch(x){return 'NO'}})()"
		-- AppleScript "quoted form" è shell-style e non è valido JS: quindi
		-- usiamo il controllo più semplice sul fatto che il campo non sia vuoto.
		set jsCode to "(function(){try{const e=document.activeElement;if(!e)return 'NO';const t=((e.value||e.innerText||e.textContent||'')+'').trim();return t.length>0?'OK':'NO'}catch(x){return 'NO'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "NO"
		end try
		if jsResult is "OK" then
			set typedOK to true
			exit repeat
		end if
		delay 0.1
	end repeat

	if typedOK then
		my appendLog("Nome incollato correttamente nel campo ricerca.")
	else
		-- Fallback: inserimento diretto nel campo attivo via JavaScript.
		my appendLog("Clipboard non rilevata nel campo: provo inserimento JS diretto.")
		set safeName to recipientName
		-- Il destinatario configurato è un nome semplice; per sicurezza
		-- rimuoviamo eventuali apostrofi che romperebbero la stringa JS.
		set safeName to my replaceText("'", "\\'", safeName)
		set jsCode to "(function(){try{const e=document.activeElement;if(!e)return 'NO';e.focus();if(e.isContentEditable){document.execCommand('selectAll',false,null);document.execCommand('insertText',false,'" & safeName & "');e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:'" & safeName & "'}));}else if('value' in e){const s=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(e),'value');if(s&&s.set)s.set.call(e,'" & safeName & "');else e.value='" & safeName & "';e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));}const t=((e.value||e.innerText||e.textContent||'')+'').trim();return t.length>0?'OK':'NO'}catch(x){return 'NO'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "NO"
		end try
		if jsResult is not "OK" then
			my appendLog("FAIL: non riesco a scrivere nel campo ricerca.")
			return false
		end if
		my appendLog("Nome inserito nel campo ricerca via JavaScript.")
	end if

	delay 0.9

	-- v103: NON ci affidiamo più al solo Enter.
	-- Dopo la ricerca proviamo prima a CLICCARE direttamente il risultato
	-- con il nome esatto; se non riusciamo, usiamo Freccia giù + Enter.
	set resultOpened to false
	repeat with attempt from 1 to 35
		set safeName to my replaceText("'", "\\'", recipientName)
		set jsCode to "(function(){try{const target='" & safeName & "'.trim().toLowerCase();const root=document.querySelector('#side')||document;const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>20&&r.height>12&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...root.querySelectorAll('[title],span,div')].filter(vis);let hit=all.find(e=>((e.getAttribute('title')||'').trim().toLowerCase()===target));if(!hit)hit=all.find(e=>((e.textContent||'').trim().toLowerCase()===target));if(!hit)return 'WAIT';let p=hit;for(let i=0;i<8&&p;i++,p=p.parentElement){const r=p.getBoundingClientRect();const role=(p.getAttribute&&p.getAttribute('role'))||'';const tab=(p.getAttribute&&p.getAttribute('tabindex'))||'';if(r.width>180&&r.height>30&&r.height<180&&(role==='row'||role==='listitem'||role==='button'||tab==='0')){p.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));p.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));p.click();return 'OK'}}hit.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));hit.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));hit.click();return 'OK'}catch(e){return 'WAIT'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try

		if jsResult is "OK" then
			my appendLog("Risultato ricerca cliccato direttamente: " & recipientName)
			exit repeat
		end if
		delay 0.15
	end repeat

	-- Verifica subito se il click ha aperto la chat.
	repeat with attempt from 1 to 25
		if my currentChatMatches(recipientName) then
			set resultOpened to true
			exit repeat
		end if
		delay 0.12
	end repeat

	if not resultOpened then
		my appendLog("Click diretto non confermato: fallback Freccia giù + Enter.")
		-- Il cursore è ancora nel campo Search all chats.
		-- Su WhatsApp Web la Freccia giù seleziona il primo risultato;
		-- Enter lo apre.
		my focusWhatsAppTab()
		tell application "System Events"
			tell process "Google Chrome"
				set frontmost to true
				key code 125
				delay 0.25
				key code 36
			end tell
		end tell

		repeat with attempt from 1 to 60
			if my currentChatMatches(recipientName) then
				set resultOpened to true
				exit repeat
			end if
			delay 0.15
		end repeat
	end if

	if resultOpened then
		my appendLog("Chat verificata correttamente: " & recipientName)
		return true
	end if

	my appendLog("FAIL: risultato trovato ma chat non aperta.")
	return false
end searchRecipientByName

on searchRecipientByPhoneInWhatsApp(recipientPhone)
	if recipientPhone is "" then return false
	if not my focusWhatsAppTab() then return false

	my appendLog("Ricerca WhatsApp per NUMERO ESATTO: " & recipientPhone)
	my appendLog("Attivo Search all chats con Cmd+Ctrl+/.")

	-- Scorciatoia collaudata sul Mac della Mammetta.
	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			keystroke "/" using {command down, control down}
		end tell
	end tell
	delay 0.65

	-- Incolla ESATTAMENTE il numero ricevuto.
	set the clipboard to recipientPhone
	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			keystroke "a" using {command down}
			delay 0.12
			key code 51
			delay 0.12
			keystroke "v" using {command down}
		end tell
	end tell
	delay 0.7

	-- Verifica che il campo Search all chats contenga proprio il numero.
	-- v124: rimossa la restrizione a #side (cerca su tutto il documento).
	-- v125: v124 NON ha risolto — il log è risultato identico a v123, quindi
	-- l'ipotesi "#side" era sbagliata. Aggiungiamo qui una diagnostica a
	-- scaglioni (tentativo 1, 10, 20, 30) che fotografa lo stesso identico
	-- controllo che stiamo eseguendo, per vedere l'evoluzione nel tempo:
	-- il campo è vuoto all'inizio e si popola tardi? Il valore letto da
	-- "wanted" è quello giusto? Ci sono più candidati e stiamo guardando
	-- quello sbagliato? Nessun cambio di comportamento, solo dati reali.
	set typedOK to false
	repeat with attempt from 1 to 30
		set safePhone to my replaceText("'", "\\'", recipientPhone)
		set jsCode to "(function(){try{const wanted='" & safePhone & "'.replace(/\\D/g,'');const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>20&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...document.querySelectorAll('input,[contenteditable=\"true\"],[role=\"textbox\"]')].filter(vis);for(const e of els){const d=((e.value||e.innerText||e.textContent||'')+'').replace(/\\D/g,'');if(d===wanted||d.includes(wanted)){e.focus();return 'OK'}}return 'NO'}catch(x){return 'NO'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "NO"
		end try

		if attempt is 1 or attempt is 10 or attempt is 20 or attempt is 30 then
			set jsCode to "(function(){try{const wanted='" & safePhone & "'.replace(/\\D/g,'');const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>20&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...document.querySelectorAll('input,[contenteditable=\"true\"],[role=\"textbox\"]')];const rows=els.map(e=>{const v=vis(e);const raw=((e.value||e.innerText||e.textContent||'')+'');const d=raw.replace(/\\D/g,'');const match=(d===wanted||d.includes(wanted));return 'tag='+(e.tagName||'').toLowerCase()+',vis='+v+',raw=['+raw.slice(0,20)+'],digits=['+d+'],match='+match}).join(' || ');return 'wanted=['+wanted+'] candidati='+els.length+' :: '+rows}catch(x){return 'ERR:'+x}})()"
			try
				set attemptSnapshot to my runWhatsAppJS(jsCode)
			on error
				set attemptSnapshot to "ERR runWhatsAppJS"
			end try
			my appendLog("DIAGNOSTICA typedOK tentativo " & attempt & "/30: " & attemptSnapshot)
		end if

		if jsResult is "OK" then
			set typedOK to true
			exit repeat
		end if
		delay 0.1
	end repeat

	if not typedOK then
		my appendLog("Numero non rilevato nel Search all chats: provo inserimento JS diretto.")
		set safePhone to my replaceText("'", "\\'", recipientPhone)
		set jsCode to "(function(){try{const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>20&&s.display!=='none'&&s.visibility!=='hidden'};let e=document.activeElement;if(!e||!vis(e)){e=[...document.querySelectorAll('input,[contenteditable=\"true\"],[role=\"textbox\"]')].filter(vis)[0]}if(!e)return 'NO';e.focus();if(e.isContentEditable){document.execCommand('selectAll',false,null);document.execCommand('insertText',false,'" & safePhone & "');e.dispatchEvent(new Event('input',{bubbles:true}));}else if('value' in e){const p=Object.getPrototypeOf(e);const s=Object.getOwnPropertyDescriptor(p,'value');if(s&&s.set)s.set.call(e,'" & safePhone & "');else e.value='" & safePhone & "';e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));}const d=((e.value||e.innerText||e.textContent||'')+'').replace(/\\D/g,'');return d==='" & safePhone & "'?'OK':'NO'}catch(x){return 'NO'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "NO"
		end try
		if jsResult is not "OK" then
			my appendLog("FAIL: non riesco a scrivere il numero nel Search all chats.")

			-- DIAGNOSTICA v123: prima di arrendersi, fotografiamo TUTTI i
			-- campi di testo visibili in pagina (non solo dentro #side,
			-- che potrebbe non esistere più con questa versione di
			-- WhatsApp Web) con tag/ruolo/contenuto, così al prossimo
			-- test sappiamo perché il numero non viene riconosciuto anche
			-- se è visibilmente scritto nella barra di ricerca.
			set jsCode to "(function(){try{const sideExists=!!document.querySelector('#side');const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>20&&r.height>10&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...document.querySelectorAll('input,[contenteditable],[role=\"textbox\"],[role=\"searchbox\"]')];const rows=all.map(e=>{const v=vis(e);const tag=(e.tagName||'').toLowerCase();const role=e.getAttribute('role')||'';const ce=e.getAttribute('contenteditable')||'';const txt=((e.value||e.innerText||e.textContent||'')+'').trim().slice(0,30);return tag+'(role='+role+',ce='+ce+',vis='+v+')=['+txt+']'}).join(' | ');return 'sideExists='+sideExists+' totale='+all.length+' :: '+rows}catch(x){return 'ERR:'+x}})()"
			try
				set diagSnapshot to my runWhatsAppJS(jsCode)
			on error
				set diagSnapshot to "ERR runWhatsAppJS"
			end try
			my appendLog("DIAGNOSTICA campo ricerca non trovato: " & diagSnapshot)

			return false
		end if
	end if

	my appendLog("Numero presente nel Search all chats: " & recipientPhone)
	delay 0.9

	-- v115: NON cerchiamo più il numero dentro la riga risultato.
	-- WhatsApp, se il contatto è salvato, mostra il NOME (es. "Ahmed N. 6").
	-- Poiché la ricerca è fatta col numero esatto, clicchiamo direttamente
	-- il PRIMO vero risultato chat visibile sotto il campo di ricerca.
	set firstResultClicked to false
	repeat with attempt from 1 to 45
		set jsCode to "(function(){try{const root=document.querySelector('#side');if(!root)return 'WAIT';const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>120&&r.height>35&&s.display!=='none'&&s.visibility!=='hidden'};const boxes=[...root.querySelectorAll('input,[contenteditable=\"true\"],[role=\"textbox\"]')].filter(vis);let searchBottom=0;for(const e of boxes){const r=e.getBoundingClientRect();if(r.bottom>searchBottom&&r.top<430)searchBottom=r.bottom}const preferred=[...root.querySelectorAll('[data-testid=\"cell-frame-container\"],[role=\"listitem\"],[role=\"row\"]')].filter(vis).filter(e=>{const r=e.getBoundingClientRect();const t=(e.innerText||e.textContent||'').trim();return r.top>searchBottom+35&&r.height>=45&&r.height<=150&&t.length>0});let hit=preferred[0]||null;if(!hit){const all=[...root.querySelectorAll('[tabindex=\"0\"],div')].filter(vis).filter(e=>{const r=e.getBoundingClientRect();const t=(e.innerText||e.textContent||'').trim();const childTall=[...e.children].some(c=>{const cr=c.getBoundingClientRect();return cr.height>35});return r.top>searchBottom+70&&r.height>=50&&r.height<=135&&r.width>300&&t.length>0&&childTall});hit=all[0]||null}if(!hit)return 'WAIT';let p=hit;for(let i=0;i<6&&p;i++,p=p.parentElement){const r=p.getBoundingClientRect();if(r.width>300&&r.height>=45&&r.height<=170){p.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));p.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));p.click();return 'OK'}}hit.click();return 'OK'}catch(e){return 'WAIT'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "OK" then
			set firstResultClicked to true
			my appendLog("Primo risultato WhatsApp cliccato direttamente.")
			exit repeat
		end if
		delay 0.15
	end repeat

	-- Verifica rapida dopo il click diretto.
	if firstResultClicked then
		repeat with attempt from 1 to 35
			set jsCode to "(function(){try{const root=document.querySelector('#main');if(!root)return 'WAIT';const h=root.querySelector('header');const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>20&&r.height>15&&s.display!=='none'&&s.visibility!=='hidden'};const composer=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].find(vis);return (h&&composer)?'READY':'WAIT'}catch(e){return 'WAIT'}})()"
			try
				set jsResult to my runWhatsAppJS(jsCode)
			on error
				set jsResult to "WAIT"
			end try
			if jsResult is "READY" then
				my appendLog("Chat aperta tramite click diretto sul primo risultato.")
				return true
			end if
			delay 0.12
		end repeat
	end if

	-- Fallback robusto (v122):
	-- La diagnostica di v121 ha confermato sul Mac della Mammetta che dopo
	-- Freccia giù il cursore/focus tastiera RESTA nel campo Search: per
	-- questo SPACE non apriva mai la chat (finiva come carattere nel
	-- campo di ricerca). Mario ha verificato manualmente che il modo che
	-- sposta davvero il focus fuori dal campo di ricerca è: DUE VOLTE TAB
	-- (key code 48), poi SPACE (key code 49). Sostituiamo quindi Freccia
	-- giù con due TAB, mantenendo la stessa verifica del focus reale e la
	-- stessa diagnostica di v121 prima/dopo SPACE, e lo stesso fallback
	-- finale su Return come rete di sicurezza.
	my appendLog("Click diretto non confermato: rifocalizzo Search all chats e passo a doppio TAB + SPACE.")
	set safePhone to my replaceText("'", "\\'", recipientPhone)
	set jsCode to "(function(){try{const wanted='" & safePhone & "'.replace(/\\D/g,'');const root=document.querySelector('#side')||document;const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>20&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...root.querySelectorAll('input,[contenteditable=\"true\"],[role=\"textbox\"]')].filter(vis);const e=els.find(x=>((x.value||x.innerText||x.textContent||'')+'').replace(/\\D/g,'').includes(wanted));if(!e)return 'NO';e.focus();try{e.click()}catch(x){};return 'OK'}catch(x){return 'NO'}})()"
	try
		set jsResult to my runWhatsAppJS(jsCode)
	on error
		set jsResult to "NO"
	end try

	if jsResult is not "OK" then
		my appendLog("WARN: non ho rifocalizzato il campo ricerca; provo comunque TAB+TAB+SPACE.")
	end if

	set resultFocused to false
	repeat with searchAttempt from 1 to 2
		tell application "System Events"
			tell process "Google Chrome"
				set frontmost to true
				key code 48
				delay 0.15
				key code 48
			end tell
		end tell

		-- v122: NON premiamo subito. Osserviamo se il focus tastiera è
		-- davvero uscito dal campo Search (documento.activeElement non è
		-- più l'input di ricerca) prima di premere SPACE, così evitiamo
		-- l'errore di v116 (SPACE troppo presto).
		repeat with focusAttempt from 1 to 20
			set jsCode to "(function(){try{const root=document.querySelector('#side')||document;const e=document.activeElement;if(!e)return 'NO';const tag=(e.tagName||'').toLowerCase();const isField=tag==='input'||e.isContentEditable||e.getAttribute('role')==='textbox';return isField?'NO':'OK'}catch(x){return 'NO'}})()"
			try
				set jsResult to my runWhatsAppJS(jsCode)
			on error
				set jsResult to "NO"
			end try
			if jsResult is "OK" then
				set resultFocused to true
				exit repeat
			end if
			delay 0.1
		end repeat

		-- DIAGNOSTICA v122: prima di premere SPACE, registriamo davvero
		-- COSA ha il focus tastiera e COSA c'è scritto nel campo ricerca.
		-- Non cambiamo la strategia (Space resta Space): raccogliamo solo
		-- i dati che servono a capire, al prossimo test reale, se il tasto
		-- sta finendo sulla riga risultato o (come sospettiamo) resta nel
		-- campo di ricerca perché il focus DOM non si è mai spostato.
		set jsCode to "(function(){try{const e=document.activeElement;if(!e)return 'NONE';const tag=(e.tagName||'').toLowerCase();const role=e.getAttribute('role')||'';const cls=(e.className||'').toString().slice(0,60);const txt=(e.innerText||e.textContent||e.value||'').trim().slice(0,40);return tag+'|role='+role+'|cls='+cls+'|txt='+txt}catch(x){return 'ERR'}})()"
		try
			set activeElementBefore to my runWhatsAppJS(jsCode)
		on error
			set activeElementBefore to "ERR"
		end try
		set jsCode to "(function(){try{const root=document.querySelector('#side')||document;const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>20&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...root.querySelectorAll('input,[contenteditable=\"true\"],[role=\"textbox\"]')].filter(vis);if(!els.length)return 'NONE';const e=els[0];return ((e.value||e.innerText||e.textContent||'')+'').slice(0,40)}catch(x){return 'ERR'}})()"
		try
			set searchBoxBefore to my runWhatsAppJS(jsCode)
		on error
			set searchBoxBefore to "ERR"
		end try
		my appendLog("DIAGNOSTICA prima di SPACE: activeElement=[" & activeElementBefore & "] campoRicerca=[" & searchBoxBefore & "] resultFocused=" & resultFocused)

		if resultFocused then
			my appendLog("Focus tastiera spostato sulla riga risultato: premo SPACE.")
			tell application "System Events"
				tell process "Google Chrome"
					set frontmost to true
					key code 49
				end tell
			end tell
		else
			my appendLog("Focus non confermato sul risultato (tentativo " & searchAttempt & "): premo comunque SPACE dopo attesa.")
			delay 0.3
			tell application "System Events"
				tell process "Google Chrome"
					set frontmost to true
					key code 49
				end tell
			end tell
		end if

		delay 0.15
		set jsCode to "(function(){try{const root=document.querySelector('#side')||document;const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>20&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...root.querySelectorAll('input,[contenteditable=\"true\"],[role=\"textbox\"]')].filter(vis);if(!els.length)return 'NONE';const e=els[0];return ((e.value||e.innerText||e.textContent||'')+'').slice(0,40)}catch(x){return 'ERR'}})()"
		try
			set searchBoxAfter to my runWhatsAppJS(jsCode)
		on error
			set searchBoxAfter to "ERR"
		end try
		if searchBoxAfter is not searchBoxBefore then
			my appendLog("DIAGNOSTICA dopo SPACE: il campo di ricerca È CAMBIATO (prima=[" & searchBoxBefore & "] dopo=[" & searchBoxAfter & "]) — SPACE è probabilmente finito nel campo di ricerca invece che sulla riga.")
		else
			my appendLog("DIAGNOSTICA dopo SPACE: il campo di ricerca è rimasto invariato (" & searchBoxAfter & ").")
		end if

		repeat with attempt from 1 to 30
			if my currentChatMatches(recipientName) then exit repeat
			set jsCode to "(function(){try{const root=document.querySelector('#main');if(!root)return 'WAIT';const h=root.querySelector('header');const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>20&&r.height>15&&s.display!=='none'&&s.visibility!=='hidden'};const composer=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].find(vis);return (h&&composer)?'READY':'WAIT'}catch(e){return 'WAIT'}})()"
			try
				set jsResult to my runWhatsAppJS(jsCode)
			on error
				set jsResult to "WAIT"
			end try
			if jsResult is "READY" then exit repeat
			delay 0.15
		end repeat

		set jsCode to "(function(){try{const root=document.querySelector('#main');if(!root)return 'WAIT';const h=root.querySelector('header');const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>20&&r.height>15&&s.display!=='none'&&s.visibility!=='hidden'};const composer=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].find(vis);return (h&&composer)?'READY':'WAIT'}catch(e){return 'WAIT'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "READY" then
			my appendLog("Chat aperta correttamente con SPACE tramite ricerca numero: " & recipientPhone)
			return true
		end if

		my appendLog("SPACE non ha aperto la chat al tentativo " & searchAttempt & ".")
	end repeat

	-- Rete di sicurezza finale: Return, come nelle versioni precedenti,
	-- nel caso in cui SPACE non fosse disponibile in questa build di
	-- WhatsApp Web (comportamento comunque loggato per la diagnosi).
	my appendLog("SPACE non ha funzionato dopo 2 tentativi: ultimo fallback con Return.")
	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			key code 125
			delay 0.3
			key code 36
		end tell
	end tell

	-- Verifica finale.
	repeat with attempt from 1 to 90
		set jsCode to "(function(){try{const root=document.querySelector('#main');if(!root)return 'WAIT';const h=root.querySelector('header');const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>20&&r.height>15&&s.display!=='none'&&s.visibility!=='hidden'};const composer=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].find(vis);return (h&&composer)?'READY':'WAIT'}catch(e){return 'WAIT'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "READY" then
			my appendLog("Chat aperta correttamente tramite ricerca numero (fallback Return): " & recipientPhone)
			return true
		end if
		delay 0.15
	end repeat

	my appendLog("FAIL: WhatsApp ha mostrato il risultato ma non sono riuscito ad aprire la chat.")
	return false
end searchRecipientByPhoneInWhatsApp


on replaceText(findText, replaceWith, sourceText)
	set AppleScript's text item delimiters to findText
	set textItems to text items of sourceText
	set AppleScript's text item delimiters to replaceWith
	set newText to textItems as text
	set AppleScript's text item delimiters to ""
	return newText
end replaceText

on openRecipientByPhone(recipientPhone)
	if recipientPhone is "" then return false
	if not my focusWhatsAppTab() then return false

	my appendLog("ATTENZIONE: handler URL obsoleto richiamato: " & recipientPhone)

	tell application "Google Chrome"
		repeat with w in windows
			repeat with i from 1 to (count of tabs of w)
				try
					if (URL of tab i of w) contains "web.whatsapp.com" then
						set active tab index of w to i
						set index of w to 1
						set URL of tab i of w to "https://web.whatsapp.com/send?phone=" & recipientPhone
						activate
						exit repeat
					end if
				end try
			end repeat
		end repeat
	end tell

	repeat with attempt from 1 to 160
		delay 0.25
		try
			set jsResult to my runWhatsAppJS("(function(){try{const t=(document.body&&document.body.innerText||'').toLowerCase();if(t.includes('phone number shared via url is invalid')||t.includes('numero di telefono')&&t.includes('non valido'))return 'INVALID';const root=document.querySelector('#main');const h=root&&root.querySelector('header');return (root&&h)?'READY':'WAIT'}catch(e){return 'WAIT'}})()")
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "READY" then
			my appendLog("Chat aperta tramite numero WhatsApp.")
			return true
		end if
		if jsResult is "INVALID" then
			my appendLog("FAIL: numero WhatsApp non valido.")
			return false
		end if
	end repeat

	my appendLog("FAIL: timeout apertura chat tramite numero.")
	return false
end openRecipientByPhone

on recordSuccess(pdfName)
	try
		set ts to do shell script "/bin/date '+%Y-%m-%dT%H:%M:%S%z'"
		do shell script "/usr/bin/printf '%s\\t%s\\n' " & quoted form of ts & " " & quoted form of pdfName & " >> " & quoted form of sentLogPath
	end try
end recordSuccess

on performSend(pdfPath, messageText, recipientName, recipientPhone)
	my openWhatsAppOnlyIfMissing()
	if not my waitForWhatsAppReady() then return "FAIL:READY"

	my focusWhatsAppTab()

	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			key code 53
		end tell
	end tell
	delay 0.15

	-- v114: ripristinato il meccanismo WhatsApp collaudato.
	-- NON usiamo URL diretti e NON usiamo il Trova di Chrome:
	-- Cmd+Ctrl+/ apre Search all chats e lì incolliamo il NUMERO.
	if recipientPhone is "" then
		display alert "Numero WhatsApp mancante" message "Non posso inviare la ricevuta perché per “" & recipientName & "” non è disponibile un numero WhatsApp."
		return "FAIL:NOPHONE"
	end if

	if not my searchRecipientByPhoneInWhatsApp(recipientPhone) then
		display alert "Chat non trovata" message "Non riesco ad aprire automaticamente la chat WhatsApp cercando il numero " & recipientPhone & " nel campo Search all chats."
		return "FAIL:CHAT"
	end if

	my appendLog("Destinatario selezionato tramite Search all chats: " & recipientPhone & " (" & recipientName & ")")
	my focusWhatsAppTab()
	delay 0.35

	set attachReady to false
	repeat with attempt from 1 to 40
		set jsCode to "(function(){const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>5&&r.height>5&&s.display!=='none'&&s.visibility!=='hidden'};const root=document.querySelector('#main');if(!root)return 'WAIT';const els=[...root.querySelectorAll('button,[role=\"button\"],[aria-label],[title]')].filter(vis);const wanted=['attach','allega','allegato','allegati'];const el=els.find(e=>{const s=((e.getAttribute('aria-label')||'')+' '+(e.getAttribute('title')||'')+' '+(e.textContent||'')).toLowerCase();return wanted.some(w=>s.includes(w))});if(el){el.click();return 'OK'}return 'WAIT'})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error errMsg
			display alert "Chrome blocca l’automazione" message "In Chrome deve essere attivo:" & return & return & "View → Developer → Allow JavaScript from Apple Events" & return & return & errMsg
			return "FAIL:JS"
		end try
		if jsResult is "OK" then
			set attachReady to true
			exit repeat
		end if
		delay 0.2
	end repeat

	if not attachReady then
		display alert "Pulsante Allega non trovato" message "Ho aperto la chat corretta, ma non trovo il pulsante Allega."
		return "FAIL:ATTACH"
	end if
	my appendLog("Pulsante Allega aperto.")

	my focusWhatsAppTab()
	tell application "System Events"
		tell process "Google Chrome"
			set initialWindowCount to count of windows
		end tell
	end tell

	set documentReady to false
	repeat with attempt from 1 to 30
		set jsCode to "(function(){const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>7&&r.height>7&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...document.querySelectorAll('[role=\"menuitem\"],[role=\"button\"],button,[tabindex=\"0\"]')].filter(vis);const el=els.find(e=>{const s=((e.innerText||'')+' '+(e.textContent||'')+' '+(e.getAttribute('aria-label')||'')).trim().toLowerCase();return s==='documento'||s==='document'||s.includes('documento')||s.includes('document')});if(el){el.click();return 'OK'}return 'WAIT'})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "OK" then
			set documentReady to true
			exit repeat
		end if
		delay 0.15
	end repeat

	if not documentReady then
		display alert "Documento non trovato" message "Il menu Allega si è aperto, ma non trovo la voce Documento."
		return "FAIL:DOCUMENT"
	end if
	my appendLog("Voce Documento selezionata.")

	-- v105: selezione PDF + verifica REALE dell'anteprima.
	-- Non dichiariamo più "PDF inviato" solo perché troviamo un generico
	-- pulsante Invia nella pagina.
	set pdfNameOnly to do shell script "/usr/bin/basename " & quoted form of pdfPath
	set safePdfName to my replaceText("'", "\\'", pdfNameOnly)

	my appendLog("Attendo il selettore file senza rifocalizzare WhatsApp.")
	delay 1.0

	set the clipboard to pdfPath
	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			keystroke "g" using {command down, shift down}
			delay 0.45
			keystroke "v" using {command down}
			delay 0.35
			key code 36
			delay 0.9
			key code 36
		end tell
	end tell
	my appendLog("Percorso PDF passato al selettore macOS: " & pdfPath)

	-- Prima prova: l'anteprima deve mostrare proprio il NOME DI QUESTO PDF.
	set previewReady to false
	repeat with attempt from 1 to 100
		set jsCode to "(function(){try{const name='" & safePdfName & "';const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>5&&r.height>5&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...document.querySelectorAll('body *')].filter(vis);const hit=all.find(e=>{const t=((e.getAttribute&&e.getAttribute('title'))||e.textContent||'').trim();return t===name||t.includes(name)});return hit?'READY':'WAIT'}catch(e){return 'WAIT'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "READY" then
			set previewReady to true
			exit repeat
		end if
		delay 0.15
	end repeat

	if not previewReady then
		my appendLog("FAIL: anteprima PDF non comparsa: " & pdfNameOnly)
		display alert "Anteprima PDF non comparsa" message "WhatsApp non ha caricato il PDF dopo la selezione:" & return & return & pdfNameOnly & return & return & "Quindi NON considero il documento inviato."
		return "FAIL:PDFPREVIEW"
	end if
	my appendLog("Anteprima PDF verificata: " & pdfNameOnly)

	-- Seconda prova: troviamo il pulsante INVIA collegato all'anteprima che
	-- contiene il nome del PDF. Lo marchiamo, così possiamo poi verificare
	-- che quella specifica anteprima sia realmente scomparsa.
	set previewSendClicked to false
	repeat with attempt from 1 to 80
		set jsCode to "(function(){try{const name='" & safePdfName & "';const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>7&&r.height>7&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...document.querySelectorAll('body *')].filter(vis);const hit=all.find(e=>{const t=((e.getAttribute&&e.getAttribute('title'))||e.textContent||'').trim();return t===name||t.includes(name)});if(!hit)return 'WAIT';let p=hit;for(let depth=0;depth<14&&p;depth++,p=p.parentElement){const buttons=[...p.querySelectorAll('button,[role=\"button\"],[aria-label],[title]')].filter(vis);const send=buttons.find(e=>{const t=((e.getAttribute('aria-label')||'')+' '+(e.getAttribute('title')||'')+' '+(e.textContent||'')).trim().toLowerCase();return t==='invia'||t==='send'||t==='invia messaggio'||t==='send message'||t.includes('invia')||t.includes('send')});if(send){send.setAttribute('data-cruscotto-pdf-send','1');send.click();return 'OK'}}return 'WAIT'}catch(e){return 'WAIT'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "OK" then
			set previewSendClicked to true
			exit repeat
		end if
		delay 0.15
	end repeat

	if not previewSendClicked then
		my appendLog("FAIL: pulsante Invia dell'anteprima PDF non trovato.")
		display alert "Invio PDF non trovato" message "L’anteprima del PDF è comparsa, ma non trovo il pulsante Invia appartenente a quell’anteprima."
		return "FAIL:PDFSEND"
	end if
	my appendLog("Clic sul pulsante Invia dell'anteprima PDF.")

	-- Terza prova: la SPECIFICA anteprima deve chiudersi.
	set previewClosed to false
	repeat with attempt from 1 to 120
		set jsCode to "(function(){try{const e=document.querySelector('[data-cruscotto-pdf-send=\"1\"]');if(!e)return 'CLOSED';const r=e.getBoundingClientRect();const s=getComputedStyle(e);return (r.width<2||r.height<2||s.display==='none'||s.visibility==='hidden')?'CLOSED':'WAIT'}catch(x){return 'WAIT'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "CLOSED" then
			set previewClosed to true
			exit repeat
		end if
		delay 0.15
	end repeat

	if not previewClosed then
		my appendLog("FAIL: anteprima PDF non si è chiusa dopo Invia.")
		display alert "PDF non confermato" message "Ho premuto Invia nell’anteprima, ma l’anteprima non si è chiusa. Non considero il PDF inviato."
		return "FAIL:PDFPREVIEWCLOSE"
	end if

	-- Quarta prova: dopo la chiusura dell'anteprima il nome del PDF deve
	-- comparire nella conversazione. SOLO ORA scriviamo "PDF inviato".
	set pdfReallySent to false
	repeat with attempt from 1 to 160
		set jsCode to "(function(){try{const name='" & safePdfName & "';const main=document.querySelector('#main');if(!main)return 'WAIT';const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>5&&r.height>5&&s.display!=='none'&&s.visibility!=='hidden'};const candidates=[...main.querySelectorAll('[data-testid=\"msg-container\"],[role=\"row\"],[title],span,div')].filter(vis);const hit=candidates.find(e=>{const t=((e.getAttribute&&e.getAttribute('title'))||e.textContent||'').trim();if(!(t===name||t.includes(name)))return false;return !e.closest('[role=\"dialog\"]')});return hit?'SENT':'WAIT'}catch(e){return 'WAIT'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "SENT" then
			set pdfReallySent to true
			exit repeat
		end if
		delay 0.15
	end repeat

	if not pdfReallySent then
		my appendLog("FAIL: il nome del PDF non compare nella conversazione dopo Invio.")
		display alert "PDF non inviato" message "L’anteprima si è chiusa, ma non trovo il documento nella conversazione:" & return & return & pdfNameOnly & return & return & "Quindi interrompo prima di scrivere il messaggio."
		return "FAIL:PDFNOTINCHAT"
	end if

	my appendLog("PDF REALMENTE inviato e verificato nella chat: " & pdfNameOnly)

	-- Solo dopo la verifica reale del PDF attendiamo il composer.
	set chatReadyAfterPdf to false
	repeat with attempt from 1 to 100
		set jsCode to "(function(){const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>8&&r.height>8&&s.display!=='none'&&s.visibility!=='hidden'};const root=document.querySelector('#main');if(!root)return 'WAIT';const composers=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].filter(vis);return composers.length>0?'READY':'WAIT'})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "READY" then
			set chatReadyAfterPdf to true
			exit repeat
		end if
		delay 0.15
	end repeat

	if not chatReadyAfterPdf then
		display alert "Campo messaggio non pronto" message "Il PDF è stato verificato nella chat, ma WhatsApp non è tornato al campo messaggio."
		return "FAIL:COMPOSER"
	end if

	set composerReady to false
	repeat with attempt from 1 to 40
		set jsCode to "(function(){const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>18&&s.display!=='none'&&s.visibility!=='hidden'};const root=document.querySelector('#main');if(!root)return 'WAIT';const all=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].filter(vis);if(!all.length)return 'WAIT';all[0].focus();return 'OK'})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "OK" then
			set composerReady to true
			exit repeat
		end if
		delay 0.1
	end repeat

	if not composerReady then
		display alert "Campo messaggio non trovato" message "Il PDF è stato inviato, ma non trovo il campo messaggio."
		return "FAIL:MESSAGEBOX"
	end if

	set fullMessage to messageText
	set the clipboard to fullMessage

	-- v104: il composer era stato trovato e focalizzato correttamente,
	-- ma v103 chiamava focusWhatsAppTab() SUBITO DOPO, prima di Cmd+V.
	-- Su Chrome 116 questo può togliere il focus DOM dal campo messaggio.
	-- Ora ogni tentativo rifocalizza il composer via JS e incolla SENZA
	-- richiamare focusWhatsAppTab() nel mezzo.
	set textReady to false
	repeat with pasteAttempt from 1 to 5
		set jsCode to "(function(){const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>18&&s.display!=='none'&&s.visibility!=='hidden'};const root=document.querySelector('#main');if(!root)return 'WAIT';const all=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].filter(vis);if(!all.length)return 'WAIT';const el=all[0];el.focus();try{el.click()}catch(e){};return 'OK'})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try

		if jsResult is "OK" then
			delay 0.18
			tell application "System Events"
				tell process "Google Chrome"
					set frontmost to true
					keystroke "v" using {command down}
				end tell
			end tell
			delay 0.4
		end if

		set jsCode to "(function(){const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>18&&s.display!=='none'&&s.visibility!=='hidden'};const root=document.querySelector('#main');if(!root)return 'WAIT';const all=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].filter(vis);if(!all.length)return 'WAIT';const el=all[0];const txt=(el.value||el.innerText||el.textContent||'').trim();return txt.includes('Benetti')?'READY':'WAIT'})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try

		if jsResult is "READY" then
			set textReady to true
			my appendLog("Messaggio incollato correttamente nel composer.")
			exit repeat
		end if

		my appendLog("Tentativo incolla messaggio non riuscito: " & pasteAttempt)
		delay 0.2
	end repeat

	if not textReady then
		display alert "Messaggio non scritto" message "Il PDF è stato inviato, ma il testo non è comparso nel campo messaggio dopo 5 tentativi."
		return "FAIL:TEXT"
	end if

	set messageSent to false
	repeat with attempt from 1 to 40
		set jsCode to "(function(){const root=document.querySelector('#main');if(!root)return 'WAIT';const footer=root.querySelector('footer');if(!footer)return 'WAIT';const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>8&&r.height>8&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...footer.querySelectorAll('button,[role=\"button\"],[aria-label],[title]')].filter(vis);const el=els.find(e=>{const t=((e.getAttribute('aria-label')||'')+' '+(e.getAttribute('title')||'')+' '+(e.textContent||'')).trim().toLowerCase();return t==='invia'||t==='send'||t.includes('invia messaggio')||t.includes('send message')});if(!el)return 'WAIT';el.click();return 'OK'})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "OK" then
			set messageSent to true
			exit repeat
		end if
		delay 0.1
	end repeat

	if not messageSent then
		my focusWhatsAppTab()
		tell application "System Events"
			tell process "Google Chrome"
				key code 36
			end tell
		end tell
	end if

	set sendConfirmed to false
	repeat with attempt from 1 to 60
		set jsCode to "(function(){const root=document.querySelector('#main');if(!root)return 'WAIT';const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>18&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].filter(vis);if(!all.length)return 'WAIT';const txt=(all[0].value||all[0].innerText||all[0].textContent||'').trim();return txt.includes('Benetti')?'WAIT':'SENT'})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "SENT" then
			set sendConfirmed to true
			exit repeat
		end if
		delay 0.15
	end repeat

	if sendConfirmed then return "SUCCESS"
	return "FAIL:CONFIRM"
end performSend

on run
	try
		do shell script "/usr/bin/touch " & quoted form of runLogPath
		my appendLog("=== Avvio Engine WhatsApp v125 ===")

		set pdfName to my readTextFile(pointerPath)
		set messageText to my readTextFile(messagePath)
		set recipientName to my getRecipientName()
		set recipientPhone to my getRecipientPhone()

		if pdfName is "" then
			display alert "Ricevuta non preparata" message "Ricevuta_Da_Inviare.txt è vuoto."
			my appendLog("FAIL: pointer vuoto")
			return
		end if

		set pdfPath to dataDir & "/" & pdfName
		try
			do shell script "/bin/test -f " & quoted form of pdfPath
		on error errMsg
			display alert "PDF non trovato" message "Non trovo:" & return & return & pdfPath & return & return & "Dettaglio tecnico: " & errMsg
			my appendLog("FAIL controllo PDF: " & errMsg & " | " & pdfPath)
			return
		end try

		my appendLog("PDF: " & pdfName)
		my appendLog("Destinatario: " & recipientName & " | telefono: " & recipientPhone)

		set resultText to my performSend(pdfPath, messageText, recipientName, recipientPhone)
		my appendLog("Risultato: " & resultText)

		if resultText is "SUCCESS" then
			my recordSuccess(pdfName)
			my appendLog("SUCCESS: PDF e messaggio inviati.")
		end if
	on error errMsg number errNum
		my appendLog("ERRORE " & errNum & ": " & errMsg)
		display alert "Automazione WhatsApp interrotta" message errMsg
	end try
end run


___CRUSCOTTO_PAYLOAD_APPLESCRIPT_9f3c1a___

cat > "$PAYLOAD_DIR/Generatore_Ricevute_Condominio_v120.html" <<'___CRUSCOTTO_PAYLOAD_HTML_9f3c1a___'
<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Cruscotto Affitti - Generatore Ricevute</title>
<link rel="icon" type="image/png" href="data:image/png;base64,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">
<link rel="apple-touch-icon" href="data:image/png;base64,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">
<style>
  *{box-sizing:border-box}
  body{margin:0;font-family:Arial,Helvetica,sans-serif;background:#ececec;color:#171717}
  .app{
    display:grid;
    grid-template-columns:minmax(320px,var(--panel-width,390px)) 8px minmax(0,1fr);
    min-height:100vh
  }
  .panel{background:#fff;padding:22px;overflow:auto;min-width:0;position:relative}
  .splitter{
    background:#d1d1d1;
    cursor:col-resize;
    position:relative;
    touch-action:none;
  }
  .splitter::after{
    content:"";
    position:absolute;
    top:0;
    bottom:0;
    left:3px;
    width:2px;
    background:#aaa;
  }
  .splitter:hover,.splitter.dragging{background:#bdbdbd}
  h1{font-size:21px;margin:0}
  .app-title-row{display:flex;align-items:center;gap:10px;margin:0 0 16px}
  .app-title-row h1{flex:1}
  .title-actions{display:flex;align-items:center;gap:6px;flex:0 0 auto}
  .settings-button{
    flex:0 0 38px;width:38px;height:38px;margin:0;padding:0;
    border:1px solid #999;border-radius:9px;background:#f2f2f2;
    color:#222;font-size:22px;line-height:36px;cursor:pointer
  }
  .settings-button:hover{background:#e2e2e2}
  .settings-modal{
    position:fixed;inset:0;display:none;align-items:center;justify-content:center;
    z-index:10000;padding:20px;background:rgba(0,0,0,.55)
  }
  .settings-modal.open{display:flex}
  .settings-card{
    width:min(1180px,97vw);background:#fff;border-radius:13px;
    box-shadow:0 14px 45px rgba(0,0,0,.35);overflow:hidden
  }
  .settings-header{
    display:flex;align-items:center;justify-content:space-between;gap:12px;
    padding:14px 16px;background:#f1f1f1;border-bottom:1px solid #ccc
  }
  .settings-title{font-size:17px;font-weight:800}
  .settings-close{width:auto;margin:0;padding:7px 12px;background:#111;color:#fff}
  .settings-content{padding:18px;max-height:78vh;overflow:auto}
  .tenant-setup{margin-top:18px}
  .tenant-setup-title{font-size:15px;font-weight:800;margin:0 0 8px}
  .tenant-setup-table{
    border:2px solid #9bb8ce;
    border-radius:8px;
    overflow:hidden;
    background:#fff;
  }
  #tenantSetupRows{display:block}
  .tenant-setup-head,.tenant-setup-row{
    display:grid;grid-template-columns:1.15fr .62fr 1.55fr .52fr .82fr;gap:7px;align-items:center;padding:7px 8px;
  }
  .tenant-setup-head{background:#eee;font-size:11px;font-weight:800;text-transform:uppercase}
  .tenant-setup-row{border-top:1px solid #eee}
  .tenant-setup-row input{margin:0;padding:7px 8px;font-size:12px}
  .setup-save{margin-top:10px;background:#1f6f43;color:#fff;font-weight:800}
  .setup-save:hover{background:#185b37}
  .whatsapp-force-box{
    margin:10px 0 12px;
    padding:10px 12px;
    border:2px solid #d9a441;
    border-radius:9px;
    background:#fff8e8;
  }
  .whatsapp-force-label{
    display:flex;
    align-items:center;
    gap:10px;
    font-weight:800;
    cursor:pointer;
    margin:0;
  }
  .whatsapp-force-label input[type="checkbox"]{
    width:19px;
    height:19px;
    margin:0;
    padding:0;
    flex:0 0 auto;
  }
  .whatsapp-force-note{
    margin-top:6px;
    font-size:12px;
    color:#674d16;
  }
  .period-group{
    margin:14px 0 10px;
    padding:12px 12px 10px;
    border:2px solid #69aee6;
    border-radius:10px;
    background:#f8fcff;
  }
  .period-group legend{
    padding:0 8px;
    font-weight:800;
    color:#1f4f73;
    font-size:13px;
  }
  .month-year-row{
    display:grid;
    grid-template-columns:minmax(0,1fr) 165px;
    gap:9px;
    align-items:end;
  }
  .year-stepper{
    display:grid;
    grid-template-columns:32px minmax(78px,1fr) 32px;
    gap:4px;
    align-items:center;
  }
  .year-btn{
    width:32px;
    height:36px;
    margin:0;
    padding:0;
    border:2px solid #69aee6;
    border-radius:7px;
    background:#eaf5ff;
    color:#194d72;
    font-size:22px;
    font-weight:800;
    line-height:30px;
    cursor:pointer;
  }
  .year-btn:hover{background:#cfeaff}
  #annoRiferimento{
    background:#cfeaff !important;
    border:2px solid #69aee6 !important;
    text-align:center;
    font-weight:700;
    height:36px;
  }
  #annoRiferimento:focus{
    outline:2px solid #9cc9ee;
    outline-offset:1px;
  }

  .period-choice{
    display:grid;
    grid-template-columns:1fr 1fr;
    gap:8px;
    margin:2px 0 12px;
  }
  .period-choice-btn{
    margin:0;
    padding:10px 8px;
    border:2px solid #9eb7c9;
    border-radius:9px;
    background:#f1f4f6;
    color:#333;
    font-weight:800;
    font-size:13px;
  }
  .period-choice-btn.active{
    background:#cfeaff;
    border-color:#4c9bd4;
    color:#123e5e;
    box-shadow:inset 0 0 0 1px rgba(255,255,255,.7);
  }

  .section-toggle{
    width:100%;margin:10px 0 8px;padding:9px 11px;
    border:1px solid #aaa;border-radius:8px;background:#f4f4f4;
    color:#222;font-weight:700;text-align:left;cursor:pointer;
  }
  .section-toggle:hover{background:#e9e9e9}
  .section-toggle .arrow{display:inline-block;width:18px;transition:transform .15s ease}
  .section-toggle.open .arrow{transform:rotate(90deg)}
  .range-mode{display:none}
  .range-inline-row{
    display:grid;
    grid-template-columns:minmax(125px,1fr) 158px minmax(125px,1fr) 158px;
    gap:8px;
    align-items:end;
  }
  .range-month-cell,.range-year-cell{min-width:0}
  .range-inline-row label{white-space:nowrap}
  .range-year-stepper{
    grid-template-columns:30px minmax(70px,1fr) 30px;
    gap:3px;
  }
  .range-year-stepper .year-btn{width:30px}
  #meseDal,#meseAl,#annoDal,#annoAl{
    background:#cfeaff !important;
    border:2px solid #69aee6 !important;
  }
  #annoDal,#annoAl{text-align:center;font-weight:700;height:36px}
  @media(max-width:700px){
    .range-inline-row{
      grid-template-columns:minmax(110px,1fr) 150px minmax(110px,1fr) 150px;
      overflow-x:auto;
      padding-bottom:4px;
    }
  }
  .range-mode.open{display:block}
  .box-quarter-controls{
    display:none;
    grid-template-columns:42px minmax(0,1fr) 42px;
    gap:8px;
    align-items:center;
    margin-top:11px;
    padding:9px 10px;
    border:2px solid #79b98a;
    border-radius:9px;
    background:#f2fff5;
  }
  .box-quarter-controls.open{display:grid}
  .box-quarter-btn{
    width:42px;
    height:38px;
    margin:0;
    padding:0;
    border:2px solid #62a876;
    border-radius:8px;
    background:#e3f7e8;
    color:#245c34;
    font-size:25px;
    font-weight:900;
    line-height:30px;
    cursor:pointer;
  }
  .box-quarter-btn:hover{background:#ccefd5}
  .box-quarter-center{
    text-align:center;
    min-width:0;
  }
  .box-quarter-title{
    font-size:12px;
    font-weight:900;
    color:#245c34;
    margin-bottom:2px;
  }
  .box-quarter-label{
    font-size:14px;
    font-weight:900;
    color:#183f24;
  }
  .box-quarter-note{
    font-size:10px;
    color:#54725d;
    margin-top:2px;
  }
  .receipts-section{display:none}
  .receipts-section.open{display:block}
  .date-clear-wrap{
    display:grid;grid-template-columns:minmax(0,1fr) 32px;gap:5px;align-items:center
  }
  .clear-date-btn{
    width:32px;height:34px;margin:0;padding:0;border:1px solid #aaa;
    border-radius:7px;background:#f3f3f3;color:#444;font-size:20px;line-height:30px
  }
  .clear-date-btn:hover{background:#ffe0de}
  h2{font-size:15px;margin:20px 0 8px}
  .advanced-toggle{
    width:100%;
    margin:0 0 14px;
    padding:10px 12px;
    border:1px solid #888;
    border-radius:8px;
    background:#eeeeee;
    color:#222;
    font-weight:700;
  }
  .advanced-toggle:hover{background:#e2e2e2}
  .compact-toggle{
    width:auto;
    min-width:0;
    margin:0;
    padding:8px 10px;
    white-space:nowrap;
    font-size:12px;
    line-height:20px;
  }
  .compact-new-receipt{
    width:auto;
    min-width:0;
    margin:0;
    padding:8px 10px;
    white-space:nowrap;
    font-size:12px;
    line-height:20px;
  }

  /* v113: i quattro passi devono essere immediatamente riconoscibili. */
  .step-label{
    margin-top:13px;
    margin-bottom:5px;
    font-size:13px;
    font-weight:800;
    color:#222;
  }
  .step-number{
    display:inline-block;
    color:#ff1684;
    background:#fff0f7;
    border:2px solid #ff1684;
    border-radius:7px;
    padding:2px 7px;
    margin-right:4px;
    font-size:16px;
    line-height:1.15;
    font-weight:950;
    letter-spacing:.2px;
    box-shadow:0 1px 0 rgba(255,22,132,.15);
  }
  .final-step-button{
    font-size:14px;
    line-height:1.35;
    padding:11px 10px;
  }
  .final-step-button .step-number{
    vertical-align:middle;
    margin-right:3px;
  }
  .final-step-button .conclusive-word{
    color:#ff3b00;
    font-size:16px;
    font-weight:950;
    letter-spacing:.3px;
  }
  .advanced-fields{display:none}
  .panel.show-advanced .advanced-fields{display:block}
  label{display:block;font-size:12px;font-weight:700;margin:10px 0 4px}
  input,select{width:100%;padding:9px 10px;border:1px solid #aaa;border-radius:7px;font-size:14px;background:#fff}
  #tenantPickerButton,
  #importo,
  #dataPagamento,
  #meseRiferimento{
    background:#cfeaff !important;
    border:2px solid #69aee6 !important;
    box-shadow:inset 0 0 0 1px rgba(255,255,255,.55);
  }
  #tenantPickerButton:focus,
  #importo:focus,
  #dataPagamento:focus,
  #meseRiferimento:focus{
    outline:2px solid #9cc9ee;
    outline-offset:1px;
  }
  .row{display:grid;grid-template-columns:1fr 1fr;gap:9px}
  .path-row{display:grid;grid-template-columns:1fr 92px;gap:7px}
  .keyboard-select{display:none !important}

  .tenant-picker{display:block !important;position:relative}
  .tenant-picker.keyboard-active #tenantPickerButton{
    outline:3px solid #ffbf47 !important;
    outline-offset:2px;
  }
  .tenant-picker-button{
    width:100%;
    margin:0;
    padding:9px 32px 9px 10px;
    border:1px solid #aaa;
    border-radius:7px;
    background:#fff;
    color:#171717;
    font-size:14px;
    text-align:left;
    position:relative;
  }
  .tenant-picker-button::after{
    content:"▾";
    position:absolute;
    right:11px;
    top:50%;
    transform:translateY(-50%);
  }
  .tenant-menu{
    display:none;
    position:absolute;
    left:0;
    top:calc(100% + 4px);
    z-index:5000;
    background:#fff;
    border:1px solid #999;
    border-radius:8px;
    box-shadow:0 8px 24px rgba(0,0,0,.22);
    overflow:hidden;
    width:max-content;
    min-width:100%;
    max-width:min(980px,calc(100vw - 40px));
  }
  .tenant-menu.open{display:block}
  .tenant-head,.tenant-row{
    display:grid;
    grid-template-columns:minmax(210px,1.2fr) minmax(95px,.55fr) minmax(300px,1.75fr) minmax(85px,.48fr) minmax(145px,.8fr);
    gap:12px;
    align-items:center;
  }
  .tenant-head{
    padding:8px 10px;
    background:#ececec;
    border-bottom:1px solid #bbb;
    font-size:11px;
    font-weight:700;
    text-transform:uppercase;
  }
  #tenantRows{max-height:330px;overflow:auto;outline:none}
  #tenantRows:focus{box-shadow:inset 0 0 0 2px #69aee6}
  .tenant-row{
    padding:8px 10px;
    font-size:13px;
    cursor:pointer;
    border-bottom:1px solid #eee;
  }
  .tenant-row:last-child{border-bottom:0}
  .tenant-row:hover{background:#e8f0fe}
  .tenant-row.selected{background:#d8e7ff;font-weight:700}
  .tenant-menu.open #tenantRows::before{
    content:"↑ ↓ cambia affittuario • Invio conferma • Esc chiude";
    display:block;
    position:sticky;
    top:0;
    z-index:2;
    padding:5px 10px;
    background:#fff8d6;
    border-bottom:1px solid #e0cf7a;
    font-size:11px;
    color:#665800;
  }
  @media(max-width:850px){
    .tenant-menu{min-width:100%}
    .tenant-head,.tenant-row{grid-template-columns:1.1fr .65fr 1.35fr .55fr .85fr}
  }
  button{padding:10px;border:0;border-radius:8px;font-size:14px;cursor:pointer}
  .primary{background:#111;color:#fff}
  .secondary{background:#ddd;color:#111}
  .new-receipt{
    background:#ffe08a;
    color:#222;
    border:1px solid #d7ad35;
    font-weight:800;
  }
  .new-receipt:hover{background:#ffd45c}
  .existing-receipt-banner{
    display:none;
    margin:10px 0 8px;
    padding:9px 11px;
    border:1px solid #d59b2a;
    border-radius:8px;
    background:#fff1c7;
    color:#664400;
    font-size:12px;
    line-height:1.35;
  }
  .existing-receipt-banner.open{display:block}
  .existing-receipt-banner strong{font-weight:900}
  .existing-choice-modal{
    position:fixed;
    inset:0;
    background:rgba(0,0,0,.58);
    display:none;
    align-items:center;
    justify-content:center;
    z-index:15000;
    padding:20px;
  }
  .existing-choice-modal.open{display:flex}
  .existing-choice-card{
    width:min(560px,94vw);
    background:#fff;
    border-radius:14px;
    padding:20px;
    box-shadow:0 16px 50px rgba(0,0,0,.35);
  }
  .existing-choice-title{
    font-size:20px;
    font-weight:900;
    margin-bottom:8px;
  }
  .existing-choice-file{
    margin:10px 0 14px;
    padding:8px 10px;
    border-radius:7px;
    background:#f3f3f3;
    font-size:11px;
    overflow-wrap:anywhere;
  }
  .existing-choice-actions{
    display:grid;
    grid-template-columns:1fr 1fr;
    gap:8px;
    margin-top:16px;
  }
  .existing-choice-new{
    background:#ffe08a;
    border:1px solid #d7ad35;
    color:#222;
    font-weight:900;
  }
  .existing-choice-edit{
    background:#111;
    color:#fff;
    font-weight:800;
  }
  .existing-choice-cancel{
    grid-column:1 / -1;
    background:#e5e5e5;
    color:#222;
  }
  .actions{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:15px}
  .wide{width:100%;margin-top:8px}
  .status{font-size:12px;color:#555;margin-top:8px;min-height:18px}
  .file-list{
    border:1px solid #bbb;
    border-radius:7px;
    background:#fafafa;
    max-height:220px;
    overflow-y:scroll;
    overflow-x:hidden;
    scrollbar-gutter:stable;
    padding:5px;
    font-size:12px
  }
  .file-list::-webkit-scrollbar{width:12px}
  .file-list::-webkit-scrollbar-track{background:#ececec;border-radius:8px}
  .file-list::-webkit-scrollbar-thumb{background:#999;border-radius:8px;border:2px solid #ececec}
  .file-list::-webkit-scrollbar-thumb:hover{background:#777}
  .receipt-stats{
    margin-top:5px;
    padding:2px 4px;
    font-size:11px;
    color:#666;
    text-align:right;
  }
  .file-item{
    padding:0;
    border-radius:5px;
    cursor:default;
    user-select:none;
    display:grid;
    grid-template-columns:minmax(0,1fr) 130px 34px 34px;
    align-items:center;
    overflow:hidden;
  }
  .file-item:hover{background:#e8e8e8}
  .file-item.selected{background:#d8d8d8;font-weight:700}
  .file-name{
    padding:7px 8px;
    white-space:nowrap;
    overflow:hidden;
    text-overflow:ellipsis;
  }
  .trash-btn{
    width:30px;
    height:30px;
    margin:2px;
    padding:0;
    border:0;
    border-radius:6px;
    background:transparent;
    font-size:17px;
    line-height:30px;
    cursor:pointer;
  }
  .trash-btn:hover{background:#ffd9d6}
  .receipt-filters{
    display:grid;
    grid-template-columns:minmax(0,1fr) 175px;
    gap:8px;
    margin:8px 0;
  }
  .receipt-filter-box label{
    display:block;
    margin:0 0 4px 0;
    font-size:11px;
    font-weight:700;
    color:#555;
  }
  .receipt-filter-box input,
  .receipt-filter-box select{
    width:100%;
    margin:0;
    padding:7px 8px;
    font-size:12px;
  }
  .receipt-list-head{
    display:grid;
    grid-template-columns:minmax(0,1fr) 130px 34px 34px;
    padding:4px 5px 3px;
    font-size:10px;
    font-weight:800;
    color:#666;
    text-transform:uppercase;
  }
  .receipt-list-head .center{text-align:center}
  .sent-status{
    padding:5px 4px;
    font-size:10px;
    line-height:1.2;
    text-align:center;
    color:#777;
  }
  .sent-status.sent{
    color:#16713b;
    font-weight:800;
  }
  .sent-check{
    display:inline-block;
    font-size:16px;
    line-height:14px;
    vertical-align:middle;
    margin-right:2px;
  }
  .sent-date{
    display:block;
    margin-top:2px;
    font-size:9px;
    font-weight:600;
    color:#4d6e59;
    white-space:nowrap;
  }
  .whatsapp-list-btn{
    width:30px;
    height:30px;
    margin:2px;
    padding:0;
    border:0;
    border-radius:7px;
    background:transparent;
    cursor:pointer;
    display:flex;
    align-items:center;
    justify-content:center;
  }
  .whatsapp-list-btn img{
    width:28px;
    height:28px;
    display:block;
    border-radius:7px;
  }
  .whatsapp-list-btn:hover{background:#dff7e8}
  .file-name-wrap{
    display:flex;
    align-items:center;
    gap:6px;
    min-width:0;
  }
  .missing-data-icon{
    flex:0 0 auto;
    display:inline-flex;
    align-items:center;
    justify-content:center;
    width:18px;
    height:18px;
    border-radius:50%;
    background:#ffe5a8;
    color:#8a4b00;
    font-size:12px;
    font-weight:800;
    line-height:18px;
    cursor:help;
  }
  .preview-modal{
    position:fixed;
    inset:0;
    background:rgba(0,0,0,.72);
    display:none;
    align-items:center;
    justify-content:center;
    z-index:9999;
    padding:20px;
  }
  .preview-modal.open{display:flex}
  .preview-box{
    width:min(1100px,96vw);
    height:min(92vh,900px);
    background:#fff;
    border-radius:12px;
    overflow:hidden;
    display:grid;
    grid-template-rows:auto 1fr;
    box-shadow:0 12px 40px rgba(0,0,0,.35);
  }
  .preview-toolbar{
    display:flex;
    justify-content:space-between;
    align-items:center;
    gap:12px;
    padding:10px 12px;
    background:#f3f3f3;
    border-bottom:1px solid #ccc;
  }
  .preview-title{
    font-size:13px;
    font-weight:700;
    overflow:hidden;
    white-space:nowrap;
    text-overflow:ellipsis;
  }
  .preview-actions{
    display:flex;
    align-items:center;
    gap:8px;
    flex:0 0 auto;
  }
  .whatsapp-share{
    width:auto;
    margin:0;
    padding:8px 14px;
    background:#25D366;
    color:#fff;
    border-radius:7px;
    font-weight:800;
  }
  .whatsapp-share:hover{filter:brightness(.95)}
  .preview-close{
    width:auto;
    margin:0;
    padding:8px 14px;
    background:#111;
    color:#fff;
    border-radius:7px;
  }

  .confetti-layer{
    position:fixed;
    inset:0;
    z-index:12000;
    pointer-events:none;
    overflow:hidden;
  }
  .confetti-piece{
    position:absolute;
    top:-24px;
    width:10px;
    height:16px;
    opacity:.95;
    animation:confettiFall var(--fall-time) linear forwards;
    transform:rotate(var(--start-rot));
  }
  @keyframes confettiFall{
    0%{
      transform:translate3d(0,-30px,0) rotate(var(--start-rot));
    }
    100%{
      transform:translate3d(var(--drift),105vh,0) rotate(var(--end-rot));
    }
  }
  .preview-frame{
    width:100%;
    height:100%;
    border:0;
    background:#ddd;
  }
  .preview-wrap{padding:24px;display:flex;justify-content:center;align-items:flex-start;overflow:auto}
  .receipt{
    width:190mm; min-height:267mm; background:white; padding:14mm 15mm;
    box-shadow:0 5px 24px rgba(0,0,0,.16);
  }
  .receipt-header{display:flex;justify-content:space-between;gap:16px;border-bottom:2px solid #222;padding-bottom:8px}
  .title{font-size:21px;font-weight:800;letter-spacing:.3px}
  .subtitle{font-size:11px;margin-top:4px}
  .receipt-no{text-align:right;font-size:10px;min-width:90px}
  .receipt-no.empty{display:none}
  .big{font-size:14px;font-weight:700;margin-top:3px}
  .section{margin-top:14px;border:1px solid #333}
  .section-title{font-size:11px;font-weight:700;background:#f3f3f3;padding:6px 8px;border-bottom:1px solid #333}
  .grid{display:grid;grid-template-columns:1fr 1fr}
  .cell{padding:8px;min-height:50px;border-right:1px solid #333;border-bottom:1px solid #333}
  .cell:nth-child(2n){border-right:0}
  .grid .cell:nth-last-child(-n+2){border-bottom:0}
  .small-label{font-size:9px;text-transform:uppercase;color:#555}
  .value{font-size:13px;font-weight:700;margin-top:4px}
  .amount{font-size:22px;font-weight:800;margin-top:3px}
  .statement{margin-top:16px;line-height:1.5;font-size:12px}
  .footer{margin-top:55px;display:grid;grid-template-columns:1fr 1fr;gap:38px;align-items:center}
  .place-date{font-size:12px}
  .sig-label{font-size:12px;color:#666;text-align:center;margin-bottom:2px}
  .signature-area{position:relative;height:42px}
  .signature-image{position:absolute;left:50%;top:-12px;transform:translateX(-50%);max-width:95%;max-height:60px;object-fit:contain}
  .muted{color:#666;font-size:11px}
  @media(max-width:950px){
    .receipt-filters{grid-template-columns:1fr}
    .app{grid-template-columns:1fr}
    .splitter{display:none}
    .panel{border-bottom:1px solid #ccc}
    .preview-wrap{padding:12px}
    .receipt{width:100%;min-height:auto;padding:22px}
    .tenant-menu{position:fixed;left:12px;right:12px;top:110px;width:auto;max-width:none}
  }
  /* v85: anteprima a video più compatta.
     Riduzione ~18% = circa 5 cm in meno sull'altezza A4 visualizzata.
     La stampa/PDF rimangono al 100%. */
  @media screen{
    .receipt{
      zoom:.82;
    }
    .preview-wrap{
      padding:12px 16px;
    }
  }

  @media print{
    body{background:white}
    .receipt{zoom:1}
    .panel{display:none}
    .app{display:block}
    .preview-wrap{padding:0}
    .receipt{width:100%;min-height:0;box-shadow:none;padding:10mm 12mm}
    @page{size:A4 portrait;margin:8mm}
  }
</style>
</head>
<body>
<div class="app">
  <div class="panel">
    <div class="app-title-row">
      <h1>Generatore ricevute <span style="font-size:12px;font-weight:400;color:#666">v120</span> <span id="whatsappEngineBadge" style="font-size:11px;font-weight:400;color:#888" title="Versione del motore WhatsApp installata sul server locale"></span></h1>
      <div class="title-actions">
        <button type="button" class="advanced-toggle compact-toggle" id="advancedToggleBtn" onclick="toggleAdvancedFields()">
          Mostra più campi
        </button>
        <button type="button" class="new-receipt compact-new-receipt" onclick="clearForm()" title="Inizia una nuova ricevuta">
          Nuova ricevuta
        </button>
        <button type="button" class="settings-button" onclick="openSettings()" title="Configurazione" aria-label="Apri configurazione">⚙</button>
      </div>
    </div>

    <label class="step-label"><span class="step-number">Passo 1</span> - Scelta Affittuario/condomino:</label>
    <select id="persona" class="keyboard-select" aria-label="Scelta affittuario o condomino">
      <option value="">— Seleziona dall'elenco —</option>
    </select>
    <div class="tenant-picker" id="tenantPicker">
      <button type="button" class="tenant-picker-button" id="tenantPickerButton" onclick="toggleTenantPicker()">
        — Seleziona dall'elenco —
      </button>
      <div id="tenantKeyboardHint" class="muted" style="margin-top:5px;display:none">
        Tastiera attiva: ↑ ↓ cambiano affittuario
      </div>
      <div class="tenant-menu" id="tenantMenu">
        <div class="tenant-head">
          <span>Nominativo</span>
          <span>Unità</span>
          <span>Indirizzo</span>
          <span>Canone</span>
          <span>WhatsApp</span>
        </div>
        <div id="tenantRows" tabindex="0" role="listbox" aria-label="Elenco affittuari"></div>
      </div>
    </div>

    <div class="advanced-fields" id="advancedFieldsTop">
    <label>Nominativo</label>
    <input id="cognome">

    <div class="row">
      <div>
        <label>Tipo unità</label>
        <select id="tipo">
          <option>Appartamento</option>
          <option>Box</option>
          <option>Appartamento + Box</option>
          <option>Altro</option>
        </select>
      </div>
      <div>
        <label>Numero / dettaglio unità</label>
        <input id="unita">
      </div>
    </div>

    <label>Indirizzo condominio</label>
    <input id="indirizzo">
    </div>

    <label class="step-label"><span class="step-number">Passo 2</span> - Data del pagamento:</label>
    <input id="dataPagamento" type="date">

    <h2 class="advanced-fields">Periodo a cui si riferisce</h2>

    <label class="step-label"><span class="step-number">Passo 3</span> - Importo Pagato (€)</label>
    <input id="importo" type="number" step="0.01">

    <fieldset class="period-group">
      <legend>Periodo del canone:</legend>

      <div class="period-choice">
        <button type="button" id="monthChoiceBtn" class="period-choice-btn active" onclick="setPeriodMode('month')">
          Mese intero
        </button>
        <button type="button" id="rangeChoiceBtn" class="period-choice-btn" onclick="setPeriodMode('range')">
          Periodo diverso
        </button>
      </div>

      <div id="monthMode">
        <div class="month-year-row">
          <div>
            <label>Mese:</label>
            <select id="meseRiferimento">
              <option value="">— Nessun mese selezionato —</option>
              <option value="Gennaio">Gennaio</option>
              <option value="Febbraio">Febbraio</option>
              <option value="Marzo">Marzo</option>
              <option value="Aprile">Aprile</option>
              <option value="Maggio">Maggio</option>
              <option value="Giugno">Giugno</option>
              <option value="Luglio">Luglio</option>
              <option value="Agosto">Agosto</option>
              <option value="Settembre">Settembre</option>
              <option value="Ottobre">Ottobre</option>
              <option value="Novembre">Novembre</option>
              <option value="Dicembre">Dicembre</option>
            </select>
          </div>
          <div>
            <label>Anno:</label>
            <div class="year-stepper">
              <button type="button" class="year-btn" onclick="changeReferenceYear(-1)" title="Anno precedente">−</button>
              <input id="annoRiferimento" type="number" min="2000" max="2100" step="1">
              <button type="button" class="year-btn" onclick="changeReferenceYear(1)" title="Anno successivo">+</button>
            </div>
          </div>
        </div>
      </div>

      <div id="rangeMode" class="range-mode">
        <div class="range-inline-row">
          <div class="range-month-cell">
            <label>Mese Dal:</label>
            <select id="meseDal">
              <option value="">— Mese —</option>
              <option>Gennaio</option><option>Febbraio</option><option>Marzo</option><option>Aprile</option>
              <option>Maggio</option><option>Giugno</option><option>Luglio</option><option>Agosto</option>
              <option>Settembre</option><option>Ottobre</option><option>Novembre</option><option>Dicembre</option>
            </select>
          </div>

          <div class="range-year-cell">
            <label>Anno:</label>
            <div class="year-stepper range-year-stepper">
              <button type="button" class="year-btn" onclick="changeRangeYear('annoDal',-1)">−</button>
              <input id="annoDal" type="number" min="2000" max="2100" step="1">
              <button type="button" class="year-btn" onclick="changeRangeYear('annoDal',1)">+</button>
            </div>
          </div>

          <div class="range-month-cell">
            <label>Mese Al:</label>
            <select id="meseAl">
              <option value="">— Mese —</option>
              <option>Gennaio</option><option>Febbraio</option><option>Marzo</option><option>Aprile</option>
              <option>Maggio</option><option>Giugno</option><option>Luglio</option><option>Agosto</option>
              <option>Settembre</option><option>Ottobre</option><option>Novembre</option><option>Dicembre</option>
            </select>
          </div>

          <div class="range-year-cell">
            <label>Anno:</label>
            <div class="year-stepper range-year-stepper">
              <button type="button" class="year-btn" onclick="changeRangeYear('annoAl',-1)">−</button>
              <input id="annoAl" type="number" min="2000" max="2100" step="1">
              <button type="button" class="year-btn" onclick="changeRangeYear('annoAl',1)">+</button>
            </div>
          </div>
        </div>

        <div id="boxQuarterControls" class="box-quarter-controls">
          <button type="button" class="box-quarter-btn" onclick="shiftBoxQuarter(-1)" title="Trimestre precedente">−</button>
          <div class="box-quarter-center">
            <div class="box-quarter-title">TRIMESTRE BOX</div>
            <div id="boxQuarterLabel" class="box-quarter-label">—</div>
            <div class="box-quarter-note">Scelto automaticamente dalla data del pagamento</div>
          </div>
          <button type="button" class="box-quarter-btn" onclick="shiftBoxQuarter(1)" title="Trimestre successivo">+</button>
        </div>
      </div>
    </fieldset>

    <div class="advanced-fields" id="advancedFieldsBottom">
      <label>Causale</label>
      <input id="causale">

      <div class="row">
        <div><label>N. ricevuta</label><input id="numeroRicevuta"></div>
        <div>
          <label>Metodo pagamento</label>
          <select id="metodo">
            <option>Contanti</option>
            <option>Bonifico bancario</option>
            <option>Assegno</option>
            <option>Altro</option>
          </select>
        </div>
      </div>
    </div>

    <div id="existingReceiptBanner" class="existing-receipt-banner">
      <strong>ATTENZIONE:</strong> stai lavorando sui dati di una ricevuta già esistente.<br>
      Al momento del salvataggio ti chiederò se vuoi <strong>modificare questa ricevuta</strong>
      oppure <strong>crearene una nuova partendo da questi dati</strong>.
    </div>

    <button class="primary wide final-step-button" onclick="generatePDF()"><span class="step-number">Passo 4</span>, il <span class="conclusive-word">CONCLUSIVO</span> - Genera e mostra ANTEPRIMA</button>

    <button type="button" class="section-toggle receipts-toggle" id="receiptsToggleBtn" onclick="toggleReceiptsList()">
      <span class="arrow">▶</span> Ricevute create e/o inviate
    </button>
    <div id="receiptsSection" class="receipts-section">
      <div class="receipt-filters">
        <div class="receipt-filter-box">
          <label for="receiptFilterText">Cerca nel nome della ricevuta</label>
          <input id="receiptFilterText" type="search" placeholder="Es. ANTAR, Agosto, AppNum03…" oninput="renderReceiptList()">
        </div>
        <div class="receipt-filter-box">
          <label for="receiptFilterWhatsapp">Stato WhatsApp</label>
          <select id="receiptFilterWhatsapp" onchange="renderReceiptList()">
            <option value="all">Tutte</option>
            <option value="sent">Inviate</option>
            <option value="unsent">Non inviate</option>
          </select>
        </div>
      </div>
      <div class="receipt-list-head">
        <span>Ricevuta</span>
        <span class="center">WhatsApp</span>
        <span></span>
        <span></span>
      </div>
      <div class="file-list" id="fileList">
        <div class="muted">Seleziona una cartella per visualizzare i PDF presenti.</div>
      </div>
      <div class="receipt-stats" id="receiptStats">Con dati: 0 • Senza dati: 0 • Inviate: 0 • Totale: 0</div>
    </div>
    <div class="status" id="status"></div>
  </div>

  <div class="splitter" id="splitter" title="Trascina per ridimensionare"></div>

  <div class="preview-wrap">
    <div class="receipt" id="receipt">
      <div class="receipt-header">
        <div>
          <div class="title">RICEVUTA DI AVVENUTO PAGAMENTO</div>
          <div class="subtitle">Conferma di pagamento</div>
        </div>
        <div class="receipt-no empty" id="ricevutaBox">
          N. RICEVUTA
          <div class="big" id="pNumero"></div>
        </div>
      </div>

      <div class="section">
        <div class="section-title">PAGAMENTO EFFETTUATO DA</div>
        <div class="grid">
          <div class="cell"><div class="small-label">Nome e cognome</div><div class="value" id="pNome">—</div></div>
          <div class="cell"><div class="small-label">Unità immobiliare</div><div class="value" id="pUnita">—</div></div>
          <div class="cell"><div class="small-label">Indirizzo condominio</div><div class="value" id="pIndirizzo">—</div></div>
          <div class="cell"><div class="small-label">Data del pagamento</div><div class="value" id="pData">—</div></div>
        </div>
      </div>

      <div class="section">
        <div class="section-title">DETTAGLIO DEL PAGAMENTO</div>
        <div class="grid">
          <div class="cell"><div class="small-label">Periodo di riferimento</div><div class="value" id="pPeriodo">—</div></div>
          <div class="cell"><div class="small-label">Importo ricevuto</div><div class="amount" id="pImporto">€ 0,00</div></div>
          <div class="cell"><div class="small-label">Causale</div><div class="value" id="pCausale">Quota condominiale</div></div>
          <div class="cell"><div class="small-label">Metodo di pagamento</div><div class="value" id="pMetodo">—</div></div>
        </div>
      </div>

      <div class="statement">
        Si attesta che <strong id="sNome">—</strong>, per l'unità
        <strong id="sUnita">—</strong> sita presso
        <strong id="sIndirizzo">—</strong>, ha effettuato in data
        <strong id="sData">—</strong> il pagamento di
        <strong id="sImporto">€ 0,00</strong>, riferito al periodo
        <strong id="sPeriodo">—</strong>.
      </div>

      <div class="footer">
        <div class="place-date" id="luogoData">San Giuliano Milanese, —</div>
        <div>
          <div class="signature-area">
            <img class="signature-image" src="data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/2wBDAQMDAwQDBAgEBAgQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/wAARCAEGA+8DASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD9U6KKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooqpq2raVoGlXuu67qdpp2m6dbyXd5eXcywwW0EalpJZJGIVEVQWLEgAAk0AW6K+Kv2i/wDgq5+zj8FvO0TwBdf8LS8SJt/0fQrtF0uLPkt+91Ha8bZjlcr9nWfDxMknlHkfJY8W/wDBSX/gpBc6xB4Ha78C/CTW7iUw+ZL/AGZpCWhiuIDbNepELvU0fy5Y5lQSxec4LxwrsCAH6U/F79r39mj4EXMmn/FL4x+H9J1KC4itp9Lhke+1G3eSIyoZbO1WSeNDHhg7oE+dOfnXPzr4p/4LJfsj+H9dutI0nTfiB4mtLfZ5eqaXo0EdrcbkVjsW7uIZhtJKHfEvzKcZXDHx/wAB/wDBD7SodVgu/id8fbu801Li7Wew0HRVtp5oA0i2zrdTSSLG5XyZJEMDhSXjVmwJj9VeAP8Agmj+xb8PrnSdStfg1aa5qWlW4hN1r99c6il4/lGN5p7WWQ2ju2WbAhCK5DIqbVwAeVeCv+Cy37LniTxNLovibQfGvhPTXuGW01i+0+K5gEAt1ffcR20kk0bmbzIlSNJhgRuzLvdY/tXwB4/8G/FPwbpPxB+H3iG01zw9rluLmxvrYnZKmSCCCAyOrBkdGAdHVlYKykDzTxT+xT+yP4w0K68Oat+zl8P7e0u9nmSaXocGmXS7HVxsubRY5o+VAOxxuXKnKsQfyW/4yO/4JK/tHf8AQc8Ka5/vw6X4t0uN/wDgX2e8h8z/AGngd/8AlrBN+/AP3UorJ8J+KdC8c+FdG8a+Fr77boviDT7fVNOufKePz7WeNZIpNjhXXcjqcMAwzggHitagAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA8q+Nf7U/7Pv7O32WP4x/FHSvD93e7GgsNst3fPG/mbZvstukkwhJhkXzSnl7l27txAPqtfgt/wVg8U674g/ba8X6Tq999otPDOn6Rpelx+UifZ7V7GG7aPKgF8z3dw+WJb58Z2qoH7Pfsyatquv/s2/CjXdd1O71HUtR8D6Fd3l5dzNNPczyWELSSySMSzuzEsWJJJJJoA9LooooA5/wCIVlbaj4A8S6feat4g0u3utHvYZb7w8srarao0LhprMQo8puVBLRiNHfeF2qxwD8Af8ET/AIoar4h+Efjz4Uagt3Nb+DNYtdSsbia9aVI4NQSTNrFERiFEls5ZTtbDPdOdqkEv+j9fjX/wRL8R3lr8ffHXhJEzaal4POoyt9onXElte28aDylkEL5F3J87xtIuMRuivKsgB+ylFFFABRRRQAUUUUAFFFFABRRRQAUVUvdTtrC5sLWeO7Z9RuDbQmG0lmRXEUkpMropWFNsTAPIVQuUQHe6K1ugAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACivkr9qr/AIKT/Ab9my2vNC0bUrTx/wCO7W4W3fw5pN9tS2Ilkjm+13ipJFbvGYpFaHDTBzGDGqMZF+FZNM/4KS/8FNNKt9ZaS08P/C/VLia2RFu/7J8Pl4FjZi8IaS8vk8+3Ta7LcJHOZAhjCyBAD7A/ai/4KsfAb4OaVqXh/wCEmr2nxH8bfZ2WzOmt52iWk5WJo3ubtWCzJtlLbLYyEtC8TtATuHx/pPwQ/wCChH/BSjVbLxX8V9cu/Cvw6nuI76zbVI3sdKigZhJHJp+mrh7txb3snk3MgxIimNrrIr7q/Z+/4JjfsufBDSlbXfB1p8R/EM9uIrzVPFVpFdwEssXmC3smBghTzIi6ErJMokdDMynFfWtAHx/8C/8Aglp+yn8H7PTr3xJ4S/4WJ4ktMyTan4kzLavI8AikVNPB+zeTu8x0WZJpEZ/9axRCv2BRRQAUUUUAFfKv/BSz4F6F8Zf2U/F+rSaNpUviTwJp83iTRdSvC6SWUduVmvkjdAWPm2sUqeWwMbSCEtgorp9VVk+LPC2heOfCus+CvFNj9t0XxBp9xpeo23mvH59rPG0cse9CrruR2GVIYZyCDzQB8bf8EgvihpXjT9ku28BwraQal8PtYvdNuIFvVlnlguZmvYrp4sBoUZriaFc7gxtZCG6qv2/X5F/8EnvFtt8Bf2o/in+yx40a0fXdauJNNt760llkgl1HRJbsSwRjygSkkUlzKJJDHgWwXaWkAH66UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFZPizxToXgbwrrPjXxTffYtF8P6fcapqNz5TyeRawRtJLJsQM7bURjhQWOMAE8UAfzr/ALR3g7xVqvxT+OPxM1eLSrL+xvihdaNqllbXklxsvr+51OZRBI0Ufmwp/Z9wpkZY2OYz5Y3ME/en9k7/AJNY+Df/AGT/AMPf+m6CvwL8UfELVdU/Zt0rQr3xxd6nqXiX4ka74h8R2d3qbXU808Nhpy2d9JHIzNG8jXupqZgFM5BEhk+zx+X+9P7Hek6Vov7KHwes9G0y0sLeTwPot28VtCsSNPPZxTTSlVABeSWSSR26s7sxySTQB7BRRRQAV+K3/BFT/k6fxT/2T++/9OOnV+1NfhD/AMEk/Guq+Ff20vD+hafb2klv4x0fVdEvmmRi8cCWzXwaIhgA/m2MSksGGxnGMkMoB+71FFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFcp8Uvil4E+C3gTU/iZ8S9d/sbw3o3k/bb37LNceV5syQx/u4UeRsySovyqcZycAEj84P2mP+CqPj7x14ytvhF+wZo93r1xd2+4+IIfD015qN3OoWd00+xlQkJHFHKsjzQuW3SFFjEazSAH2/wDtC/tjfs+/sweTZfFnxt9k1q90+fUdP0SytJbu+vI48gALGpSLzHBSN53jjZlf58I5X8tvib+0B+2l/wAFPNV1v4ffBfwBd2XgTTLeyvL/AMM2GoWyQB0Y7HvdRuBAJneUs6QZVCIEYRM8DzV6V+y1/wAEmPHfjjxVrHxD/bXl1WxzqAuU0aDWobq+1u4aRZp7i9vInlxDJl0IRxO7O7b4timX9VPC3hPwr4G0K18LeCvDOleH9Fst/wBm07S7KO0tYN7s77IowqLud2Y4HLMSeSaAPgv9mT/gj/8AC/4Y6rD4v+POu2nxI1JLe0lt9FWzkttKsL1WWSUv+8LX6blCKJUjjZDJ5kLbwI/0KoooAKKKKACiiigAooooAKKKKAPxg8D634Z+H/8AwWbub/WbG78PWN1441aySO5024geW91GzuIIZBG0s7lLi5uo3SbcsbpOsoS3iYRR/s/X4wf8FLfGtz8K/wDgop4Q+J0/w1tLZPC9v4c1+Ew3kSP4nS1umlNxK6IWhfdE1mPMDuEtEYZQoo/Z+gAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigArxT9tbxToXg/9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39vJbSvaeGLO1nVHUqxjmhjWWJ8E4eNldTgqQQDXQfDP9n74HfBvyJPhb8JvCnhm7t9PXS/t+n6XDHfTWq7P3c11t86bJjjZjI7M7KGYlua9AooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA8/8Ajp8C/hx+0X8ONR+F/wAUNG+3aVfYlhmiIS60+6UER3VtIQfLmTc2DgqVZkdXR3RvyL/Z1+CPjL9m3/gqRoX7P/gz4vXavp1wianq8OmCFNW046Uup3FlLatK67JFXyQxdtjhJlG9FAKKAP20ooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigD/9k=" alt="Firma">
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<script>
const DEFAULT_PEOPLE = [{"nominativo": "ABDEL GHANI", "appartamento": "1", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 700}, {"nominativo": "SHAWKY", "appartamento": "2", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 860}, {"nominativo": "ANTAR", "appartamento": "3", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 950}, {"nominativo": "RAMZI AHMED OMARAN", "appartamento": "4", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 700}, {"nominativo": "ZANATI", "appartamento": "5", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 700}, {"nominativo": "MOHAMED SOLINAM GABER", "appartamento": "6", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 700}, {"nominativo": "SALAHELDIN MOHAMED SAKR", "appartamento": "7", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 700}, {"nominativo": "RACHIDA", "appartamento": "8", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 700}, {"nominativo": "FATHALLA MOUSSA", "appartamento": "9", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 700}, {"nominativo": "HIHLALI", "appartamento": "10", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 700}, {"nominativo": "EL SAMKARI", "appartamento": "11", "indirizzo": "San Giuliano Milanese - Via Trieste, 44", "canone": 700}, {"nominativo": "ELSAYED", "appartamento": "2' piano A", "indirizzo": "San Giuliano Milanese - Via Don Bosco, 20", "canone": 700}, {"nominativo": "AHMED SHAABAM MAMDOUH FARAG", "appartamento": "2' piano B", "indirizzo": "San Giuliano Milanese - Via Don Bosco, 20", "canone": 1000}, {"nominativo": "KYOSEV", "appartamento": "Rialzato", "indirizzo": "Sordio - Via Manzoni", "canone": 700}];
let PEOPLE = DEFAULT_PEOPLE.map(p=>({...p}));

const BOX_ADDRESS_V107="San Giuliano Milanese - Via Matteotti, 22";
const BOX_MONTHLY_RENT_V107=100;
const BOX_TENANTS_V107=[{"nominativo":"ELALLAMI SAAD","tipo":"Box","appartamento":"01","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3391180787"},{"nominativo":"CHAFAI MABROUK","tipo":"Box","appartamento":"02","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3391180787"},{"nominativo":"OSSAMA ALI SEOUDI ABDALLA","tipo":"Box","appartamento":"03","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3334257323"},{"nominativo":"ATTIA HASSER AHMED","tipo":"Box","appartamento":"04","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3279960363"},{"nominativo":"MELLAK ABDELKRIM","tipo":"Box","appartamento":"05","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3407667604"},{"nominativo":"KHALFA MOHAMED ALI B.TOUHAMI","tipo":"Box","appartamento":"06","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3384591056"},{"nominativo":"CANESI DANILO","tipo":"Box","appartamento":"07","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3403769522"},{"nominativo":"BEHI MOHAMED","tipo":"Box","appartamento":"08","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3395659518"},{"nominativo":"DI FRONZO ANNA","tipo":"Box","appartamento":"09","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3899660714"},{"nominativo":"BALLACCHINO FRANCESCO","tipo":"Box","appartamento":"10","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3478914139"},{"nominativo":"MILANESI SIMONE","tipo":"Box","appartamento":"11","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3315618352"},{"nominativo":"HORDIICHUK ILLIA","tipo":"Box","appartamento":"12","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":""},{"nominativo":"ZHALOBA VLADYSLAV","tipo":"Box","appartamento":"13","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3484638853"},{"nominativo":"QUTAK TARAS","tipo":"Box","appartamento":"14","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3402471686"},{"nominativo":"ROSSI PAOLO","tipo":"Box","appartamento":"15","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3276772040"},{"nominativo":"MELLAK ABDELKRIM","tipo":"Box","appartamento":"16","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3407667604"},{"nominativo":"ANIME MOHAMED","tipo":"Box","appartamento":"17","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3886954490"},{"nominativo":"MELLAK ABDELKRIM","tipo":"Box","appartamento":"18","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3407667604"},{"nominativo":"MELLAK ABDELKRIM","tipo":"Box","appartamento":"19","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3407667604"},{"nominativo":"ELSAID MOHAMED ABDELNASSER","tipo":"Box","appartamento":"20","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3318464355"},{"nominativo":"MELLAK ABDELKRIM","tipo":"Box","appartamento":"21","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3407667604"},{"nominativo":"IBRAHIM ANTAR ANTAR","tipo":"Box","appartamento":"22","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3891747429"},{"nominativo":"CAPUZZI ISABELLA","tipo":"Box","appartamento":"23","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3930612927"},{"nominativo":"AMIN SOLEHI ABDEL AAL AHMED","tipo":"Box","appartamento":"24","indirizzo":"San Giuliano Milanese - Via Matteotti, 22","canone":100,"telefono":"3202475072"}];

function normalizeTenantKeyText(v){
  return String(v||'').trim().toUpperCase().replace(/\s+/g,' ');
}

function normalizeBoxNumber(v){
  const s=String(v||'').trim();
  const m=s.match(/\d+/);
  return m ? String(Number(m[0])).padStart(2,'0') : s;
}

function isMellakAbdelkrimName(v){
  const n=normalizeTenantKeyText(v);
  return n.includes('ABDELKRIM') && (
    n.includes('MELLAK') ||
    n.includes('MELLAC') ||
    n.includes('MELLACH')
  );
}

function forceMellakIdentityV109(){
  let changed=false;
  PEOPLE.forEach(p=>{
    if(isMellakAbdelkrimName(p.nominativo)){
      if(String(p.nominativo||'')!=='MELLAK ABDELKRIM'){
        p.nominativo='MELLAK ABDELKRIM';
        changed=true;
      }
      if(String(p.telefono||'')!=='3407667604'){
        p.telefono='3407667604';
        changed=true;
      }
    }
  });
  return changed;
}

function syncBoxTenantsV110(){
  let changed=false;

  BOX_TENANTS_V107.forEach(source=>{
    const sourceBox=normalizeBoxNumber(source.appartamento);

    // Per i Box il NUMERO è la chiave più sicura: così possiamo correggere
    // anche nominativi già presenti con un vecchio nome/refuso.
    let target=PEOPLE.find(p=>
      normalizeTenantKeyText(p.tipo)==='BOX' &&
      normalizeBoxNumber(p.appartamento)===sourceBox
    );

    if(!target){
      PEOPLE.push({...source});
      changed=true;
      return;
    }

    const fields=['nominativo','tipo','appartamento','indirizzo','canone','telefono'];
    fields.forEach(field=>{
      const expected=source[field];
      const current=target[field];

      if(field==='canone'){
        if(Number(current||0)!==Number(expected||0)){
          target[field]=Number(expected||0);
          changed=true;
        }
      }else if(String(current||'')!==String(expected||'')){
        target[field]=expected;
        changed=true;
      }
    });
  });

  if(forceMellakIdentityV109()) changed=true;
  return changed;
}
const SIG_B64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/2wBDAQMDAwQDBAgEBAgQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/wAARCAEGA+8DASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD9U6KKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooqpq2raVoGlXuu67qdpp2m6dbyXd5eXcywwW0EalpJZJGIVEVQWLEgAAk0AW6K+Kv2i/wDgq5+zj8FvO0TwBdf8LS8SJt/0fQrtF0uLPkt+91Ha8bZjlcr9nWfDxMknlHkfJY8W/wDBSX/gpBc6xB4Ha78C/CTW7iUw+ZL/AGZpCWhiuIDbNepELvU0fy5Y5lQSxec4LxwrsCAH6U/F79r39mj4EXMmn/FL4x+H9J1KC4itp9Lhke+1G3eSIyoZbO1WSeNDHhg7oE+dOfnXPzr4p/4LJfsj+H9dutI0nTfiB4mtLfZ5eqaXo0EdrcbkVjsW7uIZhtJKHfEvzKcZXDHx/wAB/wDBD7SodVgu/id8fbu801Li7Wew0HRVtp5oA0i2zrdTSSLG5XyZJEMDhSXjVmwJj9VeAP8Agmj+xb8PrnSdStfg1aa5qWlW4hN1r99c6il4/lGN5p7WWQ2ju2WbAhCK5DIqbVwAeVeCv+Cy37LniTxNLovibQfGvhPTXuGW01i+0+K5gEAt1ffcR20kk0bmbzIlSNJhgRuzLvdY/tXwB4/8G/FPwbpPxB+H3iG01zw9rluLmxvrYnZKmSCCCAyOrBkdGAdHVlYKykDzTxT+xT+yP4w0K68Oat+zl8P7e0u9nmSaXocGmXS7HVxsubRY5o+VAOxxuXKnKsQfyW/4yO/4JK/tHf8AQc8Ka5/vw6X4t0uN/wDgX2e8h8z/AGngd/8AlrBN+/AP3UorJ8J+KdC8c+FdG8a+Fr77boviDT7fVNOufKePz7WeNZIpNjhXXcjqcMAwzggHitagAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA8q+Nf7U/7Pv7O32WP4x/FHSvD93e7GgsNst3fPG/mbZvstukkwhJhkXzSnl7l27txAPqtfgt/wVg8U674g/ba8X6Tq999otPDOn6Rpelx+UifZ7V7GG7aPKgF8z3dw+WJb58Z2qoH7Pfsyatquv/s2/CjXdd1O71HUtR8D6Fd3l5dzNNPczyWELSSySMSzuzEsWJJJJJoA9LooooA5/wCIVlbaj4A8S6feat4g0u3utHvYZb7w8srarao0LhprMQo8puVBLRiNHfeF2qxwD8Af8ET/AIoar4h+Efjz4Uagt3Nb+DNYtdSsbia9aVI4NQSTNrFERiFEls5ZTtbDPdOdqkEv+j9fjX/wRL8R3lr8ffHXhJEzaal4POoyt9onXElte28aDylkEL5F3J87xtIuMRuivKsgB+ylFFFABRRRQAUUUUAFFFFABRRRQAUVUvdTtrC5sLWeO7Z9RuDbQmG0lmRXEUkpMropWFNsTAPIVQuUQHe6K1ugAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACivkr9qr/AIKT/Ab9my2vNC0bUrTx/wCO7W4W3fw5pN9tS2Ilkjm+13ipJFbvGYpFaHDTBzGDGqMZF+FZNM/4KS/8FNNKt9ZaS08P/C/VLia2RFu/7J8Pl4FjZi8IaS8vk8+3Ta7LcJHOZAhjCyBAD7A/ai/4KsfAb4OaVqXh/wCEmr2nxH8bfZ2WzOmt52iWk5WJo3ubtWCzJtlLbLYyEtC8TtATuHx/pPwQ/wCChH/BSjVbLxX8V9cu/Cvw6nuI76zbVI3sdKigZhJHJp+mrh7txb3snk3MgxIimNrrIr7q/Z+/4JjfsufBDSlbXfB1p8R/EM9uIrzVPFVpFdwEssXmC3smBghTzIi6ErJMokdDMynFfWtAHx/8C/8Aglp+yn8H7PTr3xJ4S/4WJ4ktMyTan4kzLavI8AikVNPB+zeTu8x0WZJpEZ/9axRCv2BRRQAUUUUAFfKv/BSz4F6F8Zf2U/F+rSaNpUviTwJp83iTRdSvC6SWUduVmvkjdAWPm2sUqeWwMbSCEtgorp9VVk+LPC2heOfCus+CvFNj9t0XxBp9xpeo23mvH59rPG0cse9CrruR2GVIYZyCDzQB8bf8EgvihpXjT9ku28BwraQal8PtYvdNuIFvVlnlguZmvYrp4sBoUZriaFc7gxtZCG6qv2/X5F/8EnvFtt8Bf2o/in+yx40a0fXdauJNNt760llkgl1HRJbsSwRjygSkkUlzKJJDHgWwXaWkAH66UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFZPizxToXgbwrrPjXxTffYtF8P6fcapqNz5TyeRawRtJLJsQM7bURjhQWOMAE8UAfzr/ALR3g7xVqvxT+OPxM1eLSrL+xvihdaNqllbXklxsvr+51OZRBI0Ufmwp/Z9wpkZY2OYz5Y3ME/en9k7/AJNY+Df/AGT/AMPf+m6CvwL8UfELVdU/Zt0rQr3xxd6nqXiX4ka74h8R2d3qbXU808Nhpy2d9JHIzNG8jXupqZgFM5BEhk+zx+X+9P7Hek6Vov7KHwes9G0y0sLeTwPot28VtCsSNPPZxTTSlVABeSWSSR26s7sxySTQB7BRRRQAV+K3/BFT/k6fxT/2T++/9OOnV+1NfhD/AMEk/Guq+Ff20vD+hafb2klv4x0fVdEvmmRi8cCWzXwaIhgA/m2MSksGGxnGMkMoB+71FFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFcp8Uvil4E+C3gTU/iZ8S9d/sbw3o3k/bb37LNceV5syQx/u4UeRsySovyqcZycAEj84P2mP+CqPj7x14ytvhF+wZo93r1xd2+4+IIfD015qN3OoWd00+xlQkJHFHKsjzQuW3SFFjEazSAH2/wDtC/tjfs+/sweTZfFnxt9k1q90+fUdP0SytJbu+vI48gALGpSLzHBSN53jjZlf58I5X8tvib+0B+2l/wAFPNV1v4ffBfwBd2XgTTLeyvL/AMM2GoWyQB0Y7HvdRuBAJneUs6QZVCIEYRM8DzV6V+y1/wAEmPHfjjxVrHxD/bXl1WxzqAuU0aDWobq+1u4aRZp7i9vInlxDJl0IRxO7O7b4timX9VPC3hPwr4G0K18LeCvDOleH9Fst/wBm07S7KO0tYN7s77IowqLud2Y4HLMSeSaAPgv9mT/gj/8AC/4Y6rD4v+POu2nxI1JLe0lt9FWzkttKsL1WWSUv+8LX6blCKJUjjZDJ5kLbwI/0KoooAKKKKACiiigAooooAKKKKAPxg8D634Z+H/8AwWbub/WbG78PWN1441aySO5024geW91GzuIIZBG0s7lLi5uo3SbcsbpOsoS3iYRR/s/X4wf8FLfGtz8K/wDgop4Q+J0/w1tLZPC9v4c1+Ew3kSP4nS1umlNxK6IWhfdE1mPMDuEtEYZQoo/Z+gAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigArxT9tbxToXg/9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39vJbSvaeGLO1nVHUqxjmhjWWJ8E4eNldTgqQQDXQfDP9n74HfBvyJPhb8JvCnhm7t9PXS/t+n6XDHfTWq7P3c11t86bJjjZjI7M7KGYlua9AooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA8/8Ajp8C/hx+0X8ONR+F/wAUNG+3aVfYlhmiIS60+6UER3VtIQfLmTc2DgqVZkdXR3RvyL/Z1+CPjL9m3/gqRoX7P/gz4vXavp1wianq8OmCFNW046Uup3FlLatK67JFXyQxdtjhJlG9FAKKAP20ooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigD/9k=";
const SIG_W = 1007, SIG_H = 262;
let directoryHandle = null;

const LOCAL_SERVER_MODE =
  location.protocol==='http:' &&
  (location.hostname==='127.0.0.1' || location.hostname==='localhost');

function remoteMimeType(name){
  const n=String(name||'').toLowerCase();
  if(n.endsWith('.pdf')) return 'application/pdf';
  if(n.endsWith('.json')) return 'application/json';
  if(n.endsWith('.txt') || n.endsWith('.log')) return 'text/plain';
  if(n.endsWith('.png')) return 'image/png';
  return 'application/octet-stream';
}

class ServerWritableFileStream{
  constructor(name){
    this.name=name;
    this.parts=[];
    this.closed=false;
  }

  async write(data){
    if(this.closed) throw new Error('File già chiuso.');

    if(data && typeof data==='object' && data.type==='write' && 'data' in data){
      data=data.data;
    }

    if(data instanceof Blob){
      this.parts.push(data);
    }else if(typeof data==='string'){
      this.parts.push(new Blob([data],{type:'text/plain;charset=utf-8'}));
    }else if(data instanceof ArrayBuffer){
      this.parts.push(new Blob([data]));
    }else if(ArrayBuffer.isView(data)){
      this.parts.push(new Blob([data.buffer.slice(data.byteOffset,data.byteOffset+data.byteLength)]));
    }else{
      this.parts.push(new Blob([String(data??'')]));
    }
  }

  async close(){
    if(this.closed) return;
    this.closed=true;

    const blob=new Blob(this.parts);
    const res=await fetch('/api/fs/file?name='+encodeURIComponent(this.name),{
      method:'PUT',
      headers:{'Content-Type':'application/octet-stream'},
      body:blob
    });

    if(!res.ok){
      throw new Error('Il server locale non riesce a salvare '+this.name+' ('+res.status+').');
    }
  }
}

class ServerFileHandle{
  constructor(name,lastModified=0){
    this.kind='file';
    this.name=name;
    this._lastModified=Number(lastModified||0);
  }

  async getFile(){
    const res=await fetch('/api/fs/file?name='+encodeURIComponent(this.name),{
      method:'GET',
      cache:'no-store'
    });

    if(!res.ok){
      const err=new Error('File non trovato: '+this.name);
      err.name='NotFoundError';
      throw err;
    }

    const blob=await res.blob();
    const lm=Number(res.headers.get('X-Last-Modified-Ms') || this._lastModified || Date.now());

    return new File([blob],this.name,{
      type:remoteMimeType(this.name),
      lastModified:lm
    });
  }

  async createWritable(){
    return new ServerWritableFileStream(this.name);
  }
}

class ServerDirectoryHandle{
  constructor(){
    this.kind='directory';
    this.name='ElencoRicevute';
  }

  async queryPermission(){
    return 'granted';
  }

  async requestPermission(){
    return 'granted';
  }

  async getFileHandle(name,options={}){
    const safe=String(name||'').trim();
    if(!safe) throw new Error('Nome file vuoto.');
    if(/[\/\\]/.test(safe)) throw new Error('Nome file non valido.');
    return new ServerFileHandle(safe);
  }

  async removeEntry(name){
    const safe=String(name||'').trim();
    const res=await fetch('/api/fs/file?name='+encodeURIComponent(safe),{
      method:'DELETE'
    });
    if(!res.ok && res.status!==404){
      throw new Error('Impossibile eliminare '+safe+' ('+res.status+').');
    }
  }

  async *values(){
    const res=await fetch('/api/fs/list',{cache:'no-store'});
    if(!res.ok){
      throw new Error('Il server locale non riesce a leggere ElencoRicevute.');
    }

    const items=await res.json();
    for(const item of items){
      if(item && item.kind==='file'){
        yield new ServerFileHandle(item.name,item.lastModified);
      }
    }
  }
}

async function localServerHealth(){
  if(!LOCAL_SERVER_MODE) return false;
  try{
    const res=await fetch('/api/health',{cache:'no-store'});
    if(!res.ok) return false;
    const data=await res.json();
    return Boolean(data && data.ok);
  }catch(e){
    return false;
  }
}

async function updateWhatsAppEngineBadge(){
  const badge=$('whatsappEngineBadge');
  if(!badge) return;
  if(!LOCAL_SERVER_MODE){
    badge.textContent='';
    return;
  }
  try{
    const res=await fetch('/api/health',{cache:'no-store'});
    if(!res.ok){ badge.textContent='(motore WhatsApp: server non raggiungibile)'; return; }
    const data=await res.json();
    const engine=data && data.whatsappEngine;
    if(engine && engine.version){
      const when=engine.installedAt ? ' · installato ' + engine.installedAt : '';
      badge.textContent='(motore WhatsApp: ' + engine.version + when + ')';
      badge.title='Versione del motore WhatsApp installata sul server locale.\nFile: ' + (engine.sourceFile || 'WhatsApp_Engine.scpt');
    } else {
      badge.textContent='(motore WhatsApp: versione non rilevata)';
    }
  }catch(e){
    badge.textContent='(motore WhatsApp: server non raggiungibile)';
  }
}
document.addEventListener('DOMContentLoaded', updateWhatsAppEngineBadge);


function $(id){ return document.getElementById(id); }
function fmtDate(v){
  if(!v) return "—";
  const [y,m,d]=v.split("-");
  return `${d}/${m}/${y}`;
}
function fmtEuro(v){
  const n=parseFloat(v||0);
  return new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(n);
}
function defaultCausaleFromPeriod(){
  const mese=$('meseRiferimento').value;
  const meseDal=$('meseDal') ? $('meseDal').value : '';
  const annoDal=$('annoDal') ? $('annoDal').value.trim() : '';
  const meseAl=$('meseAl') ? $('meseAl').value : '';
  const annoAl=$('annoAl') ? $('annoAl').value.trim() : '';

  if(mese){
    const anno=$('annoRiferimento').value.trim();
    return anno ? `Pagamento affitto mese di ${mese} ${anno}` : `Pagamento affitto mese di ${mese}`;
  }
  if(meseDal || annoDal || meseAl || annoAl){
    const dalTxt=[meseDal,annoDal].filter(Boolean).join(' ');
    const alTxt=[meseAl,annoAl].filter(Boolean).join(' ');
    return `Pagamento affitto da ${dalTxt || '—'} a ${alTxt || '—'}`;
  }
  return '';
}

function resetCausaleFromCurrentPeriod(){
  $('causale').value=defaultCausaleFromPeriod();
  update();
}

function data(){
  const full=$('cognome').value.trim() || '—';
  const tipo=$('tipo').value;
  const num=$('unita').value.trim();
  const unita=num ? `${tipo} ${num}` : tipo;
  const dataPag=fmtDate($('dataPagamento').value);
  const mese=$('meseRiferimento').value;
  const meseDal=$('meseDal') ? $('meseDal').value : '';
  const annoDal=$('annoDal') ? $('annoDal').value.trim() : '';
  const meseAl=$('meseAl') ? $('meseAl').value : '';
  const annoAl=$('annoAl') ? $('annoAl').value.trim() : '';

  let periodo='—';
  if(mese){
    const anno=$('annoRiferimento').value.trim();
    periodo=anno ? `${mese} ${anno}` : mese;
  }else if(meseDal || annoDal || meseAl || annoAl){
    const dalTxt=[meseDal,annoDal].filter(Boolean).join(' ');
    const alTxt=[meseAl,annoAl].filter(Boolean).join(' ');
    periodo=`da ${dalTxt || '—'} a ${alTxt || '—'}`;
  }

  return {
    full,tipo,num,unita,
    indirizzo:$('indirizzo').value.trim() || '—',
    dataPag,periodo,
    importo:fmtEuro($('importo').value),
    importoRaw:parseFloat($('importo').value||0),
    causale:$('causale').value.trim() || '—',
    metodo:$('metodo').value,
    nr:$('numeroRicevuta').value.trim()
  };
}
function update(){
  const d=data();
  $('pNome').textContent=d.full; $('pUnita').textContent=d.unita;
  $('pIndirizzo').textContent=d.indirizzo; $('pData').textContent=d.dataPag;
  $('pPeriodo').textContent=d.periodo; $('pImporto').textContent=d.importo;
  $('pCausale').textContent=d.causale; $('pMetodo').textContent=d.metodo;
  $('pNumero').textContent=d.nr; $('ricevutaBox').classList.toggle('empty', !d.nr);
  $('sNome').textContent=d.full; $('sUnita').textContent=d.unita;
  $('sIndirizzo').textContent=d.indirizzo; $('sData').textContent=d.dataPag;
  $('sImporto').textContent=d.importo; $('sPeriodo').textContent=d.periodo;
  $('luogoData').textContent='San Giuliano Milanese, ' + d.dataPag;
}
function renderTenantSetup(){
  const holder=$('tenantSetupRows');
  if(!holder) return;
  holder.innerHTML='';
  PEOPLE.forEach((p,i)=>{
    const row=document.createElement('div');
    row.className='tenant-setup-row';
    row.innerHTML=`
      <input data-field="nominativo" value="${String(p.nominativo||'').replace(/"/g,'&quot;')}">
      <input data-field="appartamento" value="${String(p.appartamento||'').replace(/"/g,'&quot;')}">
      <input data-field="indirizzo" value="${String(p.indirizzo||'').replace(/"/g,'&quot;')}">
      <input data-field="canone" type="number" step="0.01" value="${Number(p.canone||0)}">
      <input data-field="telefono" type="tel" placeholder="+39 333 1234567" value="${String(p.telefono||'').replace(/"/g,'&quot;')}">
    `;
    holder.appendChild(row);
  });
}

async function saveTenantSetup(){
  const rows=[...document.querySelectorAll('#tenantSetupRows .tenant-setup-row')];
  PEOPLE=rows.map(row=>{
    const get=f=>row.querySelector(`[data-field="${f}"]`).value.trim();
    return {
      nominativo:get('nominativo'),
      tipo:(PEOPLE[rows.indexOf(row)] && PEOPLE[rows.indexOf(row)].tipo) || 'Appartamento',
      appartamento:get('appartamento'),
      indirizzo:get('indirizzo'),
      canone:Number(get('canone')||0),
      telefono:get('telefono')
    };
  });

  // Manteniamo anche una copia locale di sicurezza.
  localStorage.setItem('ricevuteAffittuari',JSON.stringify(PEOPLE));
  populatePeople();

  if(directoryHandle){
    try{
      const ok=await saveTenantsFile();
      $('tenantSetupStatus').textContent=ok
        ? 'Modifiche salvate anche in Affittuari.json.'
        : 'Modifiche salvate nel browser. Per aggiornare Affittuari.json, autorizza la cartella PDF.';
    }catch(e){
      $('tenantSetupStatus').textContent='Modifiche salvate nel browser, ma non nel file JSON: '+e.message;
    }
  }else{
    $('tenantSetupStatus').textContent='Modifiche salvate nel browser. Seleziona la cartella PDF per creare Affittuari.json.';
  }
}

function populatePeople(){
  const rows=$('tenantRows');
  rows.innerHTML='';
  $('persona').innerHTML='<option value="">— Seleziona dall\'elenco —</option>';
  PEOPLE.forEach((p,i)=>{
    const o=document.createElement('option');
    o.value=i;
    const nome=String(p.nominativo||'').padEnd(28,' ');
    const tipoBreve=(p.tipo==='Box' ? 'Box ' : 'App. ');
    const app=(tipoBreve+String(p.appartamento||'')).padEnd(16,' ');
    const indirizzo=String(p.indirizzo||'').padEnd(42,' ');
    const canone=('€ '+Number(p.canone||0).toFixed(2)).padEnd(11,' ');
    const telefono=String(p.telefono||'—');
    o.textContent=`${nome} | ${app} | ${indirizzo} | ${canone} | ${telefono}`;
    $('persona').appendChild(o);

    const row=document.createElement('div');
    row.className='tenant-row';
    row.dataset.index=i;
    row.setAttribute('role','option');
    row.setAttribute('aria-selected','false');
    const unitLabel=(p.tipo==='Box' ? 'Box ' : '')+String(p.appartamento||'');
    row.innerHTML=`<span>${p.nominativo}</span><span>${unitLabel}</span><span>${p.indirizzo}</span><span>€ ${Number(p.canone||0).toFixed(2)}</span><span>${p.telefono || '—'}</span>`;
    row.onclick=()=>selectTenant(i);
    rows.appendChild(row);
  });
  renderTenantSetup();
}

let tenantKeyboardMode=false;

function setTenantKeyboardMode(on){
  tenantKeyboardMode=Boolean(on);
  $('tenantPicker').classList.toggle('keyboard-active',tenantKeyboardMode);
  $('tenantKeyboardHint').style.display=tenantKeyboardMode ? 'block' : 'none';
}

function toggleTenantPicker(){
  const menu=$('tenantMenu');
  const opening=!menu.classList.contains('open');
  menu.classList.toggle('open',opening);

  if(opening){
    setTenantKeyboardMode(true);

    const current=parseInt($('persona').value,10);
    if(Number.isFinite(current)){
      const row=document.querySelector(`.tenant-row[data-index="${current}"]`);
      if(row) row.scrollIntoView({block:'nearest'});
    }
  }else{
    setTenantKeyboardMode(false);
  }
}

function selectTenant(i, closeMenu=true){
  const idx=Number(i);
  const p=PEOPLE[idx];
  if(!p) return;

  $('persona').value=String(idx);
  $('tenantPickerButton').textContent=p.nominativo;

  let selectedRow=null;
  document.querySelectorAll('.tenant-row').forEach(r=>{
    const selected=r.dataset.index===String(idx);
    r.classList.toggle('selected',selected);
    r.setAttribute('aria-selected',selected ? 'true' : 'false');
    if(selected) selectedRow=r;
  });

  if(closeMenu){
    $('tenantMenu').classList.remove('open');
    if(typeof setTenantKeyboardMode==='function') setTenantKeyboardMode(false);
  }

  const previousWasBox=currentTenantIsBox();

  $('cognome').value=p.nominativo;
  $('tipo').value=p.tipo || 'Appartamento';
  $('unita').value=p.appartamento;
  $('indirizzo').value=p.indirizzo;
  monthlyRentBase=Number(p.canone||0);
  $('importo').value=monthlyRentBase.toFixed(2);

  if(currentTenantIsBox()){
    // Tutti i Box: €100/mese, pagamento trimestrale.
    monthlyRentBase=BOX_MONTHLY_RENT_V95;
    $('importo').value=(BOX_MONTHLY_RENT_V95*3).toFixed(2);
    applyBoxQuarterFromPaymentDate();
  }else{
    // Se arriviamo da un Box, torniamo al comportamento normale mensile.
    if(previousWasBox && usingRangePeriod){
      setRangeUiActive(false);
      $('meseDal').value='';
      $('meseAl').value='';
      $('annoDal').value='';
      $('annoAl').value='';
      syncMonthFromPaymentDate();
    }
    recalculateAmountForPeriod();
    updateBoxQuarterControls();
  }

  // Se stiamo scorrendo da tastiera, mantieni visibile la riga selezionata.
  if(selectedRow && !closeMenu){
    selectedRow.scrollIntoView({block:'nearest'});
  }
}

function moveTenantSelection(delta){
  if(!PEOPLE.length) return;

  let idx=parseInt($('persona').value,10);
  if(!Number.isFinite(idx)){
    idx=delta>0 ? -1 : PEOPLE.length;
  }

  idx=Math.max(0,Math.min(PEOPLE.length-1,idx+delta));

  // Apri la lista e aggiorna subito la ricevuta mentre si scorre con ↑/↓.
  $('tenantMenu').classList.add('open');
  selectTenant(idx,false);
}

$('tenantPickerButton').addEventListener('keydown',e=>{
  if(e.key==='ArrowDown' || e.key==='ArrowUp'){
    e.preventDefault();
    if(!$('tenantMenu').classList.contains('open')){
      $('tenantMenu').classList.add('open');
      setTenantKeyboardMode(true);
    }
    moveTenantSelection(e.key==='ArrowDown' ? 1 : -1);
  }
});








// v68 — modalità tastiera ESPLICITA.
// Una volta aperta la lista, ↑/↓ vengono intercettati a livello WINDOW,
// indipendentemente da dove Chrome ritiene che sia il focus.
// La modalità si disattiva solo quando chiudi la lista o clicchi fuori.
window.addEventListener('keydown',function(e){
  if(!tenantKeyboardMode) return;

  const code=e.keyCode || e.which || 0;
  const key=e.key || '';

  const down=(key==='ArrowDown' || code===40);
  const up=(key==='ArrowUp' || code===38);
  const home=(key==='Home' || code===36);
  const end=(key==='End' || code===35);
  const enter=(key==='Enter' || code===13);
  const esc=(key==='Escape' || key==='Esc' || code===27);

  if(!(down || up || home || end || enter || esc)) return;

  // Blocca lo scroll della scheda prima di qualsiasi altra gestione.
  e.preventDefault();
  e.stopPropagation();
  if(e.stopImmediatePropagation) e.stopImmediatePropagation();

  if(down){
    moveTenantSelection(1);
  }else if(up){
    moveTenantSelection(-1);
  }else if(home){
    selectTenant(0,false);
  }else if(end){
    selectTenant(PEOPLE.length-1,false);
  }else if(enter){
    const idx=parseInt($('persona').value,10);
    if(Number.isFinite(idx)) selectTenant(idx,true);
    $('tenantMenu').classList.remove('open');
    setTenantKeyboardMode(false);
  }else if(esc){
    $('tenantMenu').classList.remove('open');
    setTenantKeyboardMode(false);
  }

  return false;
}, {capture:true, passive:false});


document.addEventListener('click',e=>{
  const picker=$('tenantPicker');
  if(picker && !picker.contains(e.target)){
    $('tenantMenu').classList.remove('open');
    setTenantKeyboardMode(false);
  }else if(picker && picker.contains(e.target) && $('tenantMenu').classList.contains('open')){
    setTenantKeyboardMode(true);
  }
});
document.querySelectorAll('input,select').forEach(el=>{
  if(el.id!=='persona') el.addEventListener('input',update);
});

$('importo').addEventListener('input',()=>{
  if(!usingRangePeriod){
    const n=parseMoneyNumber($('importo').value);
    if(n>0) monthlyRentBase=n;
  }
});

const MONTH_NAMES=['Gennaio','Febbraio','Marzo','Aprile','Maggio','Giugno','Luglio','Agosto','Settembre','Ottobre','Novembre','Dicembre'];

function currentTenantIsBox(){
  return String($('tipo')?.value||'').trim()==='Box';
}

function setRangeUiActive(active){
  usingRangePeriod=Boolean(active);
  if($('monthMode')) $('monthMode').style.display=active ? 'none' : 'block';
  if($('rangeMode')) $('rangeMode').classList.toggle('open',active);
  if($('monthChoiceBtn')) $('monthChoiceBtn').classList.toggle('active',!active);
  if($('rangeChoiceBtn')) $('rangeChoiceBtn').classList.toggle('active',active);
}

function quarterIndexFromMonthIndex(monthIndex){
  return Math.max(0,Math.min(3,Math.floor(Number(monthIndex||0)/3)));
}

function setBoxQuarter(year,quarterIndex){
  let y=Number(year);
  let q=Number(quarterIndex);

  if(!Number.isFinite(y)) y=new Date().getFullYear();
  if(!Number.isFinite(q)) q=0;

  // Normalizza anche passaggi tipo Q4 + 1 => Q1 anno successivo.
  const absoluteQuarter=y*4+q;
  y=Math.floor(absoluteQuarter/4);
  q=((absoluteQuarter%4)+4)%4;

  const startMonth=q*3;
  const endMonth=startMonth+2;

  setRangeUiActive(true);
  $('meseRiferimento').value='';
  $('annoRiferimento').value='';
  $('meseDal').value=MONTH_NAMES[startMonth];
  $('annoDal').value=String(y);
  $('meseAl').value=MONTH_NAMES[endMonth];
  $('annoAl').value=String(y);

  monthlyRentBase=BOX_MONTHLY_RENT_V95;
  $('importo').value=(BOX_MONTHLY_RENT_V95*3).toFixed(2);

  updateBoxQuarterControls();
  resetCausaleFromCurrentPeriod();
}

function applyBoxQuarterFromPaymentDate(){
  if(!currentTenantIsBox()) return false;

  const raw=$('dataPagamento').value || localTodayISO();
  const parts=String(raw).split('-');
  const year=Number(parts[0]) || new Date().getFullYear();
  const monthNumber=Number(parts[1]) || (new Date().getMonth()+1);
  const q=quarterIndexFromMonthIndex(monthNumber-1);

  setBoxQuarter(year,q);
  return true;
}

function shiftBoxQuarter(delta){
  if(!currentTenantIsBox()) return;

  let year=parseInt($('annoDal').value,10);
  let monthIndex=monthIndexByName($('meseDal').value);

  if(!Number.isFinite(year) || monthIndex<0){
    applyBoxQuarterFromPaymentDate();
    return;
  }

  const currentQuarter=quarterIndexFromMonthIndex(monthIndex);
  setBoxQuarter(year,currentQuarter+Number(delta||0));
}

function updateBoxQuarterControls(){
  const holder=$('boxQuarterControls');
  const label=$('boxQuarterLabel');
  if(!holder || !label) return;

  const show=currentTenantIsBox() && usingRangePeriod;
  holder.classList.toggle('open',show);
  if(!show) return;

  const startMonth=$('meseDal').value;
  const endMonth=$('meseAl').value;
  const startYear=$('annoDal').value;
  const endYear=$('annoAl').value;

  if(startMonth && endMonth && startYear){
    label.textContent=startYear===endYear
      ? `${startMonth} – ${endMonth} ${startYear}`
      : `${startMonth} ${startYear} – ${endMonth} ${endYear}`;
  }else{
    label.textContent='—';
  }
}

function localTodayISO(){
  const now=new Date();
  const y=now.getFullYear();
  const m=String(now.getMonth()+1).padStart(2,'0');
  const d=String(now.getDate()).padStart(2,'0');
  return `${y}-${m}-${d}`;
}

function periodRangeActive(){
  return usingRangePeriod;
}

function syncMonthFromPaymentDate(){
  if(usingRangePeriod) return;
  const raw=$('dataPagamento').value;
  if(!raw){
    $('meseRiferimento').value='';
    $('annoRiferimento').value='';
  }else{
    const parts=raw.split('-');
    const year=Number(parts[0]);
    const monthNumber=Number(parts[1]);
    const monthIndex=monthNumber-1;

    $('meseRiferimento').value=MONTH_NAMES[monthIndex] || '';

    let referenceYear=year;
    if(monthNumber===1 || monthNumber===2){
      referenceYear=year-1;
    }else if(monthNumber===11 || monthNumber===12){
      referenceYear=year+1;
    }

    $('annoRiferimento').value=referenceYear;
  }
  resetCausaleFromCurrentPeriod();
}

$('dataPagamento').addEventListener('change',()=>{
  if(currentTenantIsBox()){
    applyBoxQuarterFromPaymentDate();
  }else{
    syncMonthFromPaymentDate();
  }
});
$('meseRiferimento').addEventListener('change',resetCausaleFromCurrentPeriod);
$('annoRiferimento').addEventListener('input',resetCausaleFromCurrentPeriod);
$('meseDal').addEventListener('change',()=>{
  normalizeRangeFromStart();
  recalculateAmountForPeriod();
  updateBoxQuarterControls();
  resetCausaleFromCurrentPeriod();
});
$('annoDal').addEventListener('change',()=>{
  normalizeRangeFromStart();
  recalculateAmountForPeriod();
  updateBoxQuarterControls();
  resetCausaleFromCurrentPeriod();
});
$('annoDal').addEventListener('input',()=>{
  recalculateAmountForPeriod();
  updateBoxQuarterControls();
  resetCausaleFromCurrentPeriod();
});

$('meseAl').addEventListener('change',()=>{
  normalizeRangeFromEnd();
  recalculateAmountForPeriod();
  updateBoxQuarterControls();
  resetCausaleFromCurrentPeriod();
});
$('annoAl').addEventListener('change',()=>{
  normalizeRangeFromEnd();
  recalculateAmountForPeriod();
  updateBoxQuarterControls();
  resetCausaleFromCurrentPeriod();
});
$('annoAl').addEventListener('input',()=>{
  recalculateAmountForPeriod();
  updateBoxQuarterControls();
  resetCausaleFromCurrentPeriod();
});
$('metodo').addEventListener('change',resetCausaleFromCurrentPeriod);

function clearForm(){
  clearLoadedReceiptContext();
  monthlyRentBase=0;
  usingRangePeriod=false;
  if($('monthMode')) $('monthMode').style.display='block';
  if($('rangeMode')) $('rangeMode').classList.remove('open');
  if($('monthChoiceBtn')) $('monthChoiceBtn').classList.add('active');
  if($('rangeChoiceBtn')) $('rangeChoiceBtn').classList.remove('active');
  $('persona').value='';
  $('tenantPickerButton').textContent='— Seleziona dall\'elenco —';
  document.querySelectorAll('.tenant-row').forEach(r=>r.classList.remove('selected'));
  ['cognome','unita','indirizzo','importo','annoRiferimento','meseDal','meseAl','annoDal','annoAl','numeroRicevuta'].forEach(id=>{ if($(id)) $(id).value=''; });
  $('dataPagamento').value=localTodayISO();
  $('tipo').selectedIndex=0;
  $('metodo').value='Contanti';
  $('causale').value='';
  $('status').textContent='';
  updateBoxQuarterControls();
  syncMonthFromPaymentDate();
}
function printPreview(){
  update();
  window.print();
}

// IndexedDB: memorizza l'handle della cartella selezionata
function openDB(){
  return new Promise((resolve,reject)=>{
    const req=indexedDB.open('RicevuteCondominioDB',1);
    req.onupgradeneeded=()=>req.result.createObjectStore('settings');
    req.onsuccess=()=>resolve(req.result);
    req.onerror=()=>reject(req.error);
  });
}
async function saveHandle(handle){
  if(LOCAL_SERVER_MODE) return true;

  const db=await openDB();
  return new Promise((resolve,reject)=>{
    const tx=db.transaction('settings','readwrite');
    tx.objectStore('settings').put(handle,'pdfDirectory');
    tx.oncomplete=resolve; tx.onerror=()=>reject(tx.error);
  });
}
async function loadHandle(){
  if(LOCAL_SERVER_MODE){
    return (await localServerHealth()) ? new ServerDirectoryHandle() : null;
  }

  const db=await openDB();
  return new Promise((resolve,reject)=>{
    const tx=db.transaction('settings','readonly');
    const req=tx.objectStore('settings').get('pdfDirectory');
    req.onsuccess=()=>resolve(req.result||null);
    req.onerror=()=>reject(req.error);
  });
}
function isRunningInsideFrame(){
  try{
    return window.self !== window.top;
  }catch(e){
    return true;
  }
}

function openStandaloneApp(){
  const url=window.location.href;
  const w=window.open(url,'_blank','noopener');
  if(!w){
    $('folderStatus').textContent='Chrome ha bloccato l’apertura della nuova scheda. Consenti i popup per questa pagina e riprova.';
  }else{
    $('folderStatus').textContent='Ho aperto il Generatore in una scheda propria. In quella scheda apri ⚙ e premi “Sfoglia…”.';
  }
}

async function chooseFolder(){
  if(LOCAL_SERVER_MODE){
    if(await localServerHealth()){
      directoryHandle=new ServerDirectoryHandle();
      $('savePath').value=DEFAULT_PDF_PATH;
      $('folderStatus').textContent='Cartella ElencoRicevute gestita automaticamente da Cruscotto Affitti: nessuna autorizzazione Chrome necessaria.';
      const btn=$('folderBrowseBtn');
      if(btn){
        btn.textContent='Collegata ✓';
        btn.disabled=true;
      }
      await loadTenantsFile();
      await loadLookup();
      await refreshFileList();
    }else{
      $('folderStatus').textContent='Il server locale di Cruscotto Affitti non risponde. Chiudi e riapri l’app dal Desktop.';
    }
    return;
  }

  if(!window.showDirectoryPicker){
    $('folderStatus').textContent='Il browser non consente la scelta diretta della cartella. Usa Chrome/Edge aggiornato.';
    return;
  }

  if(isRunningInsideFrame()){
    $('openStandaloneBtn').style.display='block';
    $('folderStatus').textContent='Il Generatore è aperto dentro una pagina incorporata: Chrome blocca il selettore cartelle. Premi “Apri il programma in una scheda propria”, poi usa “Sfoglia…”.';
    openStandaloneApp();
    return;
  }

  try{
    directoryHandle=await window.showDirectoryPicker({
      id:'ricevute-elenco',
      mode:'readwrite',
      startIn:'documents'
    });
    $('savePath').value=DEFAULT_PDF_PATH;
    $('folderStatus').textContent='Cartella memorizzata per le prossime aperture.';
    await saveHandle(directoryHandle);
    await savePdfPathFile();
    await loadTenantsFile();
    await loadLookup();
    await refreshFileList();
    $('folderStatus').textContent='Cartella collegata: '+DEFAULT_PDF_PATH;
  }catch(e){
    const msg=String(e && e.message ? e.message : e);
    if(/sub.?frame|cross.?origin|file picker/i.test(msg)){
      $('openStandaloneBtn').style.display='block';
      $('folderStatus').textContent='Chrome sta bloccando il selettore perché questa pagina è incorporata. Apri il programma in una scheda propria e riprova.';
    }else if(e && e.name!=='AbortError'){
      $('folderStatus').textContent='Errore: '+msg;
    }
  }
}
async function restoreFolder(){
  try{
    if(LOCAL_SERVER_MODE){
      if(await localServerHealth()){
        directoryHandle=new ServerDirectoryHandle();
        $('savePath').value=DEFAULT_PDF_PATH;
        $('folderStatus').textContent='Cruscotto Affitti è collegato automaticamente a ElencoRicevute. Nessun permesso Chrome richiesto.';
        const btn=$('folderBrowseBtn');
        if(btn){
          btn.textContent='Collegata ✓';
          btn.disabled=true;
        }
        const note=$('folderModeNote');
        if(note){
          note.textContent='Modalità applicazione locale: lettura e scrittura sono gestite direttamente da Cruscotto Affitti, non da Chrome.';
        }
        await loadTenantsFile();
        await loadLookup();
        await refreshFileList();
      }else{
        $('folderStatus').textContent='Il server locale di Cruscotto Affitti non risponde. Riapri l’app dal Desktop.';
      }
      return;
    }

    directoryHandle=await loadHandle();
    if(directoryHandle){
      $('savePath').value=DEFAULT_PDF_PATH;
      const permission=await directoryHandle.queryPermission({mode:'readwrite'});
      if(permission==='granted'){
        $('folderStatus').textContent='Cartella ricevute ripristinata automaticamente: '+DEFAULT_PDF_PATH;
        await loadTenantsFile();
        await loadLookup();
        await refreshFileList();
      }else{
        $('folderStatus').textContent='Cartella ricordata. Apri “Ricevute create e/o inviate” per riattivarla con un clic.';
        if($('fileList')){
          $('fileList').innerHTML='<div class="muted">Cartella ricordata: '+directoryHandle.name+'. Apri “Ricevute create e/o inviate” per riattivarla.</div>';
        }
      }
    }
  }catch(e){
    if(LOCAL_SERVER_MODE){
      $('folderStatus').textContent='Errore collegamento locale: '+(e && e.message ? e.message : e);
    }
  }
}
async function ensureFolderPermission(){
  if(!directoryHandle) return false;
  if(LOCAL_SERVER_MODE) return true;

  const opts={mode:'readwrite'};
  if((await directoryHandle.queryPermission(opts))==='granted') return true;
  return (await directoryHandle.requestPermission(opts))==='granted';
}


let currentPreviewUrl=null;
let selectedPdfEntry=null;
let selectedPdfElement=null;
let receiptLookup={};
const LOOKUP_FILE_NAME='Ricevute_Dati.json';
const TENANTS_FILE_NAME='Affittuari.json';
const PDF_PATH_FILE_NAME='Percorso_Cartella_PDF.json';
const WHATSAPP_CONFIG_FILE_NAME='WhatsApp_Destinatario.json';
const WHATSAPP_SENT_LOG_FILE='WhatsApp_Inviati.log';
const WHATSAPP_ICON_DATA='data:image/png;base64,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';
const DEFAULT_PDF_PATH='/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute';
let currentPreviewFile=null;
let currentPreviewName='';

function launchConfetti(){
  const old=document.querySelector('.confetti-layer');
  if(old) old.remove();

  const layer=document.createElement('div');
  layer.className='confetti-layer';
  document.body.appendChild(layer);

  const palette=['#ff4d4d','#ffd93d','#6bcb77','#4d96ff','#9d4edd','#ff8fab','#00b4d8'];
  const count=70;

  for(let i=0;i<count;i++){
    const piece=document.createElement('div');
    piece.className='confetti-piece';
    piece.style.left=(Math.random()*100)+'vw';
    piece.style.background=palette[Math.floor(Math.random()*palette.length)];
    piece.style.setProperty('--fall-time',(2.8+Math.random()*2.4)+'s');
    piece.style.setProperty('--drift',((-90+Math.random()*180))+'px');
    piece.style.setProperty('--start-rot',(Math.random()*360)+'deg');
    piece.style.setProperty('--end-rot',((720+Math.random()*1080))+'deg');
    piece.style.animationDelay=(Math.random()*.7)+'s';

    if(Math.random()>.5){
      piece.style.borderRadius='50%';
      piece.style.width='9px';
      piece.style.height='9px';
    }

    layer.appendChild(piece);
  }

  setTimeout(()=>layer.remove(),6000);
}

function whatsappUnitText(unitaRaw,tipoRaw){
  const u=String(unitaRaw||'').trim();
  if(!u) return '';

  const tipo=String(tipoRaw||'Appartamento').trim();
  const n=/^\d+$/.test(u) ? String(Number(u)) : u;

  if(tipo==='Box') return 'Box Numero '+n;
  return /^\d+$/.test(u) ? 'Appartamento Numero '+n : 'Appartamento '+u;
}

function whatsappPeriodFromSaved(saved){
  if(!saved) return '';
  if(saved.meseRiferimento){
    return [saved.meseRiferimento,saved.annoRiferimento].filter(Boolean).join(' ');
  }
  const dal=[saved.meseDal,saved.annoDal].filter(Boolean).join(' ');
  const al=[saved.meseAl,saved.annoAl].filter(Boolean).join(' ');
  if(dal || al) return `da ${dal || '—'} a ${al || '—'}`;
  return '';
}

function whatsappPeriodPhrase(saved){
  if(!saved) return 'periodo indicato';

  if(saved.meseRiferimento){
    const month=[saved.meseRiferimento,saved.annoRiferimento].filter(Boolean).join(' ');
    return `mese di ${month}`;
  }

  const dalMonth=String(saved.meseDal||'').trim();
  const alMonth=String(saved.meseAl||'').trim();
  const dalYear=String(saved.annoDal||'').trim();
  const alYear=String(saved.annoAl||'').trim();

  if(dalMonth && alMonth && dalYear && alYear){
    const dalIdx=MONTH_NAMES.indexOf(dalMonth);
    const alIdx=MONTH_NAMES.indexOf(alMonth);
    const monthCount=(dalIdx>=0 && alIdx>=0)
      ? ((Number(alYear)-Number(dalYear))*12 + alIdx-dalIdx+1)
      : 0;

    if(String(saved.tipo||'')==='Box' && monthCount===3){
      const yearText=dalYear===alYear ? dalYear : `${dalYear}/${alYear}`;
      return `trimestre ${dalMonth} - ${alMonth} ${yearText}`;
    }

    return `periodo da ${dalMonth} ${dalYear} a ${alMonth} ${alYear}`;
  }

  return 'periodo indicato';
}

function buildWhatsAppMessageFromSaved(saved){
  const unitText=whatsappUnitText(saved?.unita,saved?.tipo);
  const periodText=whatsappPeriodPhrase(saved);

  return [
    'Buona sera',
    `In allegato la ricevuta dell'affitto per il ${unitText} relativa al ${periodText}`,
    '',
    'Grazie mille',
    '',
    'Buona serata',
    '',
    'A presto',
    '',
    'Benetti'
  ].join('\n');
}

function resolveWhatsAppRecipient(saved){
  const override=getWhatsAppOverrideSettings();

  if(override.force){
    return {
      name:override.name || 'Destinatario test',
      phone:override.phone,
      phoneRaw:override.phoneRaw,
      forced:true
    };
  }

  if(!saved) return {name:'',phone:'',phoneRaw:'',forced:false};

  let p=null;
  const idx=parseInt(saved.personaIndex,10);
  if(Number.isFinite(idx) && PEOPLE[idx]){
    const candidate=PEOPLE[idx];
    const sameName=normalizeTenantKeyText(candidate.nominativo)===normalizeTenantKeyText(saved.nominativo);
    const sameUnit=normalizeTenantKeyText(candidate.appartamento)===normalizeTenantKeyText(saved.unita);
    if(sameName || sameUnit) p=candidate;
  }

  if(!p){
    p=PEOPLE.find(candidate=>
      normalizeTenantKeyText(candidate.nominativo)===normalizeTenantKeyText(saved.nominativo) &&
      normalizeTenantKeyText(candidate.appartamento)===normalizeTenantKeyText(saved.unita)
    ) || PEOPLE.find(candidate=>
      normalizeTenantKeyText(candidate.nominativo)===normalizeTenantKeyText(saved.nominativo)
    ) || null;
  }

  const name=String((p&&p.nominativo)||saved.nominativo||'').trim();
  const phoneRaw=String((p&&p.telefono)||saved.telefono||'').trim();
  const phone=normalizeWhatsAppPhone(phoneRaw);
  return {name,phone,phoneRaw,forced:false};
}

async function prepareWhatsAppSend(pdfName,messageText,recipient){
  if(!directoryHandle || !(await ensureFolderPermission())){
    $('status').textContent='La cartella Ricevute non è disponibile.';
    return false;
  }

  await loadWhatsAppSentLog();
  const sentBaseline=whatsappSentMap[pdfName] || '';

  // v97: MAI più protocollo ricevutewhatsapp://.
  // Anche se il Generatore viene aperto in una normale finestra/file,
  // l'invio passa sempre dal server locale che avvia l'Helper autorizzato.
  const endpoint=LOCAL_SERVER_MODE
    ? '/api/whatsapp/prepare'
    : 'http://127.0.0.1:8765/api/whatsapp/prepare';

  let res;
  try{
    res=await fetch(endpoint,{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        pdfName:String(pdfName||''),
        messageText:String(messageText||'').trim(),
        recipientName:String(recipient?.name||'').trim(),
        recipientPhone:String(recipient?.phone||'').trim()
      })
    });
  }catch(e){
    throw new Error('Server locale WhatsApp non raggiungibile. Avvia Cruscotto Affitti e riprova.');
  }

  let payload={};
  try{ payload=await res.json(); }catch(e){}

  if(!res.ok || !payload.ok){
    throw new Error(payload.error || 'Il server locale non riesce a preparare WhatsApp.');
  }

  watchWhatsAppSendStatus(pdfName,sentBaseline);
  return true;
}
async function sharePdfEntry(entry){
  if(!entry) return;

  try{
    let saved=receiptLookup[entry.name];

    // Se necessario, prova a recuperare i dati direttamente dal PDF.
    if(!saved){
      saved=await recoverLookupFromPdf(entry);
      if(saved){
        receiptLookup[entry.name]=saved;
        await saveLookup();
      }
    }

    if(!saved){
      $('status').textContent='Non riesco a ricostruire i dati di questa ricevuta, quindi non posso preparare automaticamente il messaggio WhatsApp.';
      return;
    }

    const recipient=resolveWhatsAppRecipient(saved);
    if(!recipient.phone){
      $('status').textContent=recipient.forced
        ? '“Forza invio a” è attivo ma il numero WhatsApp di test è vuoto o non valido. Apri ⚙ SetUp e correggilo.'
        : `Numero WhatsApp mancante per ${recipient.name || saved.nominativo}. Inseriscilo in ⚙ SetUp → Elenco affittuari.`;
      return;
    }
    const testo=buildWhatsAppMessageFromSaved(saved);

    const ok=await prepareWhatsAppSend(entry.name,testo,recipient);
    if(ok){
      $('status').textContent='WhatsApp: seleziono il destinatario e continuo automaticamente con PDF e messaggio…';
    }
  }catch(e){
    $('status').textContent='Impossibile preparare WhatsApp: '+e.message;
  }
}

async function shareCurrentPdf(){
  if(!currentPreviewFile || !currentPreviewName){
    $('status').textContent='Nessun PDF disponibile da inviare.';
    return;
  }

  try{
    const saved=rawFormData();
    const recipient=resolveWhatsAppRecipient(saved);
    if(!recipient.phone){
      $('status').textContent=recipient.forced
        ? '“Forza invio a” è attivo ma il numero WhatsApp di test è vuoto o non valido. Apri ⚙ SetUp e correggilo.'
        : `Numero WhatsApp mancante per ${recipient.name || saved.nominativo}. Inseriscilo in ⚙ SetUp → Elenco affittuari.`;
      return;
    }
    const testoWhatsApp=buildWhatsAppMessageFromSaved(saved);

    const ok=await prepareWhatsAppSend(currentPreviewName,testoWhatsApp,recipient);
    if(ok){
      $('status').textContent='WhatsApp: seleziono il destinatario e continuo automaticamente con PDF e messaggio…';
    }
  }catch(e){
    $('status').textContent='Impossibile preparare WhatsApp: '+e.message;
  }
}

function openPdfPreview(file, name, celebrate=false){
  currentPreviewFile=file;
  currentPreviewName=name || 'Ricevuta.pdf';

  if(currentPreviewUrl) URL.revokeObjectURL(currentPreviewUrl);
  currentPreviewUrl=URL.createObjectURL(file);
  $('pdfPreviewFrame').src=currentPreviewUrl;
  $('pdfPreviewTitle').textContent=name || 'Anteprima PDF';
  $('pdfPreviewModal').classList.add('open');
  $('pdfPreviewModal').setAttribute('aria-hidden','false');

  // I coriandoli festeggiano SOLO una ricevuta appena creata.
  if(celebrate) setTimeout(launchConfetti,250);
}
function closePdfPreview(){
  $('pdfPreviewFrame').src='about:blank';
  $('pdfPreviewModal').classList.remove('open');
  $('pdfPreviewModal').setAttribute('aria-hidden','true');
  if(currentPreviewUrl){
    URL.revokeObjectURL(currentPreviewUrl);
    currentPreviewUrl=null;
  }
  currentPreviewFile=null;
  currentPreviewName='';
}
document.addEventListener('keydown',e=>{
  const previewModal=$('pdfPreviewModal');
  const settingsModal=$('settingsModal');
  if(e.key==='Escape'){
    const choiceModal=$('existingReceiptChoiceModal');
    if(choiceModal && choiceModal.classList.contains('open')){
      resolveExistingReceiptChoice('cancel');
      return;
    }
    if(previewModal && previewModal.classList.contains('open')) closePdfPreview();
    if(settingsModal && settingsModal.classList.contains('open')) closeSettings();
  }
});



let usingRangePeriod=false;

let monthlyRentBase=0;

function parseMoneyNumber(v){
  const n=Number(String(v??'').replace(',','.'));
  return Number.isFinite(n) ? n : 0;
}

function coveredMonthsCount(){
  if(!usingRangePeriod) return 1;

  const dalMonth=monthIndexByName($('meseDal').value);
  const alMonth=monthIndexByName($('meseAl').value);
  const dalYear=parseInt($('annoDal').value,10);
  const alYear=parseInt($('annoAl').value,10);

  if(dalMonth<0 || alMonth<0 || !Number.isFinite(dalYear) || !Number.isFinite(alYear)){
    return 0;
  }

  const start=dalYear*12+dalMonth;
  const end=alYear*12+alMonth;
  if(end<start) return 0;

  return end-start+1;
}

function inferMonthlyRentBase(){
  const idx=parseInt($('persona').value,10);
  if(Number.isFinite(idx) && PEOPLE[idx]){
    const canone=Number(PEOPLE[idx].canone||0);
    if(canone>0) return canone;
  }

  const current=parseMoneyNumber($('importo').value);
  if(current<=0) return 0;

  const months=coveredMonthsCount();
  if(usingRangePeriod && months>1){
    return current/months;
  }
  return current;
}

function recalculateAmountForPeriod(){
  if(monthlyRentBase<=0){
    monthlyRentBase=inferMonthlyRentBase();
  }
  if(monthlyRentBase<=0){
    update();
    return;
  }

  const months=coveredMonthsCount();
  if(usingRangePeriod){
    if(months<=0){
      update();
      return;
    }
    $('importo').value=(monthlyRentBase*months).toFixed(2);
  }else{
    $('importo').value=monthlyRentBase.toFixed(2);
  }
  update();
}


function monthIndexByName(name){
  return MONTH_NAMES.indexOf(name);
}

function normalizeRangeFromStart(){
  const dalMonth=$('meseDal').value;
  const dalYear=parseInt($('annoDal').value,10);
  if(!dalMonth || !Number.isFinite(dalYear)) return;

  const dalIdx=monthIndexByName(dalMonth);
  if(dalIdx<0) return;

  let minAlIdx=dalIdx+1;
  let minAlYear=dalYear;
  if(minAlIdx>11){
    minAlIdx=0;
    minAlYear=dalYear+1;
  }

  const alMonth=$('meseAl').value;
  const alYear=parseInt($('annoAl').value,10);
  const alIdx=monthIndexByName(alMonth);

  const alMissing=!alMonth || !Number.isFinite(alYear);
  const alTooEarly=!alMissing && (
    alYear<minAlYear ||
    (alYear===minAlYear && alIdx<minAlIdx)
  );

  if(alMissing || alTooEarly){
    $('meseAl').value=MONTH_NAMES[minAlIdx];
    $('annoAl').value=minAlYear;
  }
}

function normalizeRangeFromEnd(){
  const alMonth=$('meseAl').value;
  const alYear=parseInt($('annoAl').value,10);
  if(!alMonth || !Number.isFinite(alYear)) return;

  const alIdx=monthIndexByName(alMonth);
  if(alIdx<0) return;

  let maxDalIdx=alIdx-1;
  let maxDalYear=alYear;
  if(maxDalIdx<0){
    maxDalIdx=11;
    maxDalYear=alYear-1;
  }

  const dalMonth=$('meseDal').value;
  const dalYear=parseInt($('annoDal').value,10);
  const dalIdx=monthIndexByName(dalMonth);

  const dalMissing=!dalMonth || !Number.isFinite(dalYear);
  const dalTooLate=!dalMissing && (
    dalYear>maxDalYear ||
    (dalYear===maxDalYear && dalIdx>maxDalIdx)
  );

  if(dalMissing || dalTooLate){
    $('meseDal').value=MONTH_NAMES[maxDalIdx];
    $('annoDal').value=maxDalYear;
  }
}

function changeRangeYear(id,delta){
  const input=$(id);
  let year=parseInt(input.value,10);
  if(!Number.isFinite(year)){
    const raw=$('dataPagamento').value;
    year=raw ? parseInt(raw.split('-')[0],10) : new Date().getFullYear();
  }
  input.value=Math.max(2000,Math.min(2100,year+delta));

  if(id==='annoDal'){
    normalizeRangeFromStart();
  }else if(id==='annoAl'){
    normalizeRangeFromEnd();
  }
  recalculateAmountForPeriod();
  updateBoxQuarterControls();
  resetCausaleFromCurrentPeriod();
}

function changeReferenceYear(delta){
  const input=$('annoRiferimento');
  let year=parseInt(input.value,10);
  if(!Number.isFinite(year)){
    const raw=$('dataPagamento').value;
    year=raw ? parseInt(raw.split('-')[0],10) : new Date().getFullYear();
  }
  year=Math.max(2000,Math.min(2100,year+delta));
  input.value=year;
  resetCausaleFromCurrentPeriod();
}

function setPeriodMode(mode){
  if(mode==='range' && currentTenantIsBox()){
    applyBoxQuarterFromPaymentDate();
    return;
  }
  if(!usingRangePeriod){
    const current=parseMoneyNumber($('importo').value);
    if(current>0) monthlyRentBase=current;
  }else if(monthlyRentBase<=0){
    monthlyRentBase=inferMonthlyRentBase();
  }

  usingRangePeriod=(mode==='range');

  $('monthMode').style.display=usingRangePeriod ? 'none' : 'block';
  $('rangeMode').classList.toggle('open',usingRangePeriod);
  $('monthChoiceBtn').classList.toggle('active',!usingRangePeriod);
  $('rangeChoiceBtn').classList.toggle('active',usingRangePeriod);

  if(usingRangePeriod){
    $('meseRiferimento').value='';
    $('annoRiferimento').value='';
    const raw=$('dataPagamento').value;
    const baseYear=raw ? Number(raw.split('-')[0]) : new Date().getFullYear();
    const baseMonth=raw ? MONTH_NAMES[Number(raw.split('-')[1])-1] : MONTH_NAMES[new Date().getMonth()];
    if(!$('meseDal').value) $('meseDal').value=baseMonth;
    if(!$('meseAl').value) $('meseAl').value=baseMonth;
    if(!$('annoDal').value) $('annoDal').value=baseYear;
    if(!$('annoAl').value) $('annoAl').value=baseYear;
  }else{
    $('meseDal').value='';
    $('meseAl').value='';
    $('annoDal').value='';
    $('annoAl').value='';
    syncMonthFromPaymentDate();
  }
  recalculateAmountForPeriod();
  updateBoxQuarterControls();
  resetCausaleFromCurrentPeriod();
}

function clearDateField(id){
  $(id).value='';
  recalculateAmountForPeriod();
  resetCausaleFromCurrentPeriod();
}

async function toggleReceiptsList(){
  const section=$('receiptsSection');
  const btn=$('receiptsToggleBtn');
  const open=!section.classList.contains('open');
  section.classList.toggle('open',open);
  btn.classList.toggle('open',open);

  if(open && directoryHandle){
    try{
      const ok=await ensureFolderPermission();
      if(ok){
        await loadTenantsFile();
        await loadLookup();
        await refreshFileList();
        $('folderStatus').textContent='Cartella ricevute collegata.';
      }else{
        $('fileList').innerHTML='<div class="muted">Autorizza l’accesso alla cartella già memorizzata.</div>';
      }
    }catch(e){
      $('fileList').innerHTML='<div class="muted">Impossibile riattivare la cartella: '+e.message+'</div>';
    }
  }
}

async function openSettings(){
  await loadWhatsAppConfig();
  if($('openStandaloneBtn')){
    $('openStandaloneBtn').style.display=isRunningInsideFrame() ? 'block' : 'none';
  }
  if(directoryHandle){
    try{
      const ok=await ensureFolderPermission();
      if(ok){
        await loadTenantsFile();
        $('folderStatus').textContent='Cartella collegata. Dati affittuari letti da Affittuari.json.';
      }
    }catch(e){}
  }
  renderTenantSetup();
  const modal=$('settingsModal');
  modal.classList.add('open');
  modal.setAttribute('aria-hidden','false');
}
function closeSettings(){
  const modal=$('settingsModal');
  modal.classList.remove('open');
  modal.setAttribute('aria-hidden','true');
}

function toggleAdvancedFields(){
  const panel=document.querySelector('.panel');
  const btn=$('advancedToggleBtn');
  const show=!panel.classList.contains('show-advanced');
  panel.classList.toggle('show-advanced',show);
  btn.textContent=show ? 'Nascondi campi' : 'Mostra più campi';
}

function initSplitter(){
  const splitter=$('splitter');
  const app=document.querySelector('.app');
  if(!splitter || !app) return;

  const saved=localStorage.getItem('ricevutePanelWidth');
  if(saved){
    const w=Math.max(320,Math.min(Number(saved),window.innerWidth-360));
    app.style.setProperty('--panel-width',w+'px');
  }

  let dragging=false;

  const start=e=>{
    if(window.innerWidth<=950) return;
    dragging=true;
    splitter.classList.add('dragging');
    document.body.style.cursor='col-resize';
    document.body.style.userSelect='none';
    e.preventDefault();
  };

  const move=e=>{
    if(!dragging) return;
    const clientX=e.touches ? e.touches[0].clientX : e.clientX;
    const w=Math.max(320,Math.min(clientX,window.innerWidth-360));
    app.style.setProperty('--panel-width',w+'px');
    localStorage.setItem('ricevutePanelWidth',String(w));
  };

  const end=()=>{
    if(!dragging) return;
    dragging=false;
    splitter.classList.remove('dragging');
    document.body.style.cursor='';
    document.body.style.userSelect='';
  };

  splitter.addEventListener('mousedown',start);
  splitter.addEventListener('touchstart',start,{passive:false});
  window.addEventListener('mousemove',move);
  window.addEventListener('touchmove',move,{passive:false});
  window.addEventListener('mouseup',end);
  window.addEventListener('touchend',end);
}

function initPreviewModal(){
  const modal=$('pdfPreviewModal');
  if(modal){
    modal.addEventListener('click',e=>{
      if(e.target===modal) closePdfPreview();
    });
  }
  const settings=$('settingsModal');
  if(settings){
    settings.addEventListener('click',e=>{
      if(e.target===settings) closeSettings();
    });
  }
}



async function loadLookup(){
  receiptLookup={};
  if(!directoryHandle) return;
  try{
    const fh=await directoryHandle.getFileHandle(LOOKUP_FILE_NAME);
    const file=await fh.getFile();
    const text=await file.text();
    const parsed=JSON.parse(text);

    // Formato corrente: { "NomeFile.pdf": {...dati...}, ... }
    // Compatibilità prudenziale con un eventuale vecchio wrapper {receipts:{...}}.
    if(parsed && typeof parsed==='object'){
      if(parsed.receipts && typeof parsed.receipts==='object'){
        receiptLookup=parsed.receipts;
      }else{
        receiptLookup=parsed;
      }
    }
  }catch(e){
    receiptLookup={};
  }
}

async function saveLookup(){
  if(!directoryHandle) return;
  const fh=await directoryHandle.getFileHandle(LOOKUP_FILE_NAME,{create:true});
  const wr=await fh.createWritable();
  await wr.write(JSON.stringify(receiptLookup,null,2));
  await wr.close();
}

function pdfUnescapeText(s){
  return s
    .replace(/\\\(/g,'(')
    .replace(/\\\)/g,')')
    .replace(/\\\\/g,'\\');
}

function displayDateToISO(s){
  const m=String(s||'').trim().match(/^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})$/);
  if(!m) return '';
  return `${m[3]}-${String(m[2]).padStart(2,'0')}-${String(m[1]).padStart(2,'0')}`;
}

function euroTextToNumber(s){
  let x=String(s||'').replace(/[€\s]/g,'');
  if(x.includes(',') && x.includes('.')){
    x=x.replace(/\./g,'').replace(',','.');
  }else if(x.includes(',')){
    x=x.replace(',','.');
  }
  const n=parseFloat(x);
  return Number.isFinite(n) ? String(n) : '';
}

function splitUnitText(unitText){
  const s=String(unitText||'').trim();
  const known=['Appartamento','Box','Garage','Posto auto','Locale'];
  for(const tipo of known){
    if(s.toLowerCase().startsWith(tipo.toLowerCase())){
      return {tipo, unita:s.slice(tipo.length).trim()};
    }
  }
  const firstSpace=s.indexOf(' ');
  if(firstSpace>0){
    return {tipo:s.slice(0,firstSpace), unita:s.slice(firstSpace+1).trim()};
  }
  return {tipo:'Appartamento', unita:s};
}

function periodToRawFields(periodo){
  const out={
    meseRiferimento:'', annoRiferimento:'',
    meseDal:'', annoDal:'', meseAl:'', annoAl:''
  };
  const p=String(periodo||'').trim();

  // Formato attuale del PDF per periodo diverso: "da Marzo 2026 a Aprile 2026"
  let m=p.match(/^da\s+(.+?)\s+(\d{4})\s+a\s+(.+?)\s+(\d{4})$/i);
  // Compatibilità con versioni più vecchie: "dal ... al ..."
  if(!m) m=p.match(/^dal\s+(.+?)\s+(\d{4})\s+al\s+(.+?)\s+(\d{4})$/i);

  if(m){
    out.meseDal=m[1].trim();
    out.annoDal=m[2];
    out.meseAl=m[3].trim();
    out.annoAl=m[4];
    return out;
  }

  m=p.match(/^(.+?)\s+(\d{4})$/);
  if(m){
    out.meseRiferimento=m[1].trim();
    out.annoRiferimento=m[2];
  }
  return out;
}

async function recoverLookupFromPdf(entry){
  try{
    const file=await entry.getFile();
    const buf=await file.arrayBuffer();

    // I PDF creati da questo programma hanno il content stream NON compresso.
    // Latin-1 mantiene una corrispondenza 1:1 byte/carattere, utile per leggerlo.
    const text=new TextDecoder('latin1').decode(buf);
    const streams=text.split('stream\n');
    let content='';

    for(let i=1;i<streams.length;i++){
      const candidate=streams[i].split('endstream')[0];
      if(candidate.includes('RICEVUTA DI AVVENUTO PAGAMENTO') &&
         candidate.includes('NOME E COGNOME') &&
         candidate.includes('IMPORTO RICEVUTO')){
        content=candidate;
        break;
      }
    }
    if(!content) return null;

    const values=[];
    const rx=/\(((?:\\.|[^\\)])*)\)\s*Tj/g;
    let match;
    while((match=rx.exec(content))!==null){
      values.push(pdfUnescapeText(match[1]));
    }

    const after=label=>{
      const i=values.indexOf(label);
      return i>=0 && i+1<values.length ? values[i+1] : '';
    };

    const nominativo=after('NOME E COGNOME');
    const unitText=after('UNITA IMMOBILIARE');
    const indirizzo=after('INDIRIZZO CONDOMINIO');
    const dataDisplay=after('DATA DEL PAGAMENTO');
    const periodo=after('PERIODO DI RIFERIMENTO');
    const importoDisplay=after('IMPORTO RICEVUTO');
    const metodo=after('METODO DI PAGAMENTO') || 'Contanti';
    const numeroRicevuta=after('N. RICEVUTA');

    if(!nominativo || !dataDisplay || !importoDisplay) return null;

    const unit=splitUnitText(unitText);
    const period=periodToRawFields(periodo);
    const personaIndex=PEOPLE.findIndex(
      p=>String(p.nominativo||'').trim().toLowerCase()===nominativo.trim().toLowerCase()
    );

    return {
      personaIndex: personaIndex>=0 ? String(personaIndex) : '',
      nominativo,
      tipo:unit.tipo || 'Appartamento',
      unita:unit.unita || '',
      indirizzo,
      importo:euroTextToNumber(importoDisplay),
      dataPagamento:displayDateToISO(dataDisplay),
      meseRiferimento:period.meseRiferimento,
      annoRiferimento:period.annoRiferimento,
      meseDal:period.meseDal,
      annoDal:period.annoDal,
      meseAl:period.meseAl,
      annoAl:period.annoAl,
      numeroRicevuta:numeroRicevuta || '',
      metodo
    };
  }catch(e){
    return null;
  }
}

async function recoverMissingLookup(files){
  let recovered=0;
  for(const entry of files){
    if(receiptLookup[entry.name]) continue;
    const restored=await recoverLookupFromPdf(entry);
    if(restored){
      receiptLookup[entry.name]=restored;
      recovered++;
    }
  }
  if(recovered>0){
    await saveLookup();
  }
  return recovered;
}

async function backupLookupFile(){
  if(!directoryHandle) return null;
  try{
    const source=await directoryHandle.getFileHandle(LOOKUP_FILE_NAME);
    const file=await source.getFile();
    const text=await file.text();

    const now=new Date();
    const stamp=
      now.getFullYear()+
      String(now.getMonth()+1).padStart(2,'0')+
      String(now.getDate()).padStart(2,'0')+'_'+
      String(now.getHours()).padStart(2,'0')+
      String(now.getMinutes()).padStart(2,'0')+
      String(now.getSeconds()).padStart(2,'0');

    const backupName=`Ricevute_Dati_backup_${stamp}.json`;
    const fh=await directoryHandle.getFileHandle(backupName,{create:true});
    const wr=await fh.createWritable();
    await wr.write(text);
    await wr.close();
    return backupName;
  }catch(e){
    return null;
  }
}

async function rebuildLookupFromAllPdfs(){
  const status=$('rebuildLookupStatus');
  if(status) status.textContent='';

  if(!directoryHandle){
    if(status) status.textContent='Prima collega la Cartella PDF.';
    return;
  }

  try{
    const ok=await ensureFolderPermission();
    if(!ok){
      if(status) status.textContent='Autorizzazione alla cartella non concessa.';
      return;
    }

    const files=[];
    for await (const entry of directoryHandle.values()){
      if(entry.kind==='file' && entry.name.toLowerCase().endsWith('.pdf')){
        files.push(entry);
      }
    }

    if(!files.length){
      if(status) status.textContent='Nessun PDF trovato nella cartella.';
      return;
    }

    const confirmed=confirm(
      `Ricostruire completamente ${LOOKUP_FILE_NAME} leggendo ${files.length} PDF?\n\n`+
      'Prima verrà creata automaticamente una copia di backup del JSON attuale.'
    );
    if(!confirmed) return;

    if(status) status.textContent=`Analisi di ${files.length} PDF in corso…`;

    const backupName=await backupLookupFile();

    const rebuilt={};
    let recovered=0;
    let skipped=0;

    for(const entry of files){
      const restored=await recoverLookupFromPdf(entry);
      if(restored){
        rebuilt[entry.name]=restored;
        recovered++;
      }else{
        skipped++;
      }
    }

    receiptLookup=rebuilt;
    await saveLookup();
    await refreshFileList();

    const backupTxt=backupName ? ` Backup: ${backupName}.` : '';
    if(status){
      status.textContent=
        `Ricostruzione completata: ${recovered} con dati, ${skipped} non ricostruibili.${backupTxt}`;
    }
    $('status').textContent=`Ricevute_Dati.json ricostruito da ${recovered} PDF.`;
  }catch(e){
    if(status) status.textContent='Errore durante la ricostruzione: '+e.message;
  }
}


function normalizeWhatsAppPhone(raw){
  // v115: il numero usato per la ricerca WhatsApp deve essere ESATTAMENTE
  // quello impostato nel SetUp/lista, eliminando solo caratteri grafici
  // come spazi, +, parentesi e trattini. Nessun prefisso 39 viene aggiunto.
  return String(raw||'').replace(/\D/g,'');
}

function getWhatsAppOverrideSettings(){
  const force=localStorage.getItem('ricevuteWhatsAppForce')==='true';
  const name=(localStorage.getItem('ricevuteWhatsAppName') || 'Destinatario test').trim();
  const phoneRaw=(localStorage.getItem('ricevuteWhatsAppPhone') || '').trim();
  const phone=normalizeWhatsAppPhone(phoneRaw);
  return {force,name,phoneRaw,phone};
}

async function saveWhatsAppConfig(){
  const status=$('whatsappSetupStatus');
  const force=!!$('whatsappForce')?.checked;
  const name=($('whatsappName')?.value || 'Destinatario test').trim();
  const phoneRaw=($('whatsappPhone')?.value || '').trim();
  const phone=normalizeWhatsAppPhone(phoneRaw);

  if(force && !phone){
    if(status) status.textContent='“Forza invio a” è attivo: inserisci prima un numero WhatsApp di test valido.';
    return false;
  }

  localStorage.setItem('ricevuteWhatsAppForce',force ? 'true' : 'false');
  localStorage.setItem('ricevuteWhatsAppName',name);
  localStorage.setItem('ricevuteWhatsAppPhone',phoneRaw);

  if(status){
    if(force){
      status.textContent=`FORZATURA ATTIVA: tutti gli invii andranno a ${name || 'Destinatario test'} — ${phoneRaw}.`;
    }else{
      status.textContent='Forzatura disattivata: ogni invio userà il numero WhatsApp presente nella lista affittuari.';
    }
  }
  return true;
}

async function loadWhatsAppConfig(){
  const cfg=getWhatsAppOverrideSettings();

  if($('whatsappForce')) $('whatsappForce').checked=cfg.force;
  if($('whatsappName')) $('whatsappName').value=cfg.name;
  if($('whatsappPhone')) $('whatsappPhone').value=cfg.phoneRaw;

  const status=$('whatsappSetupStatus');
  if(status){
    if(cfg.force){
      status.textContent=`FORZATURA ATTIVA: tutti gli invii andranno a ${cfg.name || 'Destinatario test'} — ${cfg.phoneRaw || 'numero non impostato'}.`;
    }else{
      status.textContent='Forzatura disattivata: gli invii seguono i numeri presenti nella lista affittuari.';
    }
  }
}

async function savePdfPathFile(){
  if(!directoryHandle) return false;
  if(!(await ensureFolderPermission())) return false;
  try{
    const fh=await directoryHandle.getFileHandle(PDF_PATH_FILE_NAME,{create:true});
    const wr=await fh.createWritable();
    await wr.write(JSON.stringify({
      path:DEFAULT_PDF_PATH,
      folderName:directoryHandle.name,
      savedAt:new Date().toISOString()
    },null,2));
    await wr.close();
    return true;
  }catch(e){
    return false;
  }
}

function showDefaultPdfPath(){
  const el=$('savePath');
  if(el && !el.value) el.value=DEFAULT_PDF_PATH;
}

async function saveTenantsFile(){
  if(!directoryHandle) return false;
  if(!(await ensureFolderPermission())) return false;
  const fh=await directoryHandle.getFileHandle(TENANTS_FILE_NAME,{create:true});
  const wr=await fh.createWritable();
  await wr.write(JSON.stringify(PEOPLE,null,2));
  await wr.close();
  return true;
}

async function loadTenantsFile(){
  if(!directoryHandle) return false;

  try{
    const permission=await directoryHandle.queryPermission({mode:'readwrite'});
    if(permission!=='granted') return false;

    try{
      const fh=await directoryHandle.getFileHandle(TENANTS_FILE_NAME);
      const file=await fh.getFile();
      const parsed=JSON.parse(await file.text());

      if(Array.isArray(parsed) && parsed.length){
        PEOPLE=parsed.map(p=>({
          nominativo:String(p.nominativo||''),
          tipo:String(p.tipo||'Appartamento'),
          appartamento:String(p.appartamento||''),
          indirizzo:String(p.indirizzo||''),
          canone:Number(p.canone||0),
          telefono:String(p.telefono||p.phone||'')
        }));
        const boxesAdded=syncBoxTenantsV110();
        if(boxesAdded) await saveTenantsFile();
        localStorage.setItem('ricevuteAffittuari',JSON.stringify(PEOPLE));
        populatePeople();
        return true;
      }
    }catch(e){
      // Se il file non esiste ancora, crealo dai dati di base incorporati.
      // Il localStorage resta solo una copia di sicurezza e non prevale più sul JSON.
      PEOPLE=DEFAULT_PEOPLE.map(p=>({...p}));
      syncBoxTenantsV110();
      await saveTenantsFile();
      localStorage.setItem('ricevuteAffittuari',JSON.stringify(PEOPLE));
      populatePeople();
      return true;
    }
  }catch(e){}
  return false;
}

let loadedReceiptContext=null;
let existingReceiptChoiceResolver=null;

function setLoadedReceiptContext(fileName,saved){
  loadedReceiptContext={
    fileName:String(fileName||''),
    snapshot:saved ? JSON.parse(JSON.stringify(saved)) : null
  };
  const banner=$('existingReceiptBanner');
  if(banner) banner.classList.add('open');
}

function clearLoadedReceiptContext(){
  loadedReceiptContext=null;
  const banner=$('existingReceiptBanner');
  if(banner) banner.classList.remove('open');

  if(selectedPdfElement){
    selectedPdfElement.classList.remove('selected');
    selectedPdfElement=null;
  }
  selectedPdfEntry=null;
}

function askExistingReceiptAction(fileName){
  return new Promise(resolve=>{
    existingReceiptChoiceResolver=resolve;
    $('existingReceiptChoiceFile').textContent=fileName || '';
    const modal=$('existingReceiptChoiceModal');
    modal.classList.add('open');
    modal.setAttribute('aria-hidden','false');
  });
}

function resolveExistingReceiptChoice(choice){
  const modal=$('existingReceiptChoiceModal');
  modal.classList.remove('open');
  modal.setAttribute('aria-hidden','true');

  const resolve=existingReceiptChoiceResolver;
  existingReceiptChoiceResolver=null;
  if(resolve) resolve(choice);
}

function copyNameForNewReceipt(name){
  const stamp=new Date();
  const hh=String(stamp.getHours()).padStart(2,'0');
  const mm=String(stamp.getMinutes()).padStart(2,'0');
  const ss=String(stamp.getSeconds()).padStart(2,'0');
  return String(name||'Ricevuta.pdf').replace(/\.pdf$/i,`__NUOVA_${hh}${mm}${ss}.pdf`);
}

async function clearWhatsAppSentFor(fileNames){
  if(!directoryHandle) return;
  const names=new Set((fileNames||[]).map(String).filter(Boolean));
  if(!names.size) return;

  try{
    const fh=await directoryHandle.getFileHandle(WHATSAPP_SENT_LOG_FILE);
    const file=await fh.getFile();
    const lines=(await file.text()).split(/\r?\n/).filter(Boolean);
    const kept=lines.filter(line=>{
      const tab=line.indexOf('\t');
      if(tab<0) return true;
      const fileName=line.slice(tab+1).trim();
      return !names.has(fileName);
    });

    const wr=await fh.createWritable();
    await wr.write(kept.length ? kept.join('\n')+'\n' : '');
    await wr.close();
    await loadWhatsAppSentLog();
  }catch(e){}
}

function selectedTenantRecord(){
  const idx=parseInt($('persona').value,10);
  return Number.isFinite(idx) && PEOPLE[idx] ? PEOPLE[idx] : null;
}

function selectedTenantPhone(){
  const p=selectedTenantRecord();
  return p ? String(p.telefono||'') : '';
}

function rawFormData(){
  return {
    personaIndex:$('persona').value,
    nominativo:$('cognome').value,
    tipo:$('tipo').value,
    unita:$('unita').value,
    indirizzo:$('indirizzo').value,
    importo:$('importo').value,
    dataPagamento:$('dataPagamento').value,
    meseRiferimento:$('meseRiferimento').value,
    annoRiferimento:$('annoRiferimento').value,
    meseDal:$('meseDal').value,
    annoDal:$('annoDal').value,
    meseAl:$('meseAl').value,
    annoAl:$('annoAl').value,
    numeroRicevuta:$('numeroRicevuta').value,
    causale:$('causale').value,
    metodo:$('metodo').value,
    telefono:selectedTenantPhone()
  };
}

function restoreFormData(saved){
  if(!saved) return false;
  $('persona').value =
    saved.personaIndex !== undefined &&
    [...$('persona').options].some(o=>o.value===String(saved.personaIndex))
      ? String(saved.personaIndex)
      : '';
  $('cognome').value=saved.nominativo || '';
  $('tipo').value=saved.tipo || 'Appartamento';
  $('unita').value=saved.unita || '';
  $('indirizzo').value=saved.indirizzo || '';
  $('importo').value=saved.importo || '';
  $('dataPagamento').value=saved.dataPagamento || '';
  $('meseRiferimento').value=saved.meseRiferimento || '';
  $('annoRiferimento').value=saved.annoRiferimento || (saved.dataPagamento ? saved.dataPagamento.split('-')[0] : '');
  $('meseDal').value=saved.meseDal || '';
  $('annoDal').value=saved.annoDal || '';
  $('meseAl').value=saved.meseAl || '';
  $('annoAl').value=saved.annoAl || '';
  $('numeroRicevuta').value=saved.numeroRicevuta || '';
  $('metodo').value=saved.metodo || 'Contanti';
  $('causale').value=saved.causale || '';

  usingRangePeriod=Boolean(saved.meseDal || saved.annoDal || saved.meseAl || saved.annoAl);

  const savedIdx=parseInt(saved.personaIndex,10);
  if(Number.isFinite(savedIdx) && PEOPLE[savedIdx]){
    monthlyRentBase=Number(PEOPLE[savedIdx].canone||0);
  }else{
    const savedTotal=parseMoneyNumber(saved.importo);
    const months=coveredMonthsCount();
    monthlyRentBase=(usingRangePeriod && months>1 && savedTotal>0)
      ? savedTotal/months
      : savedTotal;
  }
  if($('monthMode')) $('monthMode').style.display=usingRangePeriod ? 'none' : 'block';
  if($('rangeMode')) $('rangeMode').classList.toggle('open',usingRangePeriod);
  if($('monthChoiceBtn')) $('monthChoiceBtn').classList.toggle('active',!usingRangePeriod);
  if($('rangeChoiceBtn')) $('rangeChoiceBtn').classList.toggle('active',usingRangePeriod);

  if($('persona').value!=='' && PEOPLE[Number($('persona').value)]){
    const p=PEOPLE[Number($('persona').value)];
    $('tenantPickerButton').textContent=p.nominativo;
    document.querySelectorAll('.tenant-row').forEach(r=>r.classList.toggle('selected',r.dataset.index===$('persona').value));
  }else{
    $('tenantPickerButton').textContent=saved.nominativo || '— Seleziona dall\'elenco —';
    document.querySelectorAll('.tenant-row').forEach(r=>r.classList.remove('selected'));
  }

  if(!$('causale').value.trim()) $('causale').value=defaultCausaleFromPeriod();
  updateBoxQuarterControls();
  update();
  return true;
}

async function deletePdfEntry(entry){
  if(!entry || !directoryHandle) return;

  const name=entry.name;
  const ok=confirm(`Vuoi eliminare definitivamente il file "${name}" dal disco?`);
  if(!ok) return;

  try{
    const permitted=await ensureFolderPermission();
    if(!permitted){
      $('status').textContent='Autorizzazione alla cartella non concessa.';
      return;
    }
    await directoryHandle.removeEntry(name);
    if(receiptLookup[name]){
      delete receiptLookup[name];
      await saveLookup();
    }
    selectedPdfEntry=null;
    selectedPdfElement=null;
    $('status').textContent='PDF eliminato: '+name;
    await refreshFileList();
  }catch(e){
    $('status').textContent='Impossibile eliminare il PDF: '+e.message;
  }
}

let receiptListCache=[];
let whatsappSentMap={};
let whatsappWatchTimer=null;

function formatSentTimestamp(ts){
  const s=String(ts||'').trim();
  const m=s.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
  return m ? `${m[3]}/${m[2]}/${m[1]} ${m[4]}:${m[5]}` : s;
}

async function loadWhatsAppSentLog(){
  const map={};
  if(!directoryHandle){
    whatsappSentMap=map;
    return map;
  }
  try{
    const fh=await directoryHandle.getFileHandle(WHATSAPP_SENT_LOG_FILE);
    const file=await fh.getFile();
    const text=await file.text();
    for(const line of text.split(/\r?\n/)){
      if(!line.trim()) continue;
      const tab=line.indexOf('\t');
      if(tab<0) continue;
      const ts=line.slice(0,tab).trim();
      const name=line.slice(tab+1).trim();
      if(ts && name) map[name]=ts;
    }
  }catch(e){}
  whatsappSentMap=map;
  return map;
}

function setReceiptStats(withData=0, withoutData=0, total=0, visible=total, sent=0){
  const el=$('receiptStats');
  if(el) el.textContent=`Con dati: ${withData} • Senza dati: ${withoutData} • Inviate: ${sent} • Visualizzate: ${visible}/${total}`;
}

function renderReceiptList(){
  const list=$('fileList');
  if(!list) return;

  const q=String($('receiptFilterText')?.value || '').trim().toLowerCase();
  const status=String($('receiptFilterWhatsapp')?.value || 'all');

  const filtered=receiptListCache.filter(item=>{
    const nameOK=!q || item.entry.name.toLowerCase().includes(q);
    const sent=Boolean(item.sentAt);
    const statusOK=status==='all' || (status==='sent' && sent) || (status==='unsent' && !sent);
    return nameOK && statusOK;
  });

  list.innerHTML='';

  const withData=receiptListCache.filter(x=>x.hasData).length;
  const withoutData=receiptListCache.length-withData;
  const sentCount=receiptListCache.filter(x=>x.sentAt).length;
  setReceiptStats(withData,withoutData,receiptListCache.length,filtered.length,sentCount);

  if(!filtered.length){
    list.innerHTML='<div class="muted" style="padding:8px">Nessuna ricevuta corrisponde ai filtri impostati.</div>';
    return;
  }

  for(const item of filtered){
    const entry=item.entry;
    const div=document.createElement('div');
    div.className='file-item';

    div.title=item.hasData
      ? 'Clic per ricaricare i dati • Doppio clic per aprire l’anteprima'
      : 'Questa ricevuta non ha i dati di dettaglio salvati • Doppio clic per aprire l’anteprima';

    const nameSpan=document.createElement('div');
    nameSpan.className='file-name';

    const nameWrap=document.createElement('div');
    nameWrap.className='file-name-wrap';

    if(!item.hasData){
      const icon=document.createElement('span');
      icon.className='missing-data-icon';
      icon.textContent='!';
      icon.title='Ricevuta senza dati di dettaglio';
      nameWrap.appendChild(icon);
    }

    const textSpan=document.createElement('span');
    textSpan.textContent=entry.name;
    textSpan.style.minWidth='0';
    textSpan.style.overflow='hidden';
    textSpan.style.textOverflow='ellipsis';
    textSpan.style.whiteSpace='nowrap';
    nameWrap.appendChild(textSpan);
    nameSpan.appendChild(nameWrap);

    const sentStatus=document.createElement('div');
    sentStatus.className='sent-status'+(item.sentAt?' sent':'');
    if(item.sentAt){
      sentStatus.innerHTML=`<span class="sent-check">✓</span> Inviata<span class="sent-date">${formatSentTimestamp(item.sentAt)}</span>`;
      sentStatus.title='Invio WhatsApp completato';
    }else{
      sentStatus.textContent='— Non inviata';
      sentStatus.title='Nessun invio WhatsApp completato registrato';
    }

    const whatsappBtn=document.createElement('button');
    whatsappBtn.type='button';
    whatsappBtn.className='whatsapp-list-btn';
    whatsappBtn.title="Invia questa ricevuta via WhatsApp senza aprire l'anteprima";
    whatsappBtn.setAttribute('aria-label','Invia via WhatsApp '+entry.name);
    const waImg=document.createElement('img');
    waImg.src=WHATSAPP_ICON_DATA;
    waImg.alt='WhatsApp';
    whatsappBtn.appendChild(waImg);
    whatsappBtn.onclick=async e=>{
      e.stopPropagation();
      await sharePdfEntry(entry);
    };
    whatsappBtn.ondblclick=e=>e.stopPropagation();

    const trash=document.createElement('button');
    trash.type='button';
    trash.className='trash-btn';
    trash.textContent='🗑';
    trash.title='Elimina questo PDF';
    trash.setAttribute('aria-label','Elimina '+entry.name);
    trash.onclick=async e=>{
      e.stopPropagation();
      await deletePdfEntry(entry);
    };
    trash.ondblclick=e=>e.stopPropagation();

    div.appendChild(nameSpan);
    div.appendChild(sentStatus);
    div.appendChild(whatsappBtn);
    div.appendChild(trash);

    div.onclick=()=>{
      if(selectedPdfElement) selectedPdfElement.classList.remove('selected');
      selectedPdfEntry=entry;
      selectedPdfElement=div;
      div.classList.add('selected');
      const saved=receiptLookup[entry.name];
      if(saved){
        restoreFormData(saved);
        setLoadedReceiptContext(entry.name,saved);
        $('status').textContent='Ricevuta esistente caricata: '+entry.name;
      }else{
        clearLoadedReceiptContext();
        $('status').textContent='PDF selezionato. Nessun dato associato disponibile per questo file.';
      }
    };

    div.ondblclick=async()=>{
      try{
        const f=await entry.getFile();
        openPdfPreview(f,entry.name,false);
      }catch(e){
        $('status').textContent='Impossibile aprire il PDF: '+e.message;
      }
    };

    list.appendChild(div);
  }
}

async function watchWhatsAppSendStatus(pdfName,baseline=''){
  if(whatsappWatchTimer){
    clearInterval(whatsappWatchTimer);
    whatsappWatchTimer=null;
  }

  let checks=0;
  whatsappWatchTimer=setInterval(async()=>{
    checks++;
    try{
      await loadWhatsAppSentLog();
      const now=whatsappSentMap[pdfName] || '';
      if(now && now!==baseline){
        clearInterval(whatsappWatchTimer);
        whatsappWatchTimer=null;
        const item=receiptListCache.find(x=>x.entry.name===pdfName);
        if(item) item.sentAt=now;
        renderReceiptList();
        $('status').textContent=`WhatsApp inviato correttamente il ${formatSentTimestamp(now)}: ${pdfName}`;
        return;
      }
    }catch(e){}

    if(checks>=120){
      clearInterval(whatsappWatchTimer);
      whatsappWatchTimer=null;
    }
  },1000);
}

async function refreshFileList(){
  const list=$('fileList');
  selectedPdfEntry=null;
  selectedPdfElement=null;
  receiptListCache=[];
  list.innerHTML='';
  setReceiptStats(0,0,0,0,0);

  if(!directoryHandle){
    list.innerHTML='<div class="muted">Seleziona una cartella per visualizzare i PDF presenti.</div>';
    return;
  }

  try{
    const ok=await ensureFolderPermission();
    if(!ok){
      list.innerHTML='<div class="muted">La cartella è già memorizzata: autorizza l’accesso per vedere i PDF presenti.</div>';
      return;
    }

    const files=[];
    for await (const entry of directoryHandle.values()){
      if(entry.kind==='file' && entry.name.toLowerCase().endsWith('.pdf')) files.push(entry);
    }

    if(!files.length){
      list.innerHTML='<div class="muted">Nessun PDF presente nella cartella.</div>';
      setReceiptStats(0,0,0,0,0);
      return;
    }

    const recovered=await recoverMissingLookup(files);
    await loadWhatsAppSentLog();

    const rows=[];
    for(const entry of files){
      let fileModified=0;
      try{
        const f=await entry.getFile();
        fileModified=Number(f.lastModified||0);
      }catch(e){}

      const saved=receiptLookup[entry.name];
      const createdAt=saved && saved.createdAt ? Date.parse(saved.createdAt) : NaN;
      rows.push({
        entry,
        hasData:Boolean(saved),
        createdSort:Number.isFinite(createdAt) ? createdAt : fileModified,
        sentAt:whatsappSentMap[entry.name] || ''
      });
    }

    rows.sort((a,b)=>{
      const dt=(b.createdSort||0)-(a.createdSort||0);
      if(dt!==0) return dt;
      return b.entry.name.localeCompare(a.entry.name,'it',{numeric:true,sensitivity:'base'});
    });

    receiptListCache=rows;

    if(recovered>0){
      $('status').textContent=`Recuperati automaticamente i dati di ${recovered} ricevut${recovered===1?'a':'e'} storic${recovered===1?'a':'he'}.`;
    }

    renderReceiptList();
  }catch(e){
    list.innerHTML='<div class="muted">Impossibile leggere la cartella: '+e.message+'</div>';
  }
}

function safeFileName(s){
  return s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-zA-Z0-9._-]+/g,'_').replace(/^_+|_+$/g,'');
}
function suggestedName(d){
  const date=$('dataPagamento').value || new Date().toISOString().slice(0,10);
  const who=safeFileName(d.full==='—'?'Ricevuta':d.full);

  // AppNum: se è puramente numerico usa sempre 2 cifre (3 -> 03).
  // Per unità testuali mantiene invece il testo originale in forma sicura.
  const rawUnit=String(d.num || '').trim();
  let appNum='';
  if(/^\d+$/.test(rawUnit)){
    appNum=String(parseInt(rawUnit,10)).padStart(2,'0');
  }else{
    appNum=safeFileName(rawUnit || d.tipo);
  }

  // Periodo senza separatore tra mese e anno: Marzo2026.
  // Per un intervallo: DaMarzo2026_AAprile2026.
  let periodPart='';
  if(usingRangePeriod){
    const dalM=$('meseDal')?.value || '';
    const dalA=$('annoDal')?.value || '';
    const alM=$('meseAl')?.value || '';
    const alA=$('annoAl')?.value || '';
    const dal=safeFileName(`${dalM}${dalA}`);
    const al=safeFileName(`${alM}${alA}`);
    periodPart=`Da${dal || 'Inizio'}_A${al || 'Fine'}`;
  }else{
    const mese=$('meseRiferimento')?.value || '';
    const anno=$('annoRiferimento')?.value || '';
    periodPart=safeFileName(`${mese}${anno}`) || 'Periodo';
  }

  return `Ricevuta_${who}_AppNum${appNum}_PagatoIL${date}__Periodo_${periodPart}.pdf`;
}

// ---------- PDF minimalista A4 verticale, senza librerie esterne ----------
function latin1Bytes(str){
  // In realtà produciamo byte WinAnsi / Windows-1252.
  // Il simbolo Euro U+20AC va codificato come 0x80.
  const winAnsiMap = {
    0x20AC:0x80, // €
    0x201A:0x82, 0x0192:0x83, 0x201E:0x84, 0x2026:0x85,
    0x2020:0x86, 0x2021:0x87, 0x02C6:0x88, 0x2030:0x89,
    0x0160:0x8A, 0x2039:0x8B, 0x0152:0x8C, 0x017D:0x8E,
    0x2018:0x91, 0x2019:0x92, 0x201C:0x93, 0x201D:0x94,
    0x2022:0x95, 0x2013:0x96, 0x2014:0x97, 0x02DC:0x98,
    0x2122:0x99, 0x0161:0x9A, 0x203A:0x9B, 0x0153:0x9C,
    0x017E:0x9E, 0x0178:0x9F
  };
  const out=new Uint8Array(str.length);
  for(let i=0;i<str.length;i++){
    const c=str.charCodeAt(i);
    if(c<=0xFF){
      out[i]=c;
    }else if(winAnsiMap[c]!==undefined){
      out[i]=winAnsiMap[c];
    }else{
      out[i]=0x3F; // ? per eventuali caratteri non supportati
    }
  }
  return out;
}
function pdfEscape(s){
  return s.replace(/\\/g,'\\\\').replace(/\(/g,'\\(').replace(/\)/g,'\\)');
}

function wrapPdfText(text,maxChars=52){
  const result=[];
  const paragraphs=String(text||'').replace(/\r/g,'').split('\n');

  for(const paragraph of paragraphs){
    const words=paragraph.trim().split(/\s+/).filter(Boolean);
    if(!words.length){
      result.push('');
      continue;
    }

    let line='';
    for(const word of words){
      if(!line){
        line=word;
      }else if((line+' '+word).length<=maxChars){
        line+=' '+word;
      }else{
        result.push(line);
        line=word;
      }
    }
    if(line) result.push(line);
  }
  return result.length ? result : [''];
}
function b64ToBytes(b64){
  const bin=atob(b64), out=new Uint8Array(bin.length);
  for(let i=0;i<bin.length;i++) out[i]=bin.charCodeAt(i);
  return out;
}
function buildPDF(d){
  const W=595.28,H=841.89;

  // Nel PDF il periodo personalizzato viene espresso come "da ... a ..."
  const pdfPeriodo = usingRangePeriod
    ? d.periodo.replace(/^dal\s+/i,'da ').replace(/\s+al\s+/i,' a ')
    : d.periodo;
  const pdfCausale = usingRangePeriod
    ? d.causale.replace(/\bdal\s+/i,'da ').replace(/\s+al\s+/i,' a ')
    : d.causale;
  const objs=[];
  const addObj=(bytes)=>{ objs.push(bytes); return objs.length; };
  const strBytes=s=>latin1Bytes(s);

  const fontObj=addObj(strBytes('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'));
  const fontBoldObj=addObj(strBytes('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'));
  const imgBytes=b64ToBytes(SIG_B64);
  const imgObj=addObj(null); // placeholder

  function txt(x,y,size,text,bold=false){
    return `BT /F${bold?2:1} ${size} Tf ${x} ${y} Td (${pdfEscape(text)}) Tj ET\n`;
  }
  function line(x1,y1,x2,y2,w=0.7){ return `${w} w ${x1} ${y1} m ${x2} ${y2} l S\n`; }
  function rect(x,y,w,h){ return `0.7 w ${x} ${y} ${w} ${h} re S\n`; }

  let c='';
  c += txt(54,786,17,'RICEVUTA DI AVVENUTO PAGAMENTO',true);
  c += txt(54,769,9,'Conferma di pagamento');
  if(d.nr){ c += txt(470,786,8,'N. RICEVUTA'); c += txt(470,772,11,d.nr,true); }
  c += line(54,756,541,756,1.3);

  c += rect(54,625,487,105);
  c += txt(62,714,9,'PAGAMENTO EFFETTUATO DA',true);
  c += line(54,701,541,701);
  c += line(325,625,325,701);
  c += line(54,663,541,663);
  c += txt(62,687,7,'NOME E COGNOME'); c += txt(62,673,10,d.full,true);
  c += txt(333,687,7,'UNITA IMMOBILIARE'); c += txt(333,673,10,d.unita,true);
  c += txt(62,649,7,'INDIRIZZO CONDOMINIO'); c += txt(62,635,9,d.indirizzo,true);
  c += txt(333,649,7,'DATA DEL PAGAMENTO'); c += txt(333,635,10,d.dataPag,true);

  c += rect(54,450,487,150);
  c += txt(62,584,9,'DETTAGLIO DEL PAGAMENTO',true);
  c += line(54,571,541,571);
  c += line(325,450,325,571);
  c += line(54,530,541,530);
  c += txt(62,556,7,'PERIODO DI RIFERIMENTO'); c += txt(62,542,10,pdfPeriodo,true);
  c += txt(333,556,7,'IMPORTO RICEVUTO'); c += txt(333,540,16,d.importo,true);
  c += txt(62,516,7,'CAUSALE');

  let causaleLines=wrapPdfText(pdfCausale,52);
  let causaleFont=9;
  if(causaleLines.length>5){
    causaleLines=wrapPdfText(pdfCausale,60);
    causaleFont=8;
  }
  if(causaleLines.length>6){
    causaleLines=causaleLines.slice(0,6);
    const last=causaleLines[5];
    causaleLines[5]=(last.length>3 ? last.slice(0,-3) : last)+'...';
  }
  causaleLines.forEach((lineText,idx)=>{
    c += txt(62,502-(idx*9),causaleFont,lineText,true);
  });

  c += txt(333,516,7,'METODO DI PAGAMENTO'); c += txt(333,502,10,d.metodo,true);

  c += txt(54,414,10,'Si attesta che '+d.full+', per l\'unita '+d.unita+',');
  c += txt(54,397,10,'sita presso '+d.indirizzo+', ha effettuato in data '+d.dataPag);
  c += txt(54,380,10,'il pagamento di '+d.importo+', riferito al periodo '+pdfPeriodo+'.');

  c += txt(54,322,10,'San Giuliano Milanese, '+d.dataPag);
  const iw=145, ih=iw*(SIG_H/SIG_W);
  c += `q ${iw} 0 0 ${ih.toFixed(2)} 390 308 cm /Im1 Do Q\n`;

  const contentBytes=strBytes(c);
  const contentObj=addObj(strBytes(`<< /Length ${contentBytes.length} >>\nstream\n${c}endstream`));
  const pagesObj=addObj(null);
  const pageObj=addObj(strBytes(`<< /Type /Page /Parent ${pagesObj} 0 R /MediaBox [0 0 ${W} ${H}] /Resources << /Font << /F1 ${fontObj} 0 R /F2 ${fontBoldObj} 0 R >> /XObject << /Im1 ${imgObj} 0 R >> >> /Contents ${contentObj} 0 R >>`));
  const catalogObj=addObj(strBytes(`<< /Type /Catalog /Pages ${pagesObj} 0 R >>`));

  objs[imgObj-1] = concatBytes(
    strBytes(`<< /Type /XObject /Subtype /Image /Width ${SIG_W} /Height ${SIG_H} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${imgBytes.length} >>\nstream\n`),
    imgBytes,
    strBytes('\nendstream')
  );
  objs[pagesObj-1] = strBytes(`<< /Type /Pages /Kids [${pageObj} 0 R] /Count 1 >>`);

  let parts=[strBytes('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n')];
  let offsets=[0], pos=parts[0].length;
  for(let i=0;i<objs.length;i++){
    offsets.push(pos);
    const head=strBytes(`${i+1} 0 obj\n`);
    const tail=strBytes('\nendobj\n');
    parts.push(head,objs[i],tail);
    pos += head.length+objs[i].length+tail.length;
  }
  const xrefPos=pos;
  let x=`xref\n0 ${objs.length+1}\n0000000000 65535 f \n`;
  for(let i=1;i<offsets.length;i++) x += String(offsets[i]).padStart(10,'0')+' 00000 n \n';
  x += `trailer\n<< /Size ${objs.length+1} /Root ${catalogObj} 0 R >>\nstartxref\n${xrefPos}\n%%EOF`;
  parts.push(strBytes(x));
  return concatBytes(...parts);
}
function concatBytes(...arrs){
  let len=0; arrs.forEach(a=>len+=a.length);
  const out=new Uint8Array(len); let p=0;
  arrs.forEach(a=>{out.set(a,p);p+=a.length;});
  return out;
}
async function generatePDF(){
  update();
  const d=data();
  if(d.full==='—'){ $('status').textContent='Seleziona o inserisci il nominativo.'; return; }
  if(!$('dataPagamento').value){ $('status').textContent='Inserisci la data del pagamento.'; return; }

  const originalContext=loadedReceiptContext
    ? {fileName:loadedReceiptContext.fileName,snapshot:loadedReceiptContext.snapshot}
    : null;

  let existingAction='new';
  if(originalContext){
    existingAction=await askExistingReceiptAction(originalContext.fileName);
    if(existingAction==='cancel') return;
  }

  const pdf=buildPDF(d);
  let name=suggestedName(d);

  try{
    if(directoryHandle && await ensureFolderPermission()){
      await loadLookup();

      // Se si vuole una NUOVA ricevuta ma il nome sarebbe identico all'originale,
      // crea automaticamente un nome distinto per evitare qualsiasi sovrascrittura.
      if(originalContext && existingAction==='new' && name===originalContext.fileName){
        name=copyNameForNewReceipt(name);
      }

      const pdfBlob=new Blob([pdf],{type:'application/pdf'});
      const fh=await directoryHandle.getFileHandle(name,{create:true});
      const wr=await fh.createWritable();
      await wr.write(pdfBlob);
      await wr.close();

      const receiptRaw=rawFormData();

      if(originalContext && existingAction==='edit'){
        const oldName=originalContext.fileName;
        const oldSaved=receiptLookup[oldName] || originalContext.snapshot || {};

        // Una modifica conserva la data di creazione originaria.
        receiptRaw.createdAt=oldSaved.createdAt || new Date().toISOString();

        // Se il nome file è cambiato, elimina il vecchio PDF e la vecchia voce dati.
        if(oldName!==name){
          try{ await directoryHandle.removeEntry(oldName); }catch(e){}
          delete receiptLookup[oldName];
        }

        // Una ricevuta modificata NON può restare marcata come già inviata,
        // perché il contenuto ora è diverso.
        await clearWhatsAppSentFor([oldName,name]);
      }else{
        receiptRaw.createdAt=new Date().toISOString();
      }

      receiptLookup[name]=receiptRaw;
      await saveLookup();

      clearLoadedReceiptContext();

      $('status').textContent=
        originalContext && existingAction==='edit'
          ? 'Ricevuta esistente modificata e salvata: '+name
          : 'Nuova ricevuta salvata: '+name;

      await refreshFileList();
      openPdfPreview(pdfBlob,name,true);
    }else{
      // Fallback download browser: qui non possiamo sovrascrivere in sicurezza
      // una ricevuta esistente, quindi generiamo sempre una nuova copia.
      if(originalContext && name===originalContext.fileName){
        name=copyNameForNewReceipt(name);
      }
      const pdfBlob=new Blob([pdf],{type:'application/pdf'});
      const url=URL.createObjectURL(pdfBlob);
      const a=document.createElement('a');
      a.href=url;
      a.download=name;
      a.click();
      setTimeout(()=>URL.revokeObjectURL(url),1500);
      clearLoadedReceiptContext();
      $('status').textContent='PDF generato come nuova copia. Per gestire le modifiche alle ricevute esistenti, collega la Cartella PDF.';
      openPdfPreview(pdfBlob,name,true);
    }
  }catch(e){
    $('status').textContent='Errore durante il salvataggio: '+e.message;
  }
}

populatePeople();
showDefaultPdfPath();
if(!$('dataPagamento').value) $('dataPagamento').value=localTodayISO();
syncMonthFromPaymentDate();
restoreFolder();

if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded', ()=>{
    initPreviewModal();
    initSplitter();
  });
}else{
  initPreviewModal();
  initSplitter();
}
</script>

<div class="settings-modal" id="settingsModal" aria-hidden="true">
  <div class="settings-card">
    <div class="settings-header">
      <div class="settings-title">Configurazione</div>
      <button type="button" class="settings-close" onclick="closeSettings()">Chiudi</button>
    </div>
    <div class="settings-content">
      <label>Cartella PDF</label>
      <div class="path-row">
        <input id="savePath" readonly value="/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute">
        <button id="folderBrowseBtn" class="secondary" onclick="chooseFolder()">Sfoglia…</button>
      </div>
      <button type="button" id="openStandaloneBtn" class="secondary wide" style="display:none" onclick="openStandaloneApp()">
        Apri il programma in una scheda propria
      </button>
      <div class="status" id="folderStatus"></div>
      <p class="muted" id="folderModeNote">Percorso predefinito della mammetta. In modalità Cruscotto Affitti Local la cartella viene gestita automaticamente, senza richieste di autorizzazione da Chrome.</p>

      <div class="tenant-setup" style="margin-top:18px">
        <div class="tenant-setup-title">Invio WhatsApp — destinatario di test</div>
        <div class="muted" style="margin-bottom:8px">
          Normalmente ogni ricevuta viene inviata al numero WhatsApp presente nella riga dell’affittuario.
          Attiva <strong>Forza invio a</strong> solo durante le prove per deviare tutti gli invii al destinatario indicato qui sotto.
        </div>

        <div class="whatsapp-force-box">
          <label class="whatsapp-force-label">
            <input id="whatsappForce" type="checkbox">
            <span>Forza invio a questo destinatario</span>
          </label>
          <div class="whatsapp-force-note">
            Se attivo, il numero dell’affittuario viene ignorato e tutte le ricevute vengono inviate al numero di test qui sotto.
          </div>
        </div>

        <div class="row">
          <div>
            <label>Nome destinatario di test</label>
            <input id="whatsappName" value="Ahmed">
          </div>
          <div>
            <label>Numero WhatsApp di test</label>
            <input id="whatsappPhone" value="+39 388 691 1999" placeholder="+39 333 123 4567">
          </div>
        </div>
        <button type="button" class="setup-save wide" onclick="saveWhatsAppConfig()">Salva impostazioni WhatsApp</button>
        <div class="status" id="whatsappSetupStatus"></div>
      </div>

      <div class="tenant-setup" style="margin-top:18px">
        <div class="tenant-setup-title">Dati delle ricevute</div>
        <div class="muted" style="margin-bottom:8px">
          Se il file <strong>Ricevute_Dati.json</strong> è incompleto o è andato perso, puoi ricostruirlo leggendo tutti i PDF presenti nella Cartella PDF.
          Prima della ricostruzione viene creata una copia di backup del JSON esistente.
        </div>
        <button type="button" class="setup-save wide" onclick="rebuildLookupFromAllPdfs()">
          Ricostruisci Ricevute_Dati.json da tutti i PDF
        </button>
        <div class="status" id="rebuildLookupStatus"></div>
      </div>

      <div class="tenant-setup">
        <div class="tenant-setup-title">Elenco affittuari</div>
        <div class="muted" style="margin-bottom:8px">
          Modifica direttamente i campi nella griglia e poi premi “Salva modifiche affittuari”.
          Il file <strong>Affittuari.json</strong> nella cartella PDF è la fonte principale dei dati.
        </div>
        <div class="tenant-setup-table">
          <div class="tenant-setup-head">
            <span>Nominativo</span><span>Unità</span><span>Indirizzo</span><span>Canone (€)</span><span>Numero WhatsApp</span>
          </div>
          <div id="tenantSetupRows"></div>
        </div>
        <button type="button" class="setup-save wide" onclick="saveTenantSetup()">Salva modifiche affittuari</button>
        <div class="status" id="tenantSetupStatus"></div>
      </div>
    </div>
  </div>
</div>

<div class="preview-modal" id="pdfPreviewModal" aria-hidden="true">
  <div class="preview-box">
    <div class="preview-toolbar">
      <div class="preview-title" id="pdfPreviewTitle">Anteprima PDF</div>
      <div class="preview-actions">
        <button class="whatsapp-share" id="whatsappShareBtn" onclick="shareCurrentPdf()" title="Invia la ricevuta al numero WhatsApp associato all’affittuario">Invia via WhatsApp</button>
        <span style="font-size:11px;color:#666;white-space:nowrap">automazione completa</span>
        <button class="preview-close" onclick="closePdfPreview()">Esci dall'anteprima</button>
      </div>
    </div>
    <iframe class="preview-frame" id="pdfPreviewFrame"></iframe>
  </div>
</div>

<div class="existing-choice-modal" id="existingReceiptChoiceModal" aria-hidden="true">
  <div class="existing-choice-card">
    <div class="existing-choice-title">Questa ricevuta esiste già</div>
    <div>
      Hai caricato una ricevuta dalla lista e ora stai per generare un PDF.
      Cosa vuoi fare?
    </div>
    <div class="existing-choice-file" id="existingReceiptChoiceFile"></div>
    <div style="font-size:12px;color:#666">
      <strong>Crea una NUOVA ricevuta</strong> mantiene i dati che hai a video come punto di partenza,
      senza toccare l'originale.<br><br>
      <strong>Modifica QUESTA ricevuta</strong> sostituisce la ricevuta esistente con i dati attuali.
    </div>
    <div class="existing-choice-actions">
      <button type="button" class="existing-choice-new" onclick="resolveExistingReceiptChoice('new')">Crea una NUOVA ricevuta</button>
      <button type="button" class="existing-choice-edit" onclick="resolveExistingReceiptChoice('edit')">Modifica QUESTA ricevuta</button>
      <button type="button" class="existing-choice-cancel" onclick="resolveExistingReceiptChoice('cancel')">Annulla</button>
    </div>
  </div>
</div>

</body>
</html>

___CRUSCOTTO_PAYLOAD_HTML_9f3c1a___

cat > "$PAYLOAD_DIR/Cruscotto_Affitti_Server.py" <<'___CRUSCOTTO_PAYLOAD_SERVER_9f3c1a___'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import print_function

import json
import mimetypes
import os
import sys
import time
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs, unquote

ROOT_DIR = os.environ.get(
    "CRUSCOTTO_ROOT",
    "/Users/bless/Archivio/Appart/Ricevute Affittuari",
)
DATA_DIR = os.path.join(ROOT_DIR, "ElencoRicevute")
HTML_NAME = "Generatore_Ricevute_Condominio.html"
HTML_PATH = os.path.join(ROOT_DIR, HTML_NAME)
HOST = os.environ.get("CRUSCOTTO_HOST", "127.0.0.1")
PORT = int(os.environ.get("CRUSCOTTO_PORT", "8765"))
MAX_UPLOAD = 80 * 1024 * 1024

APP_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/CruscottoAffitti")
ENGINE_VERSION_FILE = os.path.join(APP_SUPPORT_DIR, "WhatsApp_Engine_Version.json")

def read_whatsapp_engine_info():
    try:
        with open(ENGINE_VERSION_FILE, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict) and data.get("version"):
            return data
    except Exception:
        pass
    return None

def safe_name(raw):
    name = unquote(raw or "").strip()
    if not name:
        raise ValueError("Nome file vuoto")
    if name in (".", ".."):
        raise ValueError("Nome non valido")
    if "/" in name or "\\" in name or "\x00" in name:
        raise ValueError("Percorso non valido")
    if os.path.basename(name) != name:
        raise ValueError("Percorso non valido")
    return name

def data_path(name):
    return os.path.join(DATA_DIR, safe_name(name))

class Handler(BaseHTTPRequestHandler):
    server_version = "CruscottoAffitti/7.0"

    def log_message(self, fmt, *args):
        sys.stderr.write(
            "%s - - [%s] %s\n"
            % (self.client_address[0], self.log_date_time_string(), fmt % args)
        )

    def send_no_cache(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, PUT, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")

    def send_json(self, obj, status=200):
        payload = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_no_cache()
        self.end_headers()
        self.wfile.write(payload)

    def send_error_json(self, message, status=400):
        self.send_json({"ok": False, "error": str(message)}, status=status)

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/api/health":
            self.send_json({
                "ok": True,
                "mode": "server-filesystem",
                "dataDir": DATA_DIR,
                "version": 7,
                "whatsappEngine": read_whatsapp_engine_info(),
            })
            return

        if parsed.path == "/api/fs/list":
            try:
                os.makedirs(DATA_DIR, exist_ok=True)
                items = []
                for name in os.listdir(DATA_DIR):
                    path = os.path.join(DATA_DIR, name)
                    if os.path.isfile(path):
                        st = os.stat(path)
                        items.append({
                            "kind": "file",
                            "name": name,
                            "lastModified": int(st.st_mtime * 1000),
                            "size": int(st.st_size),
                        })
                self.send_json(items)
            except Exception as exc:
                self.send_error_json(exc, 500)
            return

        if parsed.path == "/api/fs/file":
            try:
                query = parse_qs(parsed.query)
                name = safe_name((query.get("name") or [""])[0])
                path = data_path(name)
                if not os.path.isfile(path):
                    self.send_error_json("File non trovato", 404)
                    return
                with open(path, "rb") as fh:
                    data = fh.read()
                mime = mimetypes.guess_type(name)[0] or "application/octet-stream"
                st = os.stat(path)
                self.send_response(200)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("X-Last-Modified-Ms", str(int(st.st_mtime * 1000)))
                self.send_no_cache()
                self.end_headers()
                self.wfile.write(data)
            except ValueError as exc:
                self.send_error_json(exc, 400)
            except Exception as exc:
                self.send_error_json(exc, 500)
            return

        if parsed.path in ("/", "/" + HTML_NAME):
            try:
                if not os.path.isfile(HTML_PATH):
                    self.send_error_json("Generatore HTML non trovato", 404)
                    return
                with open(HTML_PATH, "rb") as fh:
                    data = fh.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.send_no_cache()
                self.end_headers()
                self.wfile.write(data)
            except Exception as exc:
                self.send_error_json(exc, 500)
            return

        self.send_error_json("Risorsa non trovata", 404)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_no_cache()
        self.end_headers()

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path == "/api/whatsapp/start":
            self.send_error_json(
                "Endpoint diagnostico non usato dalla v97. Usa /api/whatsapp/prepare.",
                409,
            )
            return

        if parsed.path == "/api/whatsapp/prepare":
            try:
                length = int(self.headers.get("Content-Length", "0") or "0")
                if length < 0 or length > 1024 * 1024:
                    self.send_error_json("Richiesta troppo grande", 413)
                    return

                raw = self.rfile.read(length).decode("utf-8")
                data = json.loads(raw or "{}")
                pdf_name = safe_name(str(data.get("pdfName") or ""))
                message_text = str(data.get("messageText") or "").strip()
                recipient_name = str(data.get("recipientName") or "").strip()
                recipient_phone = str(data.get("recipientPhone") or "").strip()

                pdf_path = data_path(pdf_name)
                if not os.path.isfile(pdf_path):
                    self.send_error_json("PDF non trovato: " + pdf_name, 404)
                    return

                os.makedirs(DATA_DIR, exist_ok=True)

                with open(os.path.join(DATA_DIR, "Ricevuta_Da_Inviare.txt"), "w", encoding="utf-8") as fh:
                    fh.write(pdf_name)

                with open(os.path.join(DATA_DIR, "Messaggio_Da_Inviare.txt"), "w", encoding="utf-8") as fh:
                    fh.write(message_text)

                # v122: il motore WhatsApp (WhatsApp_Engine.scpt) legge nome e
                # numero destinatario da WhatsApp_Destinatario.json. Prima
                # d'ora questo file non veniva mai scritto qui, quindi
                # restava quello dell'invio precedente: "Forza invio a"
                # veniva ignorato e l'invio finiva sempre al vecchio
                # destinatario salvato in questo file.
                destinatario = {"name": recipient_name, "phone": recipient_phone}
                with open(os.path.join(DATA_DIR, "WhatsApp_Destinatario.json"), "w", encoding="utf-8") as fh:
                    json.dump(destinatario, fh, ensure_ascii=False)

                helper_app = os.path.expanduser("~/Applications/Invia Ricevuta WhatsApp.app")
                if not os.path.isdir(helper_app):
                    self.send_error_json(
                        "Helper WhatsApp v97 non trovato in ~/Applications.",
                        500,
                    )
                    return

                log_path = "/tmp/Invia_Ricevuta_WhatsApp_Server.log"
                log_fh = open(log_path, "ab", 0)
                subprocess.Popen(
                    ["/usr/bin/open", helper_app],
                    stdout=log_fh,
                    stderr=log_fh,
                    close_fds=True,
                )
                log_fh.close()

                self.send_json({
                    "ok": True,
                    "prepared": pdf_name,
                    "started": "whatsapp-helper-v97",
                })
            except ValueError as exc:
                self.send_error_json(exc, 400)
            except Exception as exc:
                self.send_error_json(exc, 500)
            return

        self.send_error_json("Risorsa non trovata", 404)

    def do_PUT(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/fs/file":
            self.send_error_json("Risorsa non trovata", 404)
            return

        try:
            query = parse_qs(parsed.query)
            name = safe_name((query.get("name") or [""])[0])

            length = int(self.headers.get("Content-Length", "0") or "0")
            if length < 0 or length > MAX_UPLOAD:
                self.send_error_json("File troppo grande", 413)
                return

            payload = self.rfile.read(length)
            os.makedirs(DATA_DIR, exist_ok=True)
            target = data_path(name)
            temp = target + ".cruscotto-tmp-%d" % os.getpid()

            with open(temp, "wb") as fh:
                fh.write(payload)
                fh.flush()
                os.fsync(fh.fileno())

            os.replace(temp, target)
            self.send_json({"ok": True, "name": name, "size": len(payload)})
        except ValueError as exc:
            self.send_error_json(exc, 400)
        except Exception as exc:
            try:
                if "temp" in locals() and os.path.exists(temp):
                    os.unlink(temp)
            except Exception:
                pass
            self.send_error_json(exc, 500)

    def do_DELETE(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/fs/file":
            self.send_error_json("Risorsa non trovata", 404)
            return

        try:
            query = parse_qs(parsed.query)
            name = safe_name((query.get("name") or [""])[0])
            path = data_path(name)
            if not os.path.exists(path):
                self.send_error_json("File non trovato", 404)
                return
            if not os.path.isfile(path):
                self.send_error_json("Non è un file", 400)
                return
            os.unlink(path)
            self.send_json({"ok": True, "name": name})
        except ValueError as exc:
            self.send_error_json(exc, 400)
        except Exception as exc:
            self.send_error_json(exc, 500)

def main():
    os.makedirs(DATA_DIR, exist_ok=True)
    httpd = HTTPServer((HOST, PORT), Handler)
    print("Cruscotto Affitti server attivo su http://%s:%d" % (HOST, PORT))
    print("Dati:", DATA_DIR)
    httpd.serve_forever()

if __name__ == "__main__":
    main()

___CRUSCOTTO_PAYLOAD_SERVER_9f3c1a___

cat > "$PAYLOAD_DIR/Avvia_Cruscotto_Affitti_Server.sh" <<'___CRUSCOTTO_PAYLOAD_RUNNER_9f3c1a___'
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

___CRUSCOTTO_PAYLOAD_RUNNER_9f3c1a___

cat > "$PAYLOAD_DIR/com.letmar.cruscottoaffitti.server.plist" <<'___CRUSCOTTO_PAYLOAD_PLIST_9f3c1a___'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.letmar.cruscottoaffitti.server</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/bless/Library/Application Support/CruscottoAffitti/Avvia_Cruscotto_Affitti_Server.sh</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>ThrottleInterval</key>
  <integer>10</integer>

  <key>ProcessType</key>
  <string>Background</string>

  <key>StandardOutPath</key>
  <string>/tmp/Cruscotto_Affitti_LaunchAgent_stdout.log</string>

  <key>StandardErrorPath</key>
  <string>/tmp/Cruscotto_Affitti_LaunchAgent_stderr.log</string>
</dict>
</plist>

___CRUSCOTTO_PAYLOAD_PLIST_9f3c1a___

log "File incorporati estratti correttamente in $PAYLOAD_DIR"

# --- 2. Backup di tutto ciò che sto per sovrascrivere --------------------
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

# --- 3. Compila ed installa il motore WhatsApp v125 -----------------------

command -v osacompile >/dev/null 2>&1 || fail "osacompile non trovato: questo Mac non ha gli strumenti AppleScript. Impossibile compilare il motore WhatsApp."

TMP_SCPT="/tmp/WhatsApp_Engine_v125_$STAMP.scpt"
osacompile -o "$TMP_SCPT" "$PAYLOAD_DIR/WhatsApp_Engine_v125.applescript" 2>>"$INSTALL_LOG" \
  || fail "osacompile ha fallito la compilazione di WhatsApp_Engine_v125.applescript. Dettagli in $INSTALL_LOG"

cp -p "$TMP_SCPT" "$APP_SUPPORT/WhatsApp_Engine.scpt" \
  || fail "Non riesco a copiare WhatsApp_Engine.scpt in $APP_SUPPORT"
rm -f "$TMP_SCPT"
log "Installato: $APP_SUPPORT/WhatsApp_Engine.scpt (da v125)"

# Scrive un file di versione che il server legge e mostra nel Generatore
# HTML (badge accanto al titolo), così si vede sempre "dietro le quinte"
# quale motore WhatsApp è davvero installato, senza doversi fidare a
# occhio del numero di versione della pagina HTML (che resta v120).
ENGINE_VERSION_FILE="$APP_SUPPORT/WhatsApp_Engine_Version.json"
INSTALLED_AT_HUMAN="$(date '+%d/%m/%Y %H:%M')"
cat > "$ENGINE_VERSION_FILE" <<EOF
{
  "version": "v125",
  "installedAt": "$INSTALLED_AT_HUMAN",
  "sourceFile": "WhatsApp_Engine_v125.applescript"
}
EOF
log "Scritto: $ENGINE_VERSION_FILE (badge versione motore nel Generatore)"

# --- 4. Installa Generatore HTML v120 -------------------------------------

cp -p "$PAYLOAD_DIR/Generatore_Ricevute_Condominio_v120.html" "$HTML_TARGET" \
  || fail "Non riesco a copiare il Generatore HTML in $HTML_TARGET"
log "Installato: $HTML_TARGET (v120)"

# --- 5. Installa runner + server Python -----------------------------------

cp -p "$PAYLOAD_DIR/Avvia_Cruscotto_Affitti_Server.sh" "$APP_SUPPORT/Avvia_Cruscotto_Affitti_Server.sh" \
  || fail "Non riesco a copiare Avvia_Cruscotto_Affitti_Server.sh"
chmod +x "$APP_SUPPORT/Avvia_Cruscotto_Affitti_Server.sh"
log "Installato: $APP_SUPPORT/Avvia_Cruscotto_Affitti_Server.sh"

cp -p "$PAYLOAD_DIR/Cruscotto_Affitti_Server.py" "$APP_SUPPORT/Cruscotto_Affitti_Server.py" \
  || fail "Non riesco a copiare Cruscotto_Affitti_Server.py"
log "Installato: $APP_SUPPORT/Cruscotto_Affitti_Server.py"

# --- 6. Installa/aggiorna il LaunchAgent e riavvia il server --------------

cp -p "$PAYLOAD_DIR/com.letmar.cruscottoaffitti.server.plist" "$PLIST_TARGET" \
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

# --- 7. Pulizia file temporanei --------------------------------------------

rm -rf "$PAYLOAD_DIR"
log "Cartella di lavoro temporanea rimossa: $PAYLOAD_DIR"

# --- 8. Verifica finale ----------------------------------------------------

sleep 2
HEALTH="$(curl -s --max-time 5 http://127.0.0.1:8765/api/health 2>>"$INSTALL_LOG")"

if [ -n "$HEALTH" ]; then
  log "Server risponde: $HEALTH"
  MSG="Installazione completata.

Motore WhatsApp: v125 (diagnostica a scaglioni sul campo ricerca, il fix v124 non ha risolto)
Generatore: v120 (con badge versione motore)
Server: attivo su http://127.0.0.1:8765

Backup della versione precedente salvato in:
$BACKUP_DIR

I dati degli affittuari (ElencoRicevute) NON sono stati toccati."
  log "=== Installazione completata con successo ==="
  osascript -e "display dialog \"$MSG\" with title \"Cruscotto Affitti — Installazione v125\" buttons {\"OK\"} default button 1" >/dev/null 2>&1
else
  log "ATTENZIONE: il server non ha risposto entro 5 secondi su /api/health."
  MSG="I file sono stati installati e il backup è in:
$BACKUP_DIR

Ma il server su 127.0.0.1:8765 non ha ancora risposto.
Prova a riavviare il Mac, oppure controlla il log:
/tmp/Cruscotto_Affitti_Autostart.log"
  osascript -e "display dialog \"$MSG\" with title \"Cruscotto Affitti — Installazione v125\" buttons {\"OK\"} default button 1" >/dev/null 2>&1
fi

log "Log completo di questa installazione: $INSTALL_LOG"
exit 0
