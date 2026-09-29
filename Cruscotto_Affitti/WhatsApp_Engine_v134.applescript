property dataDir : "/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute"
property pointerPath : "/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute/Ricevuta_Da_Inviare.txt"
property messagePath : "/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute/Messaggio_Da_Inviare.txt"
property configPath : "/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute/WhatsApp_Destinatario.json"
property sentLogPath : "/Users/bless/Archivio/Appart/Ricevute Affittuari/ElencoRicevute/WhatsApp_Inviati.log"
property runLogPath : "/tmp/Invia_Ricevuta_WhatsApp_Helper_v97.log"

-- v132: frammenti JavaScript condivisi (nessun doppio apice al loro interno)
property jsVis : "const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};"
property jsDocEl : "const docEl=()=>{const w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);let n;while((n=w.nextNode())){const t=(n.nodeValue||'').trim().toLowerCase();if((t==='documento'||t==='document')&&n.parentElement&&vis(n.parentElement)){return n.parentElement.closest('[role=button],[role=menuitem],button,li')||n.parentElement}}return null};"
property jsScr : "const scr=el=>{const r=el.getBoundingClientRect();return Math.round(window.screenX+r.left+r.width/2)+'|'+Math.round(window.screenY+(window.outerHeight-window.innerHeight)+r.top+r.height/2)};"
property jsHits : "const hits=(onlyVis)=>{const f=new Set();const w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);let n;while((n=w.nextNode())){if(n.nodeValue&&n.nodeValue.indexOf(name)>=0&&n.parentElement)f.add(n.parentElement)}document.querySelectorAll('[title]').forEach(e=>{if((e.getAttribute('title')||'').indexOf(name)>=0)f.add(e)});document.querySelectorAll('body *').forEach(e=>{const t=e.textContent;if(t&&t.length<name.length+300&&t.indexOf(name)>=0){let c=false;for(const k of e.children){if((k.textContent||'').indexOf(name)>=0){c=true;break}}if(!c)f.add(e)}});const a=[...f];return onlyVis?a.filter(vis):a};"

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

on isTestSend()
	-- v129: "Forza invio a" nel SetUp -> il server scrive "isTest":true in
	-- WhatsApp_Destinatario.json. In quel caso NON dobbiamo registrare il
	-- successo in WhatsApp_Inviati.log, altrimenti il Generatore
	-- segnerebbe come "Inviata" una ricevuta che e' stata mandata solo al
	-- numero di test, non al vero affittuario.
	try
		set shellCmd to "/usr/bin/grep -o '\"isTest\"[[:space:]]*:[[:space:]]*true' " & quoted form of configPath
		do shell script shellCmd
		return true
	on error
		return false
	end try
end isTestSend

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

	-- v128: WhatsApp Web è di nuovo cambiato (Mario: con due TAB ora ci si
	-- ferma sul pulsante "Tutte", il filtro sopra la lista chat). Mario ha
	-- verificato manualmente che, con il numero scritto nel campo ricerca,
	-- basta premere INVIO per selezionare direttamente la chat. Proviamolo
	-- come primo tentativo, il più semplice e diretto: se funziona, evitiamo
	-- del tutto il click simulato e i TAB, che restano comunque come rete
	-- di sicurezza subito sotto se questo primo tentativo non bastasse.
	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			key code 36
		end tell
	end tell

	set returnDirectWorked to false
	repeat with attempt from 1 to 30
		set jsCode to "(function(){try{const root=document.querySelector('#main');if(!root)return 'WAIT';const h=root.querySelector('header');const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return r.width>20&&r.height>15&&s.display!=='none'&&s.visibility!=='hidden'};const composer=[...root.querySelectorAll('footer textarea,footer [contenteditable=\"true\"],footer [role=\"textbox\"]')].find(vis);return (h&&composer)?'READY':'WAIT'}catch(e){return 'WAIT'}})()"
		try
			set jsResult to my runWhatsAppJS(jsCode)
		on error
			set jsResult to "WAIT"
		end try
		if jsResult is "READY" then
			set returnDirectWorked to true
			exit repeat
		end if
		delay 0.15
	end repeat

	if returnDirectWorked then
		my appendLog("Chat aperta con INVIO diretto dopo il numero (nessun click/TAB necessario).")
		return true
	end if

	my appendLog("INVIO diretto non ha aperto la chat: provo con click sulla riga + TAB+TAB+SPACE come rete di sicurezza.")

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

on waitForFilePicker(initialWindowCount, maxTries)
	-- Il selettore file di Chrome su macOS compare come "sheet" attaccato
	-- alla finestra, oppure come finestra in più: basta uno dei due.
	repeat with attempt from 1 to maxTries
		set found to false
		tell application "System Events"
			tell process "Google Chrome"
				try
					if exists sheet 1 of front window then set found to true
				end try
				if not found then
					try
						if (count of windows) > initialWindowCount then set found to true
					end try
				end if
			end tell
		end tell
		if found then return true
		delay 0.15
	end repeat
	return false
end waitForFilePicker

-- ===================================================================
-- v132: allegato PDF senza selettore file macOS
-- ===================================================================
-- Dopo l'aggiornamento di WhatsApp Web (28/09/2026) il vecchio metodo
-- (clic su "+" e "Documento" + selettore file macOS + Cmd+Shift+G) non
-- funziona più in modo affidabile. In più la ricerca del "+" accettava
-- qualunque elemento contenente "allegato", e nella chat ci sono ormai i
-- messaggi "In allegato la ricevuta...": veniva cliccato un messaggio.
-- Ora il PDF viene letto dal disco e consegnato direttamente a WhatsApp
-- dentro la pagina (DataTransfer), in quest'ordine:
--   A: campo file per documenti già presente nella pagina
--   B: campo file che compare aprendo il menu "+" (trovato in modo stretto)
--   C: incolla del file nel campo messaggio
--   D: trascinamento simulato del file sulla chat
--   E: solo come ultima risorsa, il vecchio selettore file macOS, ma SOLO
--      se il selettore è davvero aperto (mai più testo nella barra Trova).
-- L'anteprima e l'invio sono verificati confrontando gli elementi con il
-- nome del PDF presenti PRIMA dell'allegato con quelli comparsi DOPO, così
-- un vecchio messaggio con lo stesso PDF non può dare falsi positivi.

on jsTry(jsCode)
	try
		set r to my runWhatsAppJS(jsCode)
		if r is missing value then return ""
		return r as text
	on error errMsg
		return "ERR:" & errMsg
	end try
end jsTry

on pdfJS(safePdfName, body)
	return "(function(){try{" & jsVis & "const name='" & safePdfName & "';" & jsHits & body & "}catch(x){return 'ERR:'+x}})()"
end pdfJS

on menuDocumentoVisible()
	set r to my jsTry("(function(){try{" & jsVis & jsDocEl & "return docEl()?'MENU':'NOMENU'}catch(x){return 'NOMENU'}})()")
	return (r is "MENU")
end menuDocumentoVisible

on parseClickPoint(r)
	-- "CLICK|x|y|..." -> {x, y}; altrimenti {}
	try
		set AppleScript's text item delimiters to "|"
		set parts to text items of r
		set AppleScript's text item delimiters to ""
		if (count of parts) < 3 then return {}
		if (item 1 of parts) is not "CLICK" then return {}
		return {(item 2 of parts) as integer, (item 3 of parts) as integer}
	on error
		set AppleScript's text item delimiters to ""
		return {}
	end try
end parseClickPoint

on clickScreenPoint(pt)
	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			click at pt
		end tell
	end tell
end clickScreenPoint

on openAttachMenu()
	if my menuDocumentoVisible() then return "GIA_APERTO"
	-- Il "+" si cerca SOLO nella barra del messaggio in basso (footer), per
	-- etichetta che INIZIA con "Allega"/"Attach" o per icona plus/attach:
	-- mai per testo contenuto, altrimenti si clicca un messaggio della chat.
	set jsCode to "(function(){try{" & jsVis & jsScr & "const main=document.querySelector('#main');if(!main)return 'NOMAIN';const mr=main.getBoundingClientRect();const root=main.querySelector('footer')||main;const lab=e=>((e.getAttribute('aria-label')||'')+'|'+(e.getAttribute('title')||'')).toLowerCase();const icon=e=>{const s=e.matches('[data-icon]')?e:e.querySelector('[data-icon]');return s?(s.getAttribute('data-icon')||'').toLowerCase():''};const cands=[...root.querySelectorAll('button,[role=button],[aria-label],[title],[data-icon]')].filter(vis).filter(e=>e.getBoundingClientRect().top>mr.bottom-140);const labOk=e=>lab(e).split('|').some(p=>{p=p.trim();return p.indexOf('allega')===0||p.indexOf('attach')===0});let el=cands.find(labOk);if(!el)el=cands.find(e=>{const i=icon(e);return i.indexOf('plus')>=0||i.indexOf('attach')>=0||i.indexOf('clip')>=0});if(!el)return 'NOBTN candidati='+cands.length;const b=el.closest('button,[role=button]')||el;const pt=scr(b);b.click();return 'CLICK|'+pt+'|'+lab(b)+'/'+icon(b)}catch(x){return 'ERR '+x}})()"
	set r to my jsTry(jsCode)
	my appendLog("Pulsante + (Allega): " & r)
	if r does not start with "CLICK" then return "NON_TROVATO"
	repeat with i from 1 to 8
		delay 0.15
		if my menuDocumentoVisible() then return "APERTO_JS"
	end repeat
	set pt to my parseClickPoint(r)
	if (count of pt) is 2 then
		my appendLog("Menu Allega non aperto dal click JavaScript: click reale sul + a " & (item 1 of pt) & "," & (item 2 of pt))
		my clickScreenPoint(pt)
		repeat with i from 1 to 12
			delay 0.15
			if my menuDocumentoVisible() then return "APERTO_CLICK_REALE"
		end repeat
	end if
	return "NON_APERTO"
end openAttachMenu

on waitPdfPreview(safePdfName, maxTries)
	repeat with i from 1 to maxTries
		set r to my jsTry(my pdfJS(safePdfName, "const fresh=hits(true).filter(e=>!e.hasAttribute('data-cruscotto-old'));if(!fresh.length)return 'WAIT';fresh.forEach(e=>e.setAttribute('data-cruscotto-preview','1'));return 'READY '+fresh.length;"))
		if r starts with "READY" then return true
		delay 0.15
	end repeat
	return false
end waitPdfPreview

on legacyPickerAttach(pdfPath)
	set m to my openAttachMenu()
	my appendLog("Metodo E: menu Allega = " & m)
	if m is "NON_TROVATO" or m is "NON_APERTO" then return "FAIL:ATTACH"
	tell application "System Events"
		tell process "Google Chrome"
			set initialWindowCount to count of windows
		end tell
	end tell
	set r to my jsTry("(function(){try{" & jsVis & jsDocEl & "const el=docEl();if(!el)return 'NODOC';el.click();return 'OK'}catch(x){return 'ERR '+x}})()")
	my appendLog("Metodo E: click JavaScript su Documento = " & r)
	set pickerOpen to my waitForFilePicker(initialWindowCount, 14)
	if not pickerOpen then
		set pr to my jsTry("(function(){try{" & jsVis & jsDocEl & jsScr & "const el=docEl();if(!el)return 'NODOC';return 'CLICK|'+scr(el)}catch(x){return 'ERR'}})()")
		set pt to my parseClickPoint(pr)
		if (count of pt) is 2 then
			my appendLog("Metodo E: click reale su Documento a " & (item 1 of pt) & "," & (item 2 of pt))
			my clickScreenPoint(pt)
			set pickerOpen to my waitForFilePicker(initialWindowCount, 20)
		else
			my appendLog("Metodo E: voce Documento non visibile (" & pr & ")")
		end if
	end if
	if not pickerOpen then
		tell application "System Events"
			tell process "Google Chrome"
				key code 53
			end tell
		end tell
		return "FAIL:PICKER"
	end if
	my appendLog("Metodo E: selettore file macOS aperto, scelgo il PDF.")
	delay 0.4
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
	my appendLog("Metodo E: percorso PDF passato al selettore macOS: " & pdfPath)
	return "OK"
end legacyPickerAttach

on attachAndSendPdf(pdfPath, messageText)
	set pdfNameOnly to do shell script "/usr/bin/basename " & quoted form of pdfPath
	set safePdfName to my replaceText("'", "\\'", pdfNameOnly)

	-- Fotografia di partenza: tutto ciò che mostra già il nome del PDF
	-- (per esempio un vecchio invio di prova) viene marcato come "vecchio".
	set r to my jsTry(my pdfJS(safePdfName, "document.querySelectorAll('[data-cruscotto-old],[data-cruscotto-preview],[data-cruscotto-pdf-send]').forEach(e=>{e.removeAttribute('data-cruscotto-old');e.removeAttribute('data-cruscotto-preview');e.removeAttribute('data-cruscotto-pdf-send')});const h=hits(false);h.forEach(e=>e.setAttribute('data-cruscotto-old','1'));return 'BASE '+h.length;"))
	my appendLog("Riferimenti al PDF già presenti in pagina prima dell'allegato: " & r)

	set fileLoaded to false
	try
		set pdfSize to do shell script "/usr/bin/stat -f%z " & quoted form of pdfPath
		set b64 to do shell script "/usr/bin/base64 < " & quoted form of pdfPath & " | /usr/bin/tr -d '\\n'"
		set r to my jsTry("(function(){try{const b=atob('" & b64 & "');const u=new Uint8Array(b.length);for(let i=0;i<b.length;i++)u[i]=b.charCodeAt(i);window.__cruscottoPdf=new File([u],'" & safePdfName & "',{type:'application/pdf',lastModified:Date.now()});return 'FILE:'+window.__cruscottoPdf.size}catch(x){return 'ERR '+x}})()")
		set b64 to ""
		my appendLog("PDF caricato nella pagina WhatsApp: " & r & " (byte su disco: " & pdfSize & ")")
		if r is ("FILE:" & pdfSize) then set fileLoaded to true
	on error errMsg
		my appendLog("Impossibile caricare il PDF nella pagina: " & errMsg)
	end try

	set previewOK to false
	set usedMethod to ""
	set jsInputStrict to "(function(){try{const f=window.__cruscottoPdf;if(!f)return 'NOFILE';const ins=[...document.querySelectorAll('input[type=file]')];const acc=i=>(i.getAttribute('accept')||'').toLowerCase().trim();const list=ins.map(i=>'['+acc(i)+']').join(' ');const inp=ins.find(i=>acc(i)==='*');if(!inp)return 'NOINPUT '+ins.length+' '+list;const dt=new DataTransfer();dt.items.add(f);inp.files=dt.files;inp.dispatchEvent(new Event('input',{bubbles:true}));inp.dispatchEvent(new Event('change',{bubbles:true}));return 'OK '+ins.length+' '+list}catch(x){return 'ERR '+x}})()"
	set jsInputMenu to "(function(){try{const f=window.__cruscottoPdf;if(!f)return 'NOFILE';const ins=[...document.querySelectorAll('input[type=file]')];const acc=i=>(i.getAttribute('accept')||'').toLowerCase().trim();const list=ins.map(i=>'['+acc(i)+']').join(' ');let inp=ins.find(i=>acc(i)==='*');if(!inp)inp=ins.find(i=>{const a=acc(i);return a===''||a.indexOf('pdf')>=0||a.indexOf('application')>=0||a.indexOf('*/*')>=0});if(!inp)return 'NOINPUT '+ins.length+' '+list;const dt=new DataTransfer();dt.items.add(f);inp.files=dt.files;inp.dispatchEvent(new Event('input',{bubbles:true}));inp.dispatchEvent(new Event('change',{bubbles:true}));return 'OK '+ins.length+' '+list}catch(x){return 'ERR '+x}})()"

	if fileLoaded then
		-- A: campo file per documenti già presente
		set r to my jsTry(jsInputStrict)
		my appendLog("Metodo A (campo file documenti già presente): " & r)
		if r starts with "OK" then
			if my waitPdfPreview(safePdfName, 20) then
				set previewOK to true
				set usedMethod to "A"
			end if
		end if

		-- B: apro il menu "+" e uso il campo file che compare
		if not previewOK then
			set m to my openAttachMenu()
			my appendLog("Menu Allega: " & m)
			delay 0.4
			set r to my jsTry(jsInputMenu)
			my appendLog("Metodo B (campo file del menu Allega): " & r)
			if r starts with "OK" then
				if my waitPdfPreview(safePdfName, 20) then
					set previewOK to true
					set usedMethod to "B"
				end if
			end if
		end if

		-- C: incollo il file nel campo messaggio
		if not previewOK then
			set r to my jsTry("(function(){try{" & jsVis & "const f=window.__cruscottoPdf;if(!f)return 'NOFILE';const main=document.querySelector('#main');if(!main)return 'NOMAIN';const ft=main.querySelector('footer')||main;const boxes=[...ft.querySelectorAll('[contenteditable=true],[role=textbox]')].filter(vis);const box=boxes[boxes.length-1];if(!box)return 'NOBOX';box.focus();const dt=new DataTransfer();dt.items.add(f);box.dispatchEvent(new ClipboardEvent('paste',{clipboardData:dt,bubbles:true,cancelable:true}));return 'OK'}catch(x){return 'ERR '+x}})()")
			my appendLog("Metodo C (incolla il file nel campo messaggio): " & r)
			if r starts with "OK" then
				if my waitPdfPreview(safePdfName, 20) then
					set previewOK to true
					set usedMethod to "C"
				end if
			end if
		end if

		-- D: trascinamento simulato del file sulla chat
		if not previewOK then
			set r to my jsTry("(function(){try{const f=window.__cruscottoPdf;if(!f)return 'NOFILE';const t=document.querySelector('#main')||document.body;const dt=new DataTransfer();dt.items.add(f);const o={dataTransfer:dt,bubbles:true,cancelable:true};t.dispatchEvent(new DragEvent('dragenter',o));t.dispatchEvent(new DragEvent('dragover',o));window.__cruscottoDT=dt;return 'OK'}catch(x){return 'ERR '+x}})()")
			delay 0.6
			set r2 to my jsTry("(function(){try{const dt=window.__cruscottoDT;if(!dt)return 'NODT';const main=document.querySelector('#main')||document.body;const b=main.getBoundingClientRect();const t=document.elementFromPoint(b.left+b.width/2,b.top+b.height/2)||main;const o={dataTransfer:dt,bubbles:true,cancelable:true};t.dispatchEvent(new DragEvent('dragover',o));t.dispatchEvent(new DragEvent('drop',o));return 'OK '+(t.tagName||'')}catch(x){return 'ERR '+x}})()")
			my appendLog("Metodo D (trascina il file sulla chat): " & r & " / " & r2)
			if r2 starts with "OK" then
				if my waitPdfPreview(safePdfName, 20) then
					set previewOK to true
					set usedMethod to "D"
				end if
			end if
		end if
	end if

	-- E: ultima risorsa, vecchio selettore file macOS (solo se si apre davvero)
	if not previewOK then
		set r to my legacyPickerAttach(pdfPath)
		my appendLog("Metodo E (selettore file macOS): " & r)
		if r is "OK" then
			if my waitPdfPreview(safePdfName, 100) then
				set previewOK to true
				set usedMethod to "E"
			end if
		else if r is "FAIL:PICKER" then
			display alert "PDF non allegato" message "Non sono riuscita ad allegare il PDF in nessun modo (e il selettore file non si è aperto). Mi fermo senza scrivere nulla altrove." & return & return & pdfNameOnly
			return "FAIL:PICKER"
		end if
	end if

	if not previewOK then
		my appendLog("FAIL: anteprima PDF non comparsa: " & pdfNameOnly)
		display alert "Anteprima PDF non comparsa" message "WhatsApp non ha caricato il PDF:" & return & return & pdfNameOnly & return & return & "Quindi NON considero il documento inviato."
		return "FAIL:PDFPREVIEW"
	end if
	my appendLog("Anteprima PDF comparsa (metodo " & usedMethod & "): " & pdfNameOnly)

	-- L'anteprima può comporsi in più passaggi: dopo un attimo marchiamo di
	-- nuovo tutti gli elementi nuovi come "anteprima".
	delay 0.8
	set r to my jsTry(my pdfJS(safePdfName, "const fresh=hits(true).filter(e=>!e.hasAttribute('data-cruscotto-old'));fresh.forEach(e=>e.setAttribute('data-cruscotto-preview','1'));return 'ANTEPRIMA '+fresh.length;"))
	my appendLog("Elementi dell'anteprima: " & r)

	-- v133: il testo va come DIDASCALIA del PDF, così arriva un unico
	-- messaggio (PDF + testo). Se la didascalia non riesce la ripulisco e
	-- il testo verrà mandato dopo, come messaggio separato (metodo di prima).
	set captionUsed to false
	if messageText is not "" then
		set r to my jsTry("(function(){try{" & jsVis & "const prev=[...document.querySelectorAll('[data-cruscotto-preview]')].filter(e=>e.isConnected&&vis(e));if(!prev.length)return 'NOPREVIEW';const main=document.querySelector('#main');const footer=main?main.querySelector('footer'):null;const ok=e=>vis(e)&&!(footer&&footer.contains(e))&&!e.closest('#side');let p=prev[0];for(let d=0;d<16&&p;d++,p=p.parentElement){const c=[...p.querySelectorAll('[contenteditable=true],[role=textbox]')].filter(ok);if(c.length){const t=c[c.length-1];document.querySelectorAll('[data-cruscotto-caption]').forEach(e=>e.removeAttribute('data-cruscotto-caption'));t.setAttribute('data-cruscotto-caption','1');t.focus();try{t.click()}catch(x){}return 'OK livello='+d}}return 'NOCAPTION'}catch(x){return 'ERR '+x}})()")
		my appendLog("Campo didascalia dell'anteprima: " & r)
		if r starts with "OK" then
			set the clipboard to messageText
			delay 0.2
			tell application "System Events"
				tell process "Google Chrome"
					set frontmost to true
					keystroke "v" using {command down}
				end tell
			end tell
			set capState to ""
			repeat with attempt from 1 to 20
				delay 0.15
				set capState to my jsTry("(function(){try{const c=document.querySelector('[data-cruscotto-caption]');if(!c)return 'NONE';const t=(c.innerText||c.textContent||'');return t.indexOf('Benetti')>=0?'OK':(t.trim().length?'PARTIAL':'EMPTY')}catch(x){return 'ERR'}})()")
				if capState is "OK" then exit repeat
			end repeat
			if capState is "OK" then
				set captionUsed to true
				my appendLog("Testo inserito come didascalia del PDF: verrà inviato un unico messaggio.")
			else
				my appendLog("Didascalia non riuscita (" & capState & "): la ripulisco e mando il testo come messaggio separato.")
				if capState is "PARTIAL" then
					my jsTry("(function(){try{const c=document.querySelector('[data-cruscotto-caption]');if(c){c.focus()}return 'OK'}catch(x){return 'ERR'}})()")
					tell application "System Events"
						tell process "Google Chrome"
							set frontmost to true
							keystroke "a" using {command down}
							delay 0.1
							key code 51
						end tell
					end tell
					delay 0.3
				end if
			end if
		end if
	end if

	set sendClicked to false
	repeat with attempt from 1 to 35
		set r to my jsTry("(function(){try{" & jsVis & "const prev=[...document.querySelectorAll('[data-cruscotto-preview]')].filter(e=>e.isConnected&&vis(e));if(!prev.length)return 'NOPREVIEW';const isSend=e=>{const l=((e.getAttribute('aria-label')||'')+'|'+(e.getAttribute('title')||'')).toLowerCase();const ic=(e.getAttribute('data-icon')||'').toLowerCase();return ic.indexOf('send')>=0||l.split('|').some(p=>{p=p.trim();return p.indexOf('invia')===0||p.indexOf('send')===0})};let p=prev[0];for(let d=0;d<16&&p;d++,p=p.parentElement){const bs=[...p.querySelectorAll('button,[role=button],[aria-label],[title],[data-icon]')].filter(vis).filter(isSend);if(bs.length){const b=bs[bs.length-1];const t=b.closest('button,[role=button]')||b;t.setAttribute('data-cruscotto-pdf-send','1');t.click();return 'OK livello='+d+' '+(t.getAttribute('aria-label')||'')+'/'+(b.getAttribute('data-icon')||'')}}return 'WAIT'}catch(x){return 'WAIT'}})()")
		if r starts with "OK" then
			set sendClicked to true
			my appendLog("Clic su Invia dell'anteprima PDF: " & r)
			exit repeat
		end if
		delay 0.15
	end repeat

	if not sendClicked then
		my appendLog("Pulsante Invia dell'anteprima non trovato: provo con il tasto Invio.")
		my focusWhatsAppTab()
		delay 0.3
		tell application "System Events"
			tell process "Google Chrome"
				set frontmost to true
				key code 36
			end tell
		end tell
	end if

	-- Conferma: l'anteprima deve chiudersi E deve comparire un elemento
	-- NUOVO con il nome del PDF (il messaggio appena inviato).
	set pdfSent to false
	set lastState to ""
	repeat with attempt from 1 to 160
		set r to my jsTry(my pdfJS(safePdfName, "const prev=[...document.querySelectorAll('[data-cruscotto-preview]')].filter(e=>e.isConnected&&vis(e));if(prev.length)return 'OPEN';const fresh=hits(true).filter(e=>!e.hasAttribute('data-cruscotto-old')&&!e.hasAttribute('data-cruscotto-preview'));return fresh.length?'SENT':'CLOSED';"))
		set lastState to r
		if r is "SENT" then
			set pdfSent to true
			exit repeat
		end if
		delay 0.15
	end repeat

	if not pdfSent then
		my appendLog("FAIL: PDF non confermato nella chat (ultimo stato: " & lastState & ").")
		if lastState is "OPEN" then
			display alert "PDF non inviato" message "L’anteprima del PDF è ancora aperta: non sono riuscita a premere Invia." & return & return & pdfNameOnly
			return "FAIL:PDFSEND"
		end if
		display alert "PDF non inviato" message "Non trovo il documento nella conversazione:" & return & return & pdfNameOnly & return & return & "Quindi interrompo prima di scrivere il messaggio."
		return "FAIL:PDFNOTINCHAT"
	end if

	my appendLog("PDF REALMENTE inviato e verificato nella chat: " & pdfNameOnly)
	if captionUsed then return "OK_CAPTION"
	return "OK"
end attachAndSendPdf

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

	set attachResult to my attachAndSendPdf(pdfPath, messageText)
	if attachResult is "OK_CAPTION" then return "SUCCESS"
	if attachResult is not "OK" then return attachResult

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

on minimizeOtherChromeWindows()
	-- v130: da quando esiste il launcher "Cruscotto Affitti.app" (finestra
	-- Chrome dedicata al Generatore, aperta con --app), Mario ha osservato
	-- direttamente che i tasti destinati a WhatsApp a volte finiscono
	-- invece su quella finestra (un Cmd+A visibile lì sopra). Per togliere
	-- del tutto la possibilità che un'altra finestra Chrome rubi il focus
	-- durante l'automazione, minimizziamo qui ogni finestra Chrome che NON
	-- sia quella di WhatsApp, prima di mandare qualsiasi tasto. Vengono poi
	-- ripristinate (restoreChromeWindows) a fine invio.
	set savedIDs to {}
	try
		tell application "Google Chrome"
			repeat with w in windows
				try
					set u to URL of active tab of w
					if u does not contain "web.whatsapp.com" then
						if not (minimized of w) then
							set minimized of w to true
							set end of savedIDs to id of w
						end if
					end if
				end try
			end repeat
		end tell
	end try
	return savedIDs
end minimizeOtherChromeWindows

on restoreChromeWindows(savedIDs)
	try
		tell application "Google Chrome"
			repeat with wid in savedIDs
				try
					set minimized of (first window whose id is wid) to false
				end try
			end repeat
		end tell
	end try
end restoreChromeWindows

on run
	set minimizedWindowIDs to {}
	try
		do shell script "/usr/bin/touch " & quoted form of runLogPath
		my appendLog("=== Avvio Engine WhatsApp v134 ===")

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

		set minimizedWindowIDs to my minimizeOtherChromeWindows()
		if (count of minimizedWindowIDs) > 0 then
			my appendLog("Minimizzate " & (count of minimizedWindowIDs) & " altra/e finestra/e Chrome (es. il launcher del Generatore) per evitare interferenze col focus.")
		end if

		set resultText to my performSend(pdfPath, messageText, recipientName, recipientPhone)
		my appendLog("Risultato: " & resultText)

		my restoreChromeWindows(minimizedWindowIDs)
		set minimizedWindowIDs to {}

		if resultText is "SUCCESS" then
			if my isTestSend() then
				my appendLog("SUCCESS (TEST — “Forza invio a” attivo): NON registro in WhatsApp_Inviati.log, il flag \"Inviata\" non verrà aggiornato.")
			else
				my recordSuccess(pdfName)
				my appendLog("SUCCESS: PDF e messaggio inviati.")
			end if
		end if
	on error errMsg number errNum
		my restoreChromeWindows(minimizedWindowIDs)
		my appendLog("ERRORE " & errNum & ": " & errMsg)
		display alert "Automazione WhatsApp interrotta" message errMsg
	end try
end run

