#!/bin/bash
# Cruscotto Affitti WhatsApp command v96
# Flusso unico: WhatsApp -> destinatario -> PDF -> messaggio -> conferma.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POINTER_FILE="$SCRIPT_DIR/Ricevuta_Da_Inviare.txt"
MESSAGE_FILE="$SCRIPT_DIR/Messaggio_Da_Inviare.txt"
CONFIG_FILE="$SCRIPT_DIR/WhatsApp_Destinatario.json"
SENT_LOG_FILE="$SCRIPT_DIR/WhatsApp_Inviati.log"
RUN_LOG="/tmp/Invia_Ricevuta_WhatsApp.log"
LOCK_DIR="/tmp/Cruscotto_Affitti_WhatsApp.lock"

log(){
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$RUN_LOG"
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "Invio già in corso: nuova richiesta ignorata."
  exit 0
fi
trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT

: > "$RUN_LOG"
log "=== Avvio WhatsApp v96 ==="

if [ ! -f "$POINTER_FILE" ]; then
  log "ERRORE: Ricevuta_Da_Inviare.txt mancante."
  osascript -e 'display alert "Ricevuta non preparata" message "Il file Ricevuta_Da_Inviare.txt non esiste."'
  exit 1
fi

PDF_NAME="$(cat "$POINTER_FILE")"
PDF_PATH="$SCRIPT_DIR/$PDF_NAME"
MESSAGE_TEXT="$(cat "$MESSAGE_FILE" 2>/dev/null || true)"
RECIPIENT_NAME="Ahmed"

if [ -f "$CONFIG_FILE" ]; then
  PARSED_NAME="$(/usr/bin/sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | /usr/bin/head -n 1)"
  if [ -n "$PARSED_NAME" ]; then RECIPIENT_NAME="$PARSED_NAME"; fi
fi

if [ -z "$PDF_NAME" ] || [ ! -f "$PDF_PATH" ]; then
  log "ERRORE: PDF non trovato: $PDF_NAME"
  osascript - "$PDF_NAME" <<'APPLESCRIPT'
on run argv
	set n to item 1 of argv
	display alert "PDF non trovato" message "Il Generatore mi ha indicato questo file:" & return & return & n & return & return & "ma non lo trovo nella cartella Ricevute."
end run
APPLESCRIPT
  exit 1
fi

log "PDF: $PDF_NAME"
log "Destinatario: $RECIPIENT_NAME"

RESULT="$(osascript - "$PDF_PATH" "$MESSAGE_TEXT" "$RECIPIENT_NAME" <<'APPLESCRIPT'
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
	if my focusWhatsAppTab() then return true

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

	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			keystroke "/" using {command down, control down}
			delay 0.45
			keystroke "a" using {command down}
			delay 0.15
			key code 51
			delay 0.2
			keystroke recipientName
			delay 0.9
			key code 36
		end tell
	end tell

	repeat with attempt from 1 to 50
		if my currentChatMatches(recipientName) then return true
		delay 0.15
	end repeat
	return false
end searchRecipientByName

on run argv
	set pdfPath to item 1 of argv
	set messageText to item 2 of argv
	set recipientName to item 3 of argv

	-- 1. RIUSA SEMPRE WhatsApp già aperto.
	-- Una nuova finestra viene creata SOLO se non esiste alcuna tab WhatsApp.
	my openWhatsAppOnlyIfMissing()
	if not my waitForWhatsAppReady() then return "FAIL:READY"

	my focusWhatsAppTab()

	-- Chiude eventuale Find di Chrome.
	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			key code 53
		end tell
	end tell
	delay 0.15

	-- 2. DESTINATARIO e, SENZA INTERROMPERSI, prosegue con l'allegato.
	if not my currentChatMatches(recipientName) then
		if not my searchRecipientByName(recipientName) then
			display alert "Chat non trovata" message "Non riesco ad aprire automaticamente la chat di “" & recipientName & "”."
			return "FAIL:CHAT"
		end if
	end if

	my focusWhatsAppTab()
	delay 0.35

	-- 3. ALLEGA.
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

	my focusWhatsAppTab()
	tell application "System Events"
		tell process "Google Chrome"
			set initialWindowCount to count of windows
		end tell
	end tell

	-- 4. DOCUMENTO.
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

	-- 5. FILE PICKER macOS.
	set pickerReady to false
	repeat with attempt from 1 to 40
		my focusWhatsAppTab()
		tell application "System Events"
			tell process "Google Chrome"
				try
					if exists sheet 1 of front window then set pickerReady to true
				end try
				if not pickerReady then
					try
						if (count of windows) > initialWindowCount then set pickerReady to true
					end try
				end if
			end tell
		end tell
		if pickerReady then exit repeat
		delay 0.15
	end repeat

	if not pickerReady then
		display alert "Selettore file non aperto" message "Non è comparsa la finestra macOS per scegliere il PDF."
		return "FAIL:PICKER"
	end if

	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			keystroke "g" using {command down, shift down}
			delay 0.35
			keystroke pdfPath
			delay 0.3
			key code 36
			delay 0.8
			key code 36
		end tell
	end tell

	-- 6. INVIA PDF.
	set attachmentSent to false
	repeat with attempt from 1 to 60
		set jsCode to "(function(){const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>8&&r.height>8&&s.display!=='none'&&s.visibility!=='hidden'};const dialogs=[...document.querySelectorAll('[role=\"dialog\"]')].filter(vis);const scope=dialogs.length?dialogs[dialogs.length-1]:document;const els=[...scope.querySelectorAll('button,[role=\"button\"],[aria-label],[title]')].filter(vis);const c=els.filter(e=>{const t=((e.getAttribute('aria-label')||'')+' '+(e.getAttribute('title')||'')+' '+(e.textContent||'')).trim().toLowerCase();return t==='invia'||t==='send'||t.includes('invia')||t.includes('send')});if(!c.length)return 'WAIT';c.sort((a,b)=>{const ra=a.getBoundingClientRect(),rb=b.getBoundingClientRect();return (rb.bottom+rb.right)-(ra.bottom+ra.right)});c[0].click();return 'OK'})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "OK" then
			set attachmentSent to true
			exit repeat
		end if
		delay 0.15
	end repeat

	if not attachmentSent then
		display alert "Invio PDF non trovato" message "Il PDF è stato scelto, ma non trovo il pulsante Invia dell’anteprima."
		return "FAIL:PDFSEND"
	end if

	-- 7. ATTENDE composer normale dopo il PDF.
	set chatReadyAfterPdf to false
	repeat with attempt from 1 to 100
		set jsCode to "(function(){const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>8&&r.height>8&&s.display!=='none'&&s.visibility!=='hidden'};const root=document.querySelector('#main');if(!root)return 'WAIT';const dialogs=[...document.querySelectorAll('[role=\"dialog\"]')].filter(vis);const composers=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].filter(vis);return (dialogs.length===0&&composers.length>0)?'READY':'WAIT'})()"
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
		display alert "WhatsApp ancora occupato" message "Il PDF sembra inviato, ma WhatsApp non è tornato al campo messaggio."
		return "FAIL:COMPOSER"
	end if

	-- 8. MESSAGGIO separato.
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

	set fullMessage to messageText & return & return & "Ciao"
	set the clipboard to fullMessage
	my focusWhatsAppTab()

	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			keystroke "v" using {command down}
		end tell
	end tell

	set textReady to false
	repeat with attempt from 1 to 40
		set jsCode to "(function(){const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>18&&s.display!=='none'&&s.visibility!=='hidden'};const root=document.querySelector('#main');if(!root)return 'WAIT';const all=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].filter(vis);if(!all.length)return 'WAIT';const el=all[0];const txt=(el.value||el.innerText||el.textContent||'').trim();el.focus();return txt.includes('Ciao')?'READY':'WAIT'})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "READY" then
			set textReady to true
			exit repeat
		end if
		delay 0.1
	end repeat

	if not textReady then
		display alert "Messaggio non scritto" message "Il PDF è stato inviato, ma il testo non è comparso nel campo messaggio."
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

	-- 9. Conferma che il composer si sia svuotato.
	set sendConfirmed to false
	repeat with attempt from 1 to 60
		set jsCode to "(function(){const root=document.querySelector('#main');if(!root)return 'WAIT';const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>18&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].filter(vis);if(!all.length)return 'WAIT';const txt=(all[0].value||all[0].innerText||all[0].textContent||'').trim();return txt.includes('Ciao')?'WAIT':'SENT'})()"
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
end run
APPLESCRIPT
)"

log "AppleScript risultato: $RESULT"

if [ "$RESULT" = "SUCCESS" ]; then
  printf '%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$PDF_NAME" >> "$SENT_LOG_FILE"
  log "SUCCESS: PDF e messaggio inviati."
  exit 0
fi

log "FAIL: $RESULT"
exit 1
