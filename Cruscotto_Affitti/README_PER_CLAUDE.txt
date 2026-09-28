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
  osacompile -o WhatsApp_Engine_v122.scpt WhatsApp_Engine_v122.applescript

6. WhatsApp_Engine_v121.applescript (primo tentativo di fix — SUPERATO da v122,
   conservato come riferimento storico)
   Parte identica a v115. Modificata SOLO la gestione del fallback dentro
   searchRecipientByPhoneInWhatsApp: dopo il click diretto non confermato,
   premeva Freccia giù, verificava via document.activeElement che il focus
   fosse uscito dal campo di ricerca, poi premeva SPACE.
   ESITO DEL TEST REALE su Mamma Mac (v121, con diagnostica aggiunta):
   il cursore/focus tastiera RESTAVA nel campo di ricerca anche dopo
   Freccia giù — quindi SPACE non apriva mai la chat. Confermato da Mario
   con osservazione diretta: "il cursore è ancora nel campo ricerca".

6b. WhatsApp_Engine_v122.applescript (FIX ATTUALE, basato su prova reale)
   Stessa base di v121/v115/v105 (nessun'altra parte toccata). Unica
   modifica: nel fallback di searchRecipientByPhoneInWhatsApp, al posto di
   Freccia giù si usano DUE TAB (key code 48 x2) per spostare davvero il
   focus tastiera fuori dal campo di ricerca, poi SPACE (key code 49) —
   esattamente la sequenza che Mario ha verificato manualmente funzionare
   sul Mac della mamma ("per risolvere bisogna dare due TAB e poi uno
   spazio"). Mantiene la stessa diagnostica di v121 (log di
   activeElement e del contenuto del campo di ricerca prima/dopo SPACE)
   e lo stesso fallback finale su Return come rete di sicurezza.

   NON toccato: ricerca numero, file picker, invio PDF, verifica anteprima,
   composer, invio messaggio, server, LaunchAgent, UI del Generatore.

6d. WhatsApp_Engine_v123.applescript (SOLO DIAGNOSTICA, nessun fix ancora)
   Test reale v122 su Mamma Mac: il motore non arriva NEMMENO al click
   sulla riga risultato / ai due TAB+SPACE. Fallisce prima, nella verifica
   che il numero sia stato incollato nel campo "Search all chats": anche
   con "Forza invio a" che ora funziona (numero 3338397583 corretto),
   il log mostra "Numero non rilevato... provo inserimento JS diretto...
   FAIL: non riesco a scrivere il numero", nonostante lo screenshot
   mostri il numero scritto correttamente e visibile nella barra di
   ricerca. Questo stesso fallimento è identico nei log di v120 e v121:
   quindi il fix TAB+TAB+SPACE non è MAI stato davvero messo alla prova
   finora, perché l'esecuzione si ferma prima.
   v123 aggiunge SOLO una diagnostica (nessun cambio di comportamento):
   se anche l'inserimento JS diretto fallisce, prima di arrendersi
   fotografa TUTTI i campi di testo visibili in tutta la pagina (non solo
   dentro #side, che potrebbe non esistere più con l'attuale WhatsApp
   Web) con tag/ruolo/contenuto di ciascuno, e logga tutto. Serve a capire
   se il selettore CSS usato per trovare il campo di ricerca (root
   #side + input/[contenteditable]/[role=textbox]) è quello sbagliato
   per la versione di WhatsApp Web attualmente in uso sul Mac della
   Mammetta.
   RISPOSTA ottenuta dal test reale: sì. Il log ha mostrato
   "sideExists=true totale=2 :: input(role=textbox,...,vis=true)=[3338397583]"
   — il campo di ricerca esiste, è visibile e contiene già il numero
   corretto, ma il codice lo cercava solo dentro #side, e su questa
   versione di WhatsApp Web il campo di ricerca vive FUORI da #side
   (probabilmente in un header sopra la lista chat, che invece resta
   dentro #side).

6e. WhatsApp_Engine_v124.applescript (FIX basato sulla diagnostica v123)
   Stessa base di v105/v115/v121/v122/v123 (nessun'altra parte toccata).
   Unica modifica: nella verifica del campo di ricerca dentro
   searchRecipientByPhoneInWhatsApp (sia il primo controllo via
   document.querySelectorAll, sia il fallback di inserimento diretto via
   JavaScript), il root di ricerca passa da
   "document.querySelector('#side')||document" a semplicemente
   "document" — cerca cioè su tutta la pagina, non solo dentro #side.
   Il resto (click sul primo risultato, doppio TAB+SPACE, fallback
   Return, diagnostica di log) resta identico a v122/v123.
   ESITO DEL TEST REALE: v124 NON ha risolto. Il log è risultato
   IDENTICO a quello di v123 (stesso fallimento, stesso identico
   messaggio "sideExists=true totale=2..."), quindi l'ipotesi "#side"
   era sbagliata: il problema non era la restrizione a #side.

6f. WhatsApp_Engine_v125.applescript (SOLO DIAGNOSTICA, nessun fix ancora)
   Dato che rimuovere la restrizione a #side non ha cambiato nulla,
   serve capire perché una lettura di sola verifica (senza scrivere
   nulla) del campo di ricerca fallisce per 30 tentativi (3 secondi) pur
   con il numero visibilmente già presente, mentre una diagnostica
   eseguita DOPO (a distanza di qualche secondo in più) lo trova
   correttamente. v125 aggiunge una fotografia dettagliata (candidati
   trovati, tag, valore grezzo, valore solo-cifre, wanted, match sì/no)
   ai tentativi 1, 10, 20 e 30 del loop di verifica, per vedere
   l'evoluzione nel tempo: il campo è vuoto all'inizio e si popola
   tardi? "wanted" è la stringa giusta? Ci sono più candidati e stiamo
   guardando quello sbagliato? Nessun cambio di comportamento.
   RISPOSTA ottenuta dal test reale, DEFINITIVA: il campo con il numero
   corretto c'è fin dal tentativo 1, il confronto sarebbe positivo
   ("match=true"), ma il codice lo scartava PRIMA di arrivare al
   confronto perché il suo getBoundingClientRect risultava troppo
   piccolo/nascosto secondo il filtro "vis" (soglia width>80,
   height>20). Log: "tag=input,vis=false,raw=[3338397583],
   digits=[3338397583],match=true". Probabile spiegazione: WhatsApp usa
   un <input> reale minuscolo/invisibile per catturare la digitazione,
   mentre l'elemento visivamente grande che vede l'utente è un layer
   decorativo separato.

6g. WhatsApp_Engine_v126.applescript (FIX DEFINITIVO, basato sulla
   diagnostica v125)
   Stessa base di v105/v115/v121-v125 (nessun'altra parte toccata).
   Unica modifica: nella verifica del campo di ricerca dentro
   searchRecipientByPhoneInWhatsApp (sia il controllo di sola lettura
   sia il fallback di inserimento diretto via JavaScript), rimosso il
   filtro "vis" (visibilità/dimensione) che scartava il campo giusto: il
   confronto ora si basa SOLO sul contenuto (le cifre corrispondono?),
   che è già di per sé una prova sufficiente di aver trovato il campo
   giusto. Il resto (click sul primo risultato — che invece usa ancora
   correttamente un filtro di visibilità, perché lì serve davvero per
   non cliccare righe nascoste —, doppio TAB+SPACE, fallback Return,
   diagnostica di log) resta identico a v122-v125.
   ESITO DEL TEST REALE: FUNZIONA. Il numero viene trovato, il primo
   risultato viene cliccato, e la diagnostica conferma che il focus
   arriva davvero sulla riga giusta (activeElement mostra il testo della
   chat "Gian Mario Benetti..."). Emerso però un bug distinto subito
   dopo SPACE: errore AppleScript -2753 "La variabile recipientName non
   è definita".

6h. WhatsApp_Engine_v127.applescript (fix errore -2753 dopo SPACE)
   Causa: nel fallback TAB+TAB+SPACE di searchRecipientByPhoneInWhatsApp
   (funzione che riceve SOLO recipientPhone, non recipientName), un
   controllo residuo chiamava "currentChatMatches(recipientName)" — una
   variabile che in quella funzione non esiste. Rimosso quel controllo:
   era comunque ridondante, la riga successiva verifica già
   correttamente (via header+composer visibili in #main) se la chat si
   è aperta, in modo generico e senza bisogno del nome.
   NON toccato nient'altro.

6i. WhatsApp_Engine_v128.applescript (nuovo tentativo più semplice: INVIO
   diretto)
   WhatsApp Web è di nuovo cambiato: Mario riporta che con due TAB ora ci
   si ferma sul pulsante "Tutte" (il filtro sopra la lista chat), quindi
   il percorso TAB+TAB+SPACE di v122-v127 non è più affidabile su questa
   versione. Mario ha però verificato manualmente un metodo più semplice:
   con il numero scritto nel campo di ricerca, basta premere INVIO per
   selezionare direttamente la chat.
   v128 prova questo per primo, subito dopo aver confermato che il
   numero è presente nel campo (key code 36 = Return), e verifica se la
   chat si apre (header+composer in #main). Se funziona, la funzione
   ritorna subito senza toccare click simulati o TAB. Se NON funziona,
   ricade nella logica precedente invariata (click sulla riga, doppio
   TAB+SPACE, fallback Return finale) come rete di sicurezza — nessuna
   parte precedente è stata rimossa, solo anteposto questo tentativo più
   diretto.
   ESITO DEL TEST REALE: FUNZIONA, flusso completo end-to-end. Log:
     "Numero presente nel Search all chats: 3338397583"
     "Chat aperta con INVIO diretto dopo il numero (nessun click/TAB necessario)."
     "Pulsante Allega aperto." → "Voce Documento selezionata." →
     "Anteprima PDF verificata" → "PDF REALMENTE inviato e verificato
     nella chat" → "Messaggio incollato correttamente nel composer." →
     "Risultato: SUCCESS" → "SUCCESS: PDF e messaggio inviati."
   v128 è quindi la versione da considerare STABILE e definitiva per
   l'invio automatico WhatsApp su questo Mac, alla data del 28/09/2026.
   Se WhatsApp Web dovesse cambiare ancora in futuro, ripartire da qui
   con lo stesso metodo: mai un'altra versione alla cieca, sempre prima
   la diagnostica sul log reale, poi il fix mirato.

6j. WhatsApp_Engine_v129.applescript + Generatore HTML + Server —
   non aggiornare "Inviata" sugli invii di test
   Richiesta di Mario: quando "Forza invio a" è attivo (il numero è
   quello di test, non quello vero dell'affittuario), l'invio non deve
   far scattare il flag "✓ Inviata" sulla ricevuta, perché è
   evidentemente solo una prova.
   Il flag viene letto dall'HTML da WhatsApp_Inviati.log, che però è
   scritto dal motore AppleScript stesso (recordSuccess) ad ogni SUCCESS
   — quindi bastava nascondere il flag lato HTML solo temporaneamente:
   al ricaricamento della pagina, rileggendo il log, sarebbe ricomparso
   comunque. Fix end-to-end, alla radice:
   1. Generatore HTML (prepareWhatsAppSend): il body della POST verso
      /api/whatsapp/prepare include ora "isTest": true quando
      recipient.forced è true (cioè "Forza invio a" attivo); inoltre
      non avvia più watchWhatsAppSendStatus per gli invii di test (non
      c'è nulla da attendere).
   2. Cruscotto_Affitti_Server.py (/api/whatsapp/prepare): legge
      "isTest" dal body e lo scrive dentro
      ElencoRicevute/WhatsApp_Destinatario.json insieme a name/phone.
   3. WhatsApp_Engine_v129.applescript: nuova funzione isTestSend() che
      legge "isTest":true da WhatsApp_Destinatario.json (grep); nel
      gestore "run", se SUCCESS e isTestSend() è true, NON chiama più
      recordSuccess (quindi WhatsApp_Inviati.log non viene toccato) e
      logga chiaramente che si è trattato di un invio di test.
   Verificato con una chiamata di test diretta al server (isTest:true
   → scritto correttamente nel JSON; isTest assente → scritto false).
   NON toccato nient'altro (ricerca, click, PDF, composer, messaggio).

6c. Cruscotto_Affitti_Server.py — fix bug "Forza invio a" ignorato
   BUG CONFERMATO dal test di Mario: con "Forza invio a" attivo nel SetUp,
   l'invio partiva comunque verso il vecchio destinatario (Ahmed) invece
   che verso il numero di test.
   CAUSA: l'endpoint POST /api/whatsapp/prepare riceveva recipientName e
   recipientPhone dall'HTML ma non li scriveva MAI in
   ElencoRicevute/WhatsApp_Destinatario.json — il file che
   WhatsApp_Engine.scpt legge per sapere chi contattare. Quel file restava
   quindi quello dell'ultimo invio reale, e "Forza invio a" non aveva
   alcun effetto sull'automazione (anche se il messaggio/PDF venivano
   preparati correttamente).
   FIX: /api/whatsapp/prepare ora scrive sempre
   ElencoRicevute/WhatsApp_Destinatario.json con {"name":...,"phone":...}
   usando esattamente il destinatario scelto dall'HTML (forzato o reale).
   Verificato con una chiamata di test diretta al server.

7. Invia_Ricevuta_WhatsApp_v96.command / Cruscotto_Affitti_Server.py
   File più recenti ricevuti da Mario per contesto. Il .command v96 usa un
   meccanismo di ricerca per NOME (non per numero) diverso da v105/v115 e
   sembra una diramazione più vecchia/parallela rispetto all'architettura
   WhatsApp_Engine.scpt descritta nel testimone: conservato come riferimento
   storico, non modificato, e non è quello da installare per il fix.
   Cruscotto_Affitti_Server.py corrisponde al server "version 7" (health
   endpoint), utile per verificare endpoint /api/fs/* e /api/whatsapp/prepare
   effettivamente in uso su questo Mac.

8. Installa_Cruscotto_Affitti_v129.command (INSTALLER — TUTTO-IN-UNO)
   Un solo file, autosufficiente: tutti i contenuti sopra (HTML, .scpt,
   server, runner, plist) sono incorporati dentro il .command stesso —
   non serve scaricare nient'altro. Doppio-click sul Mac della Mammetta
   per installare tutto in un colpo solo. Fa SEMPRE un backup datato (in
   ~/Library/Application Support/CruscottoAffitti/Backup_Installer/<data>)
   di ogni file che sta per sostituire, PRIMA di sovrascriverlo:
     - WhatsApp_Engine.scpt precedente
     - Avvia_Cruscotto_Affitti_Server.sh precedente
     - Cruscotto_Affitti_Server.py precedente
     - Generatore_Ricevute_Condominio.html precedente
     - il plist del LaunchAgent precedente
   Poi installa: WhatsApp_Engine.scpt compilato da v129 (niente flag Inviata sui test),
   Generatore v120
   (con badge versione motore), server Python (con fix Forza invio a),
   runner e LaunchAgent; infine ricarica il LaunchAgent e verifica
   /api/health. Generato dallo script build_installer.py (nella cartella
   scratchpad della sessione, non nel repo) a partire dai file sorgente:
   per rigenerarlo dopo un'altra modifica, rilanciare quello script.
   NON tocca MAI: ElencoRicevute/ (Affittuari.json, Ricevute_Dati.json,
   PDF, WhatsApp_Destinatario.json, WhatsApp_Inviati.log, log) né
   ~/Applications/Invia Ricevuta WhatsApp.app (il guscio Helper
   autorizzato in Accessibilità, che deve restare immutato). Si può
   rilanciare più volte senza rischi: ogni run fa un nuovo backup.
   Se qualcosa manca (cartella ElencoRicevute non trovata) l'installer si
   ferma con un avviso invece di installare qualcosa di incompleto.

6k. Cruscotto_Affitti_Launcher.applescript + CruscottoAffitti.icns —
   launcher "Cruscotto Affitti.app" (finestra-app Chrome dedicata)
   Richiesta di Mario: la Mammetta fatica a gestire più schede Chrome
   aperte insieme (Generatore + WhatsApp), quindi serve un modo per
   aprire il Generatore fuori dalle schede normali. Mario aveva già un
   precedente tentativo funzionante fatto da "Camilla Ciatti" (ChatGPT):
   un piccolo applet AppleScript compilato (Cruscotto Affitti.app) che
   apre SOLO il Generatore come finestra-app Chrome dedicata (flag
   --app=, niente tab/barra indirizzi/segnalibri), lasciando WhatsApp
   Web come scheda di una normale finestra Chrome, esattamente come
   oggi. Analizzato il .app ricevuto (decompilato solo a livello di
   stringhe, .scpt binario non leggibile riga per riga): usa
   `nohup '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
   --app='http://127.0.0.1:8765/Generatore_Ricevute_Condominio.html'
   --window-size=1500,900 --no-first-run --disable-session-crashed-bubble`.
   Ricostruito da zero come sorgente AppleScript leggibile e
   versionabile (non solo eseguibile compilato):
   Cruscotto_Affitti_Launcher.applescript. Stessa tecnica, stesso URL,
   stesse opzioni Chrome, con l'aggiunta di un controllo che avvia da
   solo il server locale (stesso runner del LaunchAgent) se non risulta
   già attivo prima di aprire la finestra.
   PERCHÉ NON DOVREBBE ROMPERE L'AUTOMAZIONE WHATSAPP: il vecchio
   testimone del progetto segnalava problemi di focus quando era
   WHATSAPP STESSO ad essere aperto in modalità --app. Qui invece è
   SOLO il Generatore ad usare --app; WhatsApp resta sempre una scheda
   di una normale finestra Chrome. WhatsApp_Engine.scpt individua la
   scheda giusta cercando l'URL "web.whatsapp.com" fra TUTTE le finestre
   di Google Chrome (non per indice/posizione), e rifocalizza
   esplicitamente quella finestra prima di ogni invio di tasti — quindi
   un'altra finestra Chrome aperta in parallelo (quella del Generatore)
   non dovrebbe interferire. VA COMUNQUE VERIFICATO CON UN TEST REALE
   del flusso di invio WhatsApp con la finestra-app del Generatore
   aperta, prima di fidarsi al 100%.
   Icona: CruscottoAffitti.icns, la stessa che Mario ha estratto dal
   tentativo precedente di Camilla Ciatti (il disegno della casetta).
   L'installer (vedi sotto) la installa e la imposta come icona del
   launcher via PlistBuddy.
   NON tocca l'automazione WhatsApp, il motore, il server, né l'app
   Helper WhatsApp.

8b. Installer, aggiornamento: ora compila e installa anche il launcher
   Nella sezione 7 dell'installer (dopo aver ricaricato il LaunchAgent):
   backup dell'eventuale "~/Applications/Cruscotto Affitti.app"
   preesistente (cp -R, poi rimosso e ricreato da zero), compilazione di
   Cruscotto_Affitti_Launcher.applescript con osacompile direttamente in
   "~/Applications/Cruscotto Affitti.app", copia dell'icona
   CruscottoAffitti.icns dentro Contents/Resources/, e impostazione di
   CFBundleIconFile/CFBundleDisplayName/CFBundleName via PlistBuddy (con
   fallback "Add" se le chiavi non esistessero già, e un avviso nel log
   se PlistBuddy non fosse disponibile, senza bloccare l'installazione).
   L'icona incorporata nell'installer è codificata in base64 (unico modo
   sicuro per portare un file binario dentro uno script di testo) e
   decodificata con "base64 -D" (sintassi macOS/BSD, con fallback
   "base64 -d" in caso di ambiente non-macOS). Verificato che l'icona
   decodificata dall'installer sia byte-per-byte identica all'originale.

PROSSIMO PASSO SUL MAC DELLA MADRE DI MARIO:
1. Scaricare SOLO Installa_Cruscotto_Affitti_v129.command (nessun altro
   file, nessuno zip: è autosufficiente).
2. Se il Mac toglie il permesso di esecuzione o Gatekeeper blocca il
   file "sviluppatore non identificato": da Terminale,
   chmod +x e xattr -d com.apple.quarantine sul file, poi lanciarlo
   (oppure tasto destro -> Apri -> Apri).
3. Alla fine comparirà un avviso con l'esito e il percorso del backup.
4. Fare un invio di test (con "Forza invio a" attivo nel SetUp — ora
   funziona davvero, vedi punto 6c) e poi leggere:
   tail -150 /tmp/Invia_Ricevuta_WhatsApp_Helper_v97.log
   Cercare le righe "DIAGNOSTICA" per vedere cosa succede al focus, e la
   riga finale per sapere se ha aperto la chat con TAB+TAB+SPACE al primo
   giro, al secondo, o con il fallback Return.
   Log dell'installer stesso, se serve rivedere cosa ha fatto:
   /tmp/Cruscotto_Affitti_Installer.log
5. Provare il nuovo launcher: aprire "Cruscotto Affitti" da
   ~/Applications (o dal Launchpad/Spotlight) e verificare che si apra
   la finestra-app del Generatore. IMPORTANTE: rifare anche un invio
   WhatsApp di test con questa finestra-app aperta in parallelo, per
   verificare che l'automazione WhatsApp continui a funzionare come
   prima (vedi nota sul rischio nel punto 6k del pacchetto).
