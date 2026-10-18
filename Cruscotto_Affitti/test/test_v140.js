// Prove v140 contro il server reale (vedi setup.sh)
const { chromium } = require('playwright');
const fs = require('fs');
const { execSync } = require('child_process');
const T = __dirname;
const D = T + '/root/ElencoRicevute';
const URL = 'http://127.0.0.1:8765/Generatore_Ricevute_Condominio.html';
const setup = () => execSync(T + '/setup.sh', { stdio: 'ignore' });
const readJ = f => JSON.parse(fs.readFileSync(D + '/' + f, 'utf8'));
const backups = () => { try { return fs.readdirSync(T + '/home/Library/Application Support/CruscottoAffitti/Backup_Dati'); } catch (e) { return []; } };
let fails = 0;
const check = (ok, what) => { console.log((ok ? 'OK   ' : 'FAIL ') + what); if (!ok) fails++; };

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });

  async function openPage(routeFn) {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    const dialogs = [], errors = [];
    page.on('dialog', d => { dialogs.push(d.message()); d.accept(); });
    page.on('pageerror', e => errors.push(String(e)));
    if (routeFn) await routeFn(page);
    await page.goto(URL);
    await page.waitForTimeout(2500);
    return { ctx, page, dialogs, errors };
  }

  // --- 1. avvio normale -----------------------------------------------------
  setup();
  let { ctx, page, dialogs, errors } = await openPage();
  const title = await page.textContent('h1');
  check(/v141/.test(title), 'etichetta v141 nel titolo');
  const people = await page.evaluate(() => PEOPLE.filter(p => !/^BOX/i.test(p.tipo || '')).map(p => p.nominativo + '=' + p.telefono));
  check(people.includes('ANTAR=3331112222') && people.includes('RACHIDA='), 'affittuari letti da Affittuari.json: ' + people.slice(0, 3).join(', '));
  check(dialogs.length === 0, 'nessun avviso all\'avvio normale (' + dialogs.join(' | ') + ')');

  // --- 2. numero mancante: avviso visibile ------------------------------------
  await page.evaluate(() => sharePdfEntry({ name: 'Ricevuta_SHAWKY.pdf' }));
  await page.waitForTimeout(300);
  check(dialogs.some(m => /Numero WhatsApp mancante per SHAWKY/.test(m) && /NON è stata inviata/.test(m)), 'avviso "Numero WhatsApp mancante per SHAWKY" mostrato');
  check(!fs.existsSync(D + '/WhatsApp_Destinatario.json'), 'nessuna richiesta di invio partita verso il server');

  // anche dall'anteprima PDF (pulsante "Invia via WhatsApp")
  dialogs.length = 0;
  await page.evaluate(() => {
    const i = PEOPLE.findIndex(p => p.nominativo === 'SHAWKY');
    $('persona').value = String(i); $('persona').dispatchEvent(new Event('change'));
    openPdfPreview(new File(['%PDF'], 'x.pdf', { type: 'application/pdf' }), 'Ricevuta_SHAWKY.pdf');
  });
  await page.click('#whatsappShareBtn');
  await page.waitForTimeout(300);
  check(dialogs.some(m => /Numero WhatsApp mancante/.test(m)), 'avviso anche dal pulsante dell\'anteprima');
  await page.evaluate(() => closePdfPreview());

  // --- 3. recupero numeri dalle ricevute ----------------------------------------
  const before = fs.readFileSync(D + '/Affittuari.json', 'utf8');
  await page.evaluate(() => openSettings());
  await page.waitForTimeout(500);
  await page.click('button.setup-recover');
  await page.waitForTimeout(200);
  const rep = await page.textContent('#tenantRecoverStatus');
  const rachidaTel = await page.evaluate(() => [...document.querySelectorAll('#tenantSetupRows .tenant-setup-row')].find(r => r.querySelector('[data-field=nominativo]').value === 'RACHIDA').querySelector('[data-field=telefono]').value);
  check(rachidaTel === '+39 345 000 1111', 'RACHIDA riempita con il numero della ricevuta più recente (' + rachidaTel + ')');
  check(/SHAWKY/.test(rep.split('Ancora senza numero')[1] || ''), 'SHAWKY segnalato come ancora senza numero');
  check(/ZANATI \(5\) → 3201234567/.test(rep), 'ZANATI (non in elenco) segnalato come presente nelle ricevute ma non nell\'elenco');
  check(fs.readFileSync(D + '/Affittuari.json', 'utf8') === before, 'il recupero da solo NON salva Affittuari.json');
  await page.screenshot({ path: T + '/recupero.png', fullPage: false });
  const nb = backups().length;
  await page.click('button.setup-save:has-text("Salva modifiche affittuari")');
  await page.waitForTimeout(800);
  const rachidaSaved = readJ('Affittuari.json').find(p => p.nominativo === 'RACHIDA');
  check(rachidaSaved && rachidaSaved.telefono === '+39 345 000 1111', 'dopo "Salva" il numero di RACHIDA è in Affittuari.json');
  check(backups().filter(f => f.startsWith('Affittuari_')).length > nb - 0 && backups().length > nb, 'il server ha salvato una copia di sicurezza prima di sovrascrivere (' + backups().length + ' copie)');
  check(errors.length === 0, 'nessun errore JavaScript (' + errors.join(' | ') + ')');
  await ctx.close();

  // --- 4. server che risponde male su Affittuari.json: il file NON si tocca ----
  setup();
  const orig = fs.readFileSync(D + '/Affittuari.json', 'utf8');
  ({ ctx, page, dialogs, errors } = await openPage(p => p.route(/api\/fs\/file\?name=Affittuari\.json/, (route, req) =>
    req.method() === 'GET' ? route.fulfill({ status: 500, body: '{"ok":false}' }) : route.continue())));
  check(dialogs.some(m => /non riesco a leggere Affittuari\.json/.test(m)), 'avviso se Affittuari.json non si legge (errore 500)');
  check(fs.readFileSync(D + '/Affittuari.json', 'utf8') === orig, 'Affittuari.json NON riscritto con l\'elenco di base');
  const blocked = await page.evaluate(() => saveTenantsFile().then(() => 'salvato', e => 'bloccato: ' + e.message));
  check(/^bloccato/.test(blocked), 'salvataggio dell\'elenco bloccato finché il file non è stato letto');
  await ctx.close();

  // stesso caso con il server irraggiungibile (connessione rifiutata)
  ({ ctx, page, dialogs, errors } = await openPage(p => p.route(/api\/fs\/file\?name=Affittuari\.json/, (route, req) =>
    req.method() === 'GET' ? route.abort('connectionrefused') : route.continue())));
  check(dialogs.some(m => /non riesco a leggere Affittuari\.json/.test(m)) && fs.readFileSync(D + '/Affittuari.json', 'utf8') === orig, 'connessione rifiutata: avviso e file intatto');
  await ctx.close();

  // --- 5. Ricevute_Dati.json illeggibile: lo storico NON si tocca --------------
  const origLookup = fs.readFileSync(D + '/Ricevute_Dati.json', 'utf8');
  ({ ctx, page, dialogs, errors } = await openPage(p => p.route(/api\/fs\/file\?name=Ricevute_Dati\.json/, (route, req) =>
    req.method() === 'GET' ? route.fulfill({ status: 500, body: '{}' }) : route.continue())));
  check(dialogs.some(m => /non riesco a leggere Ricevute_Dati\.json/.test(m)), 'avviso se Ricevute_Dati.json non si legge');
  const blocked2 = await page.evaluate(() => saveLookup().then(() => 'salvato', e => 'bloccato'));
  check(blocked2 === 'bloccato' && fs.readFileSync(D + '/Ricevute_Dati.json', 'utf8') === origLookup, 'Ricevute_Dati.json intatto e salvataggio bloccato');
  await ctx.close();

  // --- 6. file davvero assente (404): si crea dall'elenco di base, come prima ----
  fs.unlinkSync(D + '/Affittuari.json');
  ({ ctx, page, dialogs, errors } = await openPage());
  check(fs.existsSync(D + '/Affittuari.json') && readJ('Affittuari.json').some(p => p.nominativo === 'KYOSEV'), 'Affittuari.json mancante: ricreato dall\'elenco di base');
  check(dialogs.length === 0, 'nessun avviso quando il file semplicemente non esiste');
  await ctx.close();

  // --- 7. storia delle versioni ----------------------------------------------
  ({ ctx, page, dialogs, errors } = await openPage());
  await page.evaluate(() => openHistory());
  const items = await page.$$eval('#historyModal li', l => l.length);
  const first = await page.textContent('#historyModal li');
  check(items === 26 && /^v141/.test(first.trim()), 'storia: 26 voci, la prima è v141');
  check(errors.length === 0, 'nessun errore JavaScript');
  await ctx.close();

  await browser.close();
  console.log(fails ? fails + ' PROVE FALLITE' : 'TUTTE LE PROVE SUPERATE');
  process.exit(fails ? 1 : 0);
})();
