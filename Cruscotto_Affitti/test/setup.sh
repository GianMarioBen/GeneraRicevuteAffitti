#!/bin/bash
# Prove del Generatore contro il server REALE con dati finti (cartelle root/ e home/ qui accanto).
# Uso, dalla cartella del repo:  NODE_PATH=$(npm root -g) node Cruscotto_Affitti/test/test_v140.js  (e test_v141.js)
# ricrea i dati di prova e (ri)avvia il server reale
T=$(cd "$(dirname "$0")" && pwd)
D=$T/root/ElencoRicevute
[ -f "$T/server.pid" ] && kill "$(cat "$T/server.pid")" 2>/dev/null; sleep 0.5
if curl -s -m 1 -o /dev/null http://127.0.0.1:8765/api/health; then
  echo "ATTENZIONE: la porta 8765 è occupata da un altro server (prove precedenti?): chiudilo prima." >&2
  exit 1
fi
rm -rf "$D" "$T/home/Library"; mkdir -p "$D"
cp "$T/../Generatore_Ricevute_Condominio_v120.html" "$T/root/Generatore_Ricevute_Condominio.html"
cat > "$D/Affittuari.json" <<'J'
[
 {"nominativo":"ANTAR","tipo":"Appartamento","appartamento":"3","indirizzo":"Via Prova, 1","canone":950,"telefono":"3331112222"},
 {"nominativo":"RACHIDA","tipo":"Appartamento","appartamento":"8","indirizzo":"Via Prova, 1","canone":700,"telefono":""},
 {"nominativo":"SHAWKY","tipo":"Appartamento","appartamento":"2","indirizzo":"Via Prova, 1","canone":860,"telefono":""}
]
J
cat > "$D/Ricevute_Dati.json" <<'J'
{
 "Ricevuta_RACHIDA_nuova.pdf":{"nominativo":"RACHIDA","tipo":"Appartamento","unita":"8","dataPagamento":"2026-09-01","meseRiferimento":"Settembre","annoRiferimento":"2026","telefono":"+39 345 000 1111"},
 "Ricevuta_RACHIDA_vecchia.pdf":{"nominativo":"RACHIDA","tipo":"Appartamento","unita":"8","dataPagamento":"2026-03-01","meseRiferimento":"Marzo","annoRiferimento":"2026","telefono":"3459999999"},
 "Ricevuta_BEHI.pdf":{"nominativo":"ZANATI","tipo":"Appartamento","unita":"5","dataPagamento":"2026-09-27","meseRiferimento":"Settembre","annoRiferimento":"2026","telefono":"3201234567"},
 "Ricevuta_SHAWKY.pdf":{"nominativo":"SHAWKY","tipo":"Appartamento","unita":"2","dataPagamento":"2026-09-05","meseRiferimento":"Settembre","annoRiferimento":"2026","telefono":""}
}
J
for f in Ricevuta_RACHIDA_nuova Ricevuta_RACHIDA_vecchia Ricevuta_BEHI Ricevuta_SHAWKY; do printf '%%PDF-1.4\n%%EOF\n' > "$D/$f.pdf"; done
cd "$T" && HOME="$T/home" CRUSCOTTO_ROOT="$T/root" nohup python3 "$T/../Cruscotto_Affitti_Server.py" > "$T/server.log" 2>&1 &
echo $! > "$T/server.pid"
for i in $(seq 1 30); do curl -s -m 1 http://127.0.0.1:8765/api/health >/dev/null && break; sleep 0.2; done
