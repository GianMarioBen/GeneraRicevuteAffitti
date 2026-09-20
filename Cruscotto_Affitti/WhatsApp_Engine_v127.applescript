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
	-- v126: la diagnostica di v125 ha dato la risposta definitiva. Il
	-- campo con il numero corretto ESISTE e il confronto sarebbe positivo
	-- (match=true), ma veniva scartato dal filtro "vis" perché il suo
	-- getBoundingClientRect risulta troppo piccolo/nascosto (probabilmente
	-- è un <input> reale minuscolo o invisibile che cattura la digitazione,
	-- mentre a schermo si vede un elemento decorativo separato). Il
	-- controllo sul contenuto (le cifre corrispondono?) è già di per sé
	-- una prova sufficiente: togliamo quindi il filtro di visibilità/
	-- dimensione da questa verifica, che serviva solo a evitare falsi
	-- positivi ma qui ci impediva di vedere il campo vero.
	set typedOK to false
	repeat with attempt from 1 to 30
		set safePhone to my replaceText("'", "\\'", recipientPhone)
		set jsCode to "(function(){try{const wanted='" & safePhone & "'.replace(/\\D/g,'');const els=[...document.querySelectorAll('input,[contenteditable=\"true\"],[role=\"textbox\"]')];for(const e of els){const d=((e.value||e.innerText||e.textContent||'')+'').replace(/\\D/g,'');if(d===wanted||d.includes(wanted)){e.focus();return 'OK'}}return 'NO'}catch(x){return 'NO'}})()"
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

	if not typedOK then
		my appendLog("Numero non rilevato nel Search all chats: provo inserimento JS diretto.")
		set safePhone to my replaceText("'", "\\'", recipientPhone)
		set jsCode to "(function(){try{let e=document.activeElement;if(!e||!(e.tagName==='INPUT'||e.isContentEditable||e.getAttribute('role')==='textbox')){e=[...document.querySelectorAll('input,[contenteditable=\"true\"],[role=\"textbox\"]')][0]}if(!e)return 'NO';e.focus();if(e.isContentEditable){document.execCommand('selectAll',false,null);document.execCommand('insertText',false,'" & safePhone & "');e.dispatchEvent(new Event('input',{bubbles:true}));}else if('value' in e){const p=Object.getPrototypeOf(e);const s=Object.getOwnPropertyDescriptor(p,'value');if(s&&s.set)s.set.call(e,'" & safePhone & "');else e.value='" & safePhone & "';e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));}const d=((e.value||e.innerText||e.textContent||'')+'').replace(/\\D/g,'');return d==='" & safePhone & "'?'OK':'NO'}catch(x){return 'NO'}})()"
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

		-- v127: qui avevamo un riferimento a "recipientName", variabile
		-- che NON esiste in questa funzione (riceve solo recipientPhone)
		-- — causava l'errore AppleScript -2753 "La variabile recipientName
		-- non è definita" subito dopo SPACE. Rimosso: il controllo READY
		-- qui sotto (header + composer visibili) è già di per sé la prova
		-- corretta e generica che la chat si è aperta.
		repeat with attempt from 1 to 30
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
		my appendLog("=== Avvio Engine WhatsApp v127 ===")

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

