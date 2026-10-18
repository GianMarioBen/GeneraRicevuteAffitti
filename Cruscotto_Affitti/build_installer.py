#!/usr/bin/env python3
"""Genera Installa_Cruscotto_Affitti_<versione>.command (tutto-in-uno).

Uso (dalla cartella Cruscotto_Affitti):
    python3 build_installer.py v139 "descrizione breve della versione"

Prende il modello Installer_Template.command.in e ci incorpora i sorgenti
di questa cartella. Il motore usato è WhatsApp_Engine_<versione>.applescript,
che deve esistere.
"""
import base64
import os
import sys
import textwrap

HERE = os.path.dirname(os.path.abspath(__file__))


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as fh:
        return fh.read().rstrip("\n")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    ver, desc = sys.argv[1], sys.argv[2]
    if '"' in desc:
        sys.exit("La descrizione non deve contenere doppi apici.")

    with open(os.path.join(HERE, "CruscottoAffitti.icns"), "rb") as fh:
        icon_b64 = "\n".join(textwrap.wrap(base64.b64encode(fh.read()).decode("ascii"), 76))

    payloads = {
        "ENGINE": read("WhatsApp_Engine_%s.applescript" % ver),
        "HTML": read("Generatore_Ricevute_Condominio_v120.html"),
        "SERVER": read("Cruscotto_Affitti_Server.py"),
        "RUNNER": read("Avvia_Cruscotto_Affitti_Server.sh"),
        "PLIST": read("com.letmar.cruscottoaffitti.server.plist"),
        "LAUNCHER": read("Cruscotto_Affitti_Launcher.applescript"),
        "HELPER": read("Invia_Ricevuta_WhatsApp_Helper.applescript"),
        "ICON_B64": icon_b64,
    }

    out = read("Installer_Template.command.in")
    for key, body in payloads.items():
        if "___CRUSCOTTO_PAYLOAD_" in body:
            sys.exit("Il sorgente %s contiene un terminatore heredoc." % key)
        marker = "@@PAYLOAD:%s@@" % key
        if out.count(marker) != 1:
            sys.exit("Segnaposto %s non trovato (o ripetuto) nel modello." % marker)
        out = out.replace(marker, body)
    out = out.replace("@@VER@@", ver).replace("@@DESC@@", desc)
    for token in ("@@VER@@", "@@DESC@@", "@@PAYLOAD:"):
        if token in out:
            sys.exit("Segnaposto non sostituito nel risultato: %s" % token)

    target = os.path.join(HERE, "Installa_Cruscotto_Affitti_%s.command" % ver)
    with open(target, "w", encoding="utf-8") as fh:
        fh.write(out + "\n")
    os.chmod(target, 0o755)
    print("Scritto: %s %d byte" % (target, os.path.getsize(target)))


if __name__ == "__main__":
    main()
