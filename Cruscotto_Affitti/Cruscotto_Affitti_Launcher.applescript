-- Cruscotto Affitti — Launcher (applet "stay-open", con icona propria nel Dock)
--
-- Apre SOLO il Generatore Ricevute come finestra-app di Google Chrome
-- (niente tab, niente barra indirizzi) tramite il flag --app=, come il
-- tentativo originale di "Camilla Ciatti". Da v2 il launcher RESTA APERTO
-- finché il Generatore è aperto, così nel Dock c'è la sua icona (la
-- casetta) invece di avere il Generatore solo "dentro" l'icona di Chrome:
--   - clic sull'icona nel Dock  -> riporta in primo piano il Generatore
--     (anche se era minimizzato), oppure lo riapre se era stato chiuso;
--   - non apre mai una seconda finestra se il Generatore è già aperto;
--   - quando la finestra del Generatore viene chiusa, il launcher si
--     chiude da solo dopo pochi secondi.
-- Va compilato come applet stay-open: osacompile -s -o "Cruscotto Affitti.app" ...
--
-- WhatsApp Web NON viene toccato: resta una scheda di una normale finestra
-- Chrome. Durante l'invio il motore WhatsApp minimizza temporaneamente la
-- finestra del Generatore (e la ripristina alla fine) per evitare che
-- rubi il focus dei tasti.
--
-- Il launcher legge solo titoli/URL delle finestre di Chrome ogni pochi
-- secondi; non manda tasti e non porta Chrome in primo piano da solo.

property serverHealthURL : "http://127.0.0.1:8765/api/health"
property generatoreURL : "http://127.0.0.1:8765/Generatore_Ricevute_Condominio.html"
property generatoreKey : "Generatore_Ricevute_Condominio.html"
property serverRunner : "/Users/bless/Library/Application Support/CruscottoAffitti/Avvia_Cruscotto_Affitti_Server.sh"
property chromeBinary : "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
property wrapperLog : "/tmp/Cruscotto_Affitti_Wrapper.log"
property idleTicks : 0

on isServerUp()
	try
		do shell script "/usr/bin/curl -s -m 2 -o /dev/null " & quoted form of serverHealthURL
		return true
	on error
		return false
	end try
end isServerUp

on fileExists(posixPath)
	try
		do shell script "/bin/test -e " & quoted form of posixPath
		return true
	on error
		return false
	end try
end fileExists

on ensureServer()
	if my isServerUp() then return true
	try
		do shell script "nohup /bin/bash " & quoted form of serverRunner & " >/tmp/Cruscotto_Affitti_Launcher_Server.log 2>&1 &"
	on error errMsg
		display alert "Non riesco ad avviare il server locale" message errMsg
		return false
	end try
	repeat with attempt from 1 to 20
		delay 0.5
		if my isServerUp() then return true
	end repeat
	display alert "Non riesco ad avviare il server locale" message "Il server su 127.0.0.1:8765 non ha risposto entro 10 secondi. Prova a riavviare il Mac, oppure controlla /tmp/Cruscotto_Affitti_Autostart.log."
	return false
end ensureServer

on chromeRunning()
	try
		return (application "Google Chrome" is running)
	on error
		return false
	end try
end chromeRunning

on generatoreWindowID()
	-- id della finestra Chrome che mostra il Generatore; missing value se
	-- non c'è; "ERR" se Chrome non ha risposto (in quel caso NON chiudiamo).
	if not my chromeRunning() then return missing value
	try
		tell application "Google Chrome"
			repeat with w in windows
				try
					repeat with t in tabs of w
						if (URL of t) contains generatoreKey then return id of w
					end repeat
				end try
			end repeat
		end tell
	on error
		return "ERR"
	end try
	return missing value
end generatoreWindowID

on bringGeneratoreToFront()
	set wid to my generatoreWindowID()
	if wid is missing value or wid is "ERR" then return false
	try
		tell application "Google Chrome"
			set w to (first window whose id is wid)
			set minimized of w to false
			set index of w to 1
			activate
		end tell
		return true
	on error
		return false
	end try
end bringGeneratoreToFront

on openGeneratore()
	if my bringGeneratoreToFront() then return
	if not my ensureServer() then return
	if not (my fileExists(chromeBinary)) then
		display alert "Google Chrome non trovato" message "Non trovo Google Chrome in " & chromeBinary & ". Il Generatore deve girare dentro Chrome."
		return
	end if
	-- Apre il Generatore come vera finestra-app Chrome.
	try
		do shell script "nohup " & quoted form of chromeBinary & " --app=" & quoted form of generatoreURL & " --window-size=1500,900 --no-first-run --disable-session-crashed-bubble >" & quoted form of wrapperLog & " 2>&1 &"
	on error errMsg
		display alert "Impossibile aprire Google Chrome" message errMsg
	end try
end openGeneratore

on run
	set idleTicks to 0
	my openGeneratore()
end run

on reopen
	-- clic sull'icona nel Dock mentre il launcher è già aperto
	set idleTicks to 0
	my openGeneratore()
end reopen

on idle
	set idleTicks to idleTicks + 1
	-- i primi ~15 secondi lasciamo a Chrome il tempo di aprire la finestra
	if idleTicks > 5 then
		set wid to my generatoreWindowID()
		if wid is missing value then
			tell me to quit
			return 1
		end if
	end if
	return 3
end idle

on quit
	continue quit
end quit
