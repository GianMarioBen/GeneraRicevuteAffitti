-- Invia Ricevuta WhatsApp — guscio Helper (sorgente ricostruito in v139)
--
-- È l'app autorizzata in Preferenze di Sistema > Sicurezza e Privacy >
-- Privacy > Accessibilità: i tasti che il motore manda a WhatsApp Web
-- partono da qui, quindi questo guscio NON va mai modificato o
-- ricompilato se esiste già (si perderebbe l'autorizzazione).
--
-- L'installer lo compila SOLO se ~/Applications/Invia Ricevuta WhatsApp.app
-- manca del tutto e non si trova neppure nel Cestino; in quel caso il
-- permesso Accessibilità va ridato una volta a mano.
--
-- Non contiene logica: carica ed esegue il motore WhatsApp_Engine.scpt,
-- l'unico file che si aggiorna a ogni versione. Il server locale lo avvia
-- con "open" dopo aver scritto Ricevuta_Da_Inviare.txt,
-- Messaggio_Da_Inviare.txt e WhatsApp_Destinatario.json.

on run
	set enginePath to (POSIX path of (path to home folder)) & "Library/Application Support/CruscottoAffitti/WhatsApp_Engine.scpt"
	try
		set engineScript to load script (POSIX file enginePath)
	on error errMsg
		display alert "Motore WhatsApp non trovato" message "Non riesco a caricare:" & return & enginePath & return & return & "Rilancia l'installer del Cruscotto Affitti." & return & return & "Dettaglio tecnico: " & errMsg
		return
	end try
	run engineScript
end run
