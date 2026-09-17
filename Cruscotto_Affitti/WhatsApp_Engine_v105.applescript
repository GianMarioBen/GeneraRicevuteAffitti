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

on replaceText(findText, replaceWith, sourceText)
	set AppleScript's text item delimiters to findText
	set textItems to text items of sourceText
	set AppleScript's text item delimiters to replaceWith
	set newText to textItems as text
	set AppleScript's text item delimiters to ""
	return newText
end replaceText

on recordSuccess(pdfName)
	try
		set ts to do shell script "/bin/date '+%Y-%m-%dT%H:%M:%S%z'"
		do shell script "/usr/bin/printf '%s\\t%s\\n' " & quoted form of ts & " " & quoted form of pdfName & " >> " & quoted form of sentLogPath
	end try
end recordSuccess

on performSend(pdfPath, messageText, recipientName)
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

	if not my currentChatMatches(recipientName) then
		my appendLog("Cerco destinatario: " & recipientName)
		if not my searchRecipientByName(recipientName) then
			display alert "Chat non trovata" message "Non riesco ad aprire automaticamente la chat di “" & recipientName & "”."
			return "FAIL:CHAT"
		end if
	end if

	my appendLog("Destinatario selezionato: " & recipientName)
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

	set fullMessage to messageText & return & return & "Ciao"
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

		set jsCode to "(function(){const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>80&&r.height>18&&s.display!=='none'&&s.visibility!=='hidden'};const root=document.querySelector('#main');if(!root)return 'WAIT';const all=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].filter(vis);if(!all.length)return 'WAIT';const el=all[0];const txt=(el.value||el.innerText||el.textContent||'').trim();return txt.includes('Ciao')?'READY':'WAIT'})()"
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
end performSend

on run
	try
		do shell script "/usr/bin/touch " & quoted form of runLogPath
		my appendLog("=== Avvio Engine WhatsApp v105 ===")

		set pdfName to my readTextFile(pointerPath)
		set messageText to my readTextFile(messagePath)
		set recipientName to my getRecipientName()

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
		my appendLog("Destinatario: " & recipientName)

		set resultText to my performSend(pdfPath, messageText, recipientName)
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

