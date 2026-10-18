const { chromium } = require('playwright'); const fs=require('fs'); const {execSync}=require('child_process');
const T=__dirname, D=T+'/root/ElencoRicevute', URL='http://127.0.0.1:8765/Generatore_Ricevute_Condominio.html';
const BK=T+'/home/Library/Application Support/CruscottoAffitti/Backup_Dati';
const nb=()=>{try{return fs.readdirSync(BK).length}catch(e){return 0}};
let fails=0; const check=(ok,w)=>{console.log((ok?'OK   ':'FAIL ')+w); if(!ok) fails++;};
const tel=(j,n)=>(j.find(p=>p.nominativo===n)||{}).telefono;
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome'});
  async function load(){const c=await b.newContext();const p=await c.newPage();const errs=[],dl=[];p.on('pageerror',e=>errs.push(String(e)));p.on('dialog',d=>{dl.push(d.message());d.accept()});await p.goto(URL);await p.waitForTimeout(2500);const st=await p.textContent('#status');const h=await p.textContent('h1');await c.close();return {errs,dl,st,h};}

  // Scenario A: file mancante -> ricreato dall'elenco di base, con i numeri
  execSync(T+'/setup.sh',{stdio:'ignore'}); fs.unlinkSync(D+'/Affittuari.json');
  let r=await load(); let j=JSON.parse(fs.readFileSync(D+'/Affittuari.json','utf8'));
  check(/v142/.test(r.h),'etichetta v142');
  check(tel(j,'RACHIDA')==='3271242094','A: RACHIDA ha il numero 3271242094');
  check(tel(j,'KYOSEV')==='3273555511' && tel(j,'AHMED SHAABAM MAMDOUH FARAG')==='3398809798','A: Sordio e Bosco B riempiti');
  check(!tel(j,'SALAHELDIN MOHAMED SAKR') && !tel(j,'ELSAYED'),'A: App 7 e Bosco A restano vuoti (numero non fornito)');
  check(tel(j,'HORDIICHUK ILLIA')==='3402471686','A: Box 12 riempito');
  check((j.find(p=>p.tipo==='Box'&&p.appartamento.replace(/\D/g,'').replace(/^0+/,'')==='2')||{}).nominativo==='CHAFAI MABROUK','A: Box 2 non toccato');
  check(r.errs.length===0 && r.dl.length===0,'A: nessun errore né avviso');

  // Scenario B: file esistente con un numero diverso e un inquilino nuovo
  execSync(T+'/setup.sh',{stdio:'ignore'});
  const base=JSON.parse(fs.readFileSync(D+'/Affittuari.json','utf8'));
  const def=[["ABDEL GHANI","1"],["SHAWKY","2"],["ANTAR","3"],["NUOVO INQUILINO","4"],["ZANATI","5"],["RACHIDA","8"],["EL SAMKARI","11"]]
    .map(([n,u])=>({nominativo:n,tipo:'Appartamento',appartamento:u,indirizzo:'San Giuliano Milanese - Via Trieste, 44',canone:700,telefono:n==='ANTAR'?'3331112222':''}));
  def.push({nominativo:'ELSAYED',tipo:'Appartamento',appartamento:"2' piano A",indirizzo:'San Giuliano Milanese - Via Don Bosco, 20',canone:700,telefono:''});
  def.push({nominativo:'AHMED SHAABAM MAMDOUH FARAG',tipo:'Appartamento',appartamento:"2' piano B",indirizzo:'San Giuliano Milanese - Via Don Bosco, 20',canone:1000,telefono:''});
  fs.writeFileSync(D+'/Affittuari.json',JSON.stringify(def,null,2));
  r=await load(); j=JSON.parse(fs.readFileSync(D+'/Affittuari.json','utf8'));
  check(tel(j,'ANTAR')==='3331112222','B: ANTAR conserva il suo numero (non sovrascritto)');
  check(tel(j,'NUOVO INQUILINO')==='','B: inquilino nuovo dell\'App 4 NON riceve il numero del vecchio');
  check(tel(j,'RACHIDA')==='3271242094' && tel(j,'ZANATI')==='3806848599' && tel(j,'SHAWKY')==='3285515288','B: RACHIDA, ZANATI, SHAWKY riempiti');
  check(tel(j,'AHMED SHAABAM MAMDOUH FARAG')==='3398809798' && tel(j,'ELSAYED')==='','B: Bosco B riempito, Bosco A vuoto');
  check(/Inseriti 6 numeri WhatsApp mancanti/.test(r.st),'B: messaggio "'+r.st+'"');
  check(nb()>=1,'B: copia di sicurezza fatta dal server prima di scrivere');
  const before=fs.readFileSync(D+'/Affittuari.json','utf8'), n1=nb();
  r=await load();
  check(fs.readFileSync(D+'/Affittuari.json','utf8')===before && nb()===n1,'B: seconda apertura non riscrive nulla');
  check(r.errs.length===0,'B: nessun errore JavaScript');
  await b.close(); console.log(fails?fails+' PROVE FALLITE':'TUTTE LE PROVE SUPERATE'); process.exit(fails?1:0);
})();
