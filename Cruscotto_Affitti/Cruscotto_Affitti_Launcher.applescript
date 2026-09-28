-- Cruscotto Affitti — Launcher
--
-- Apre SOLO il Generatore Ricevute come vera finestra-app di Google Chrome
-- (niente tab, niente barra indirizzi, niente segnalibri), tramite il flag
-- --app=. Ricostruito da Claude/Camilla a partire dall'app funzionante che
-- "Camilla Ciatti" (ChatGPT) aveva già creato in precedenza (stesso URL,
-- stesse opzioni di Chrome), qui come sorgente leggibile e versionabile
-- invece che come solo eseguibile compilato.
--
-- IMPORTANTE — cosa NON fa questo launcher:
-- WhatsApp Web NON viene mai toccato da questo launcher e resta sempre
-- una scheda di una normale finestra di Google Chrome, esattamente come
-- prima. WhatsApp_Engine.scpt individua la scheda giusta cercando l'URL
-- "web.whatsapp.com" fra TUTTE le finestre di Google Chrome aperte, quindi
-- la finestra-app del Generatore (che ha un URL diverso) viene ignorata
-- automaticamente da quella ricerca e non dovrebbe interferire con
-- l'automazione dell'invio. Il vecchio testimone del progetto segnalava
-- problemi di focus quando era WhatsApp stesso ad essere aperto in
-- modalità --app: qui invece è SOLO il Generatore ad usare --app, WhatsApp
-- resta tab normale. Va comunque testato con calma il flusso di invio
-- WhatsApp mentre questa finestra-app è aperta, prima di fidarsi al 100%.
--
-- Se il server locale (127.0.0.1:8765) non risulta già attivo, questo
-- launcher lo avvia da solo usando lo stesso runner del LaunchAgent,
-- prima di aprire la finestra.

property serverHealthURL : "http://127.0.0.1:8765/api/health"
property generatoreURL : "http://127.0.0.1:8765/Generatore_Ricevute_Condominio.html"
property serverRunner : "/Users/bless/Library/Application Support/CruscottoAffitti/Avvia_Cruscotto_Affitti_Server.sh"
property chromeBinary : "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
property wrapperLog : "/tmp/Cruscotto_Affitti_Wrapper.log"

on isServerUp()
	try
		do shell script "/usr/bin/curl -s -m 2 -o /dev/null " & quoted form of serverHealthURL
		return true
	on error
		return false
	end try
end isServerUp

on run
	if not my isServerUp() then
		try
			do shell script "nohup /bin/bash " & quoted form of serverRunner & " >/tmp/Cruscotto_Affitti_Launcher_Server.log 2>&1 &"
		on error errMsg
			display alert "Non riesco ad avviare il server locale" message errMsg
			return
		end try

		set started to false
		repeat with attempt from 1 to 20
			delay 0.5
			if my isServerUp() then
				set started to true
				exit repeat
			end if
		end repeat

		if not started then
			display alert "Non riesco ad avviare il server locale" message "Il server su 127.0.0.1:8765 non ha risposto entro 10 secondi. Prova a riavviare il Mac, oppure controlla /tmp/Cruscotto_Affitti_Autostart.log."
			return
		end if
	end if

	if not (my fileExists(chromeBinary)) then
		display alert "Google Chrome non trovato" message "Non trovo Google Chrome in " & chromeBinary & ". Il Generatore deve girare dentro Chrome."
		return
	end if

	-- Apre il Generatore come vera finestra-app Chrome.
	-- Niente tab, niente barra indirizzi, niente segnalibri.
	try
		do shell script "nohup " & quoted form of chromeBinary & " --app=" & quoted form of generatoreURL & " --window-size=1500,900 --no-first-run --disable-session-crashed-bubble >" & quoted form of wrapperLog & " 2>&1 &"
	on error errMsg
		display alert "Impossibile aprire Google Chrome" message errMsg
	end try
end run

on fileExists(posixPath)
	try
		do shell script "/bin/test -e " & quoted form of posixPath
		return true
	on error
		return false
	end try
end fileExists
