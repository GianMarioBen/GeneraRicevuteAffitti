PACCHETTO PER CLAUDE — CRUSCOTTO AFFITTI

1. Generatore_Ricevute_Condominio_v120.html
   Stato FULL con Autostart/UI/telefoni/24 Box/Forza invio a.

2. WhatsApp_Engine_v115.applescript
   Sorgente AppleScript della versione in cui il risultato Ahmed arrivava al bordo verde.

3. WhatsApp_Engine_v105.applescript
   Sorgente AppleScript della versione in cui l'intero flusso PDF + messaggio ha funzionato da una normale scheda Chrome.

4. Avvia_Cruscotto_Affitti_Server.sh
   Runner del server usato dal LaunchAgent.

5. com.letmar.cruscottoaffitti.server.plist
   LaunchAgent macOS per avvio automatico del server.

NOTA .scpt:
Le vecchie versioni compilate v105/v115 non sono conservate come file distinti: gli installer compilavano la sorgente .applescript e la installavano sempre come
~/Library/Application Support/CruscottoAffitti/WhatsApp_Engine.scpt
che veniva poi sovrascritta dagli aggiornamenti successivi.
Per analisi/modifica è preferibile usare le sorgenti .applescript qui incluse.
Su macOS si possono compilare in .scpt con:
  osacompile -o WhatsApp_Engine_v115.scpt WhatsApp_Engine_v115.applescript
  osacompile -o WhatsApp_Engine_v105.scpt WhatsApp_Engine_v105.applescript
  osacompile -o WhatsApp_Engine_v121.scpt WhatsApp_Engine_v121.applescript

6. WhatsApp_Engine_v121.applescript (NUOVO — proposta di fix)
   Parte identica a v115 (ricerca WhatsApp per numero esatto, poi tutto il
   flusso PDF + messaggio ereditato da v105/v115, invariato).
   Modificata SOLO la gestione del fallback dentro
   searchRecipientByPhoneInWhatsApp, cioè esattamente la transizione:
     risultato trovato in Search all chats
     → risultato realmente focalizzato
     → apertura chat
   che il testimone identifica come unico punto rotto.

   Cosa cambia rispetto a v115:
   - v115, quando il click diretto sul risultato non veniva confermato,
     rifocalizzava il campo di ricerca e premeva Freccia giù + RETURN
     (key code 36). Questo NON è mai stato verificato manualmente da Mario
     come tasto che apre la chat.
   - v121 rifocalizza il campo di ricerca, preme Freccia giù, poi VERIFICA
     via document.activeElement che il focus tastiera sia realmente uscito
     dal campo di ricerca ed entrato nella riga risultato (questo è il
     "bordo verde" osservato), e SOLO A QUEL PUNTO preme BARRA SPAZIATRICE
     (key code 49) — esattamente il tasto che Mario ha premuto a mano con
     successo davanti alla riga con bordo verde. Si ritenta un secondo giro
     (Freccia giù + SPACE) se il primo non apre la chat, per lasciare tempo
     a WhatsApp di registrare il focus (evitando l'errore di v116, che
     premeva SPACE troppo presto). Se anche questo fallisce, resta come
     ultima rete di sicurezza il vecchio fallback Return di v115, così non
     si perde nulla della robustezza precedente.
   - Ogni fase è loggata in modo distinto in
     /tmp/Invia_Ricevuta_WhatsApp_Helper_v97.log, per poter capire subito,
     dal prossimo test reale, se è stato SPACE, il secondo tentativo, o il
     fallback Return ad aprire la chat (o se nessuno dei tre ha funzionato).

   NON toccato: ricerca numero, file picker, invio PDF, verifica anteprima,
   composer, invio messaggio, server, LaunchAgent, UI del Generatore.

7. Invia_Ricevuta_WhatsApp_v96.command / Cruscotto_Affitti_Server.py
   File più recenti ricevuti da Mario per contesto. Il .command v96 usa un
   meccanismo di ricerca per NOME (non per numero) diverso da v105/v115 e
   sembra una diramazione più vecchia/parallela rispetto all'architettura
   WhatsApp_Engine.scpt descritta nel testimone: conservato come riferimento
   storico, non modificato, e non è quello da installare per il fix.
   Cruscotto_Affitti_Server.py corrisponde al server "version 7" (health
   endpoint), utile per verificare endpoint /api/fs/* e /api/whatsapp/prepare
   effettivamente in uso su questo Mac.

8. Installa_Cruscotto_Affitti_v121.command (INSTALLER)
   Doppio-click sul Mac della Mammetta per installare tutto quanto sopra
   in un colpo solo. Fa SEMPRE un backup datato (in
   ~/Library/Application Support/CruscottoAffitti/Backup_Installer/<data>)
   di ogni file che sta per sostituire, PRIMA di sovrascriverlo:
     - WhatsApp_Engine.scpt precedente
     - Avvia_Cruscotto_Affitti_Server.sh precedente
     - Cruscotto_Affitti_Server.py precedente
     - Generatore_Ricevute_Condominio.html precedente
     - il plist del LaunchAgent precedente
   Poi installa: WhatsApp_Engine.scpt compilato da v121, Generatore v120,
   server Python, runner e LaunchAgent; infine ricarica il LaunchAgent e
   verifica /api/health.
   NON tocca MAI: ElencoRicevute/ (Affittuari.json, Ricevute_Dati.json,
   PDF, WhatsApp_Destinatario.json, WhatsApp_Inviati.log, log) né
   ~/Applications/Invia Ricevuta WhatsApp.app (il guscio Helper
   autorizzato in Accessibilità, che deve restare immutato). Si può
   rilanciare più volte senza rischi: ogni run fa un nuovo backup.
   Se qualcosa manca (cartella ElencoRicevute non trovata, file del
   pacchetto mancanti) l'installer si ferma con un avviso invece di
   installare qualcosa di incompleto.

PROSSIMO PASSO SUL MAC DELLA MADRE DI MARIO:
1. Scompattare TUTTO lo zip in un'unica cartella (tutti i file devono
   stare insieme all'installer).
2. Doppio-click su Installa_Cruscotto_Affitti_v121.command
   (se macOS chiede conferma per "sviluppatore non identificato":
   tasto destro -> Apri -> Apri).
3. Alla fine comparirà un avviso con l'esito e il percorso del backup.
4. Fare un invio di test (con "Forza invio a" attivo nel SetUp) e poi
   leggere:
   tail -100 /tmp/Invia_Ricevuta_WhatsApp_Helper_v97.log
   per vedere quale dei tre passi (SPACE primo giro, SPACE secondo giro,
   fallback Return) ha aperto la chat.
   Log dell'installer stesso, se serve rivedere cosa ha fatto:
   /tmp/Cruscotto_Affitti_Installer.log
