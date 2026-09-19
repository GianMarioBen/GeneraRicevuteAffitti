#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import print_function

import json
import mimetypes
import os
import sys
import time
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs, unquote

ROOT_DIR = os.environ.get(
    "CRUSCOTTO_ROOT",
    "/Users/bless/Archivio/Appart/Ricevute Affittuari",
)
DATA_DIR = os.path.join(ROOT_DIR, "ElencoRicevute")
HTML_NAME = "Generatore_Ricevute_Condominio.html"
HTML_PATH = os.path.join(ROOT_DIR, HTML_NAME)
HOST = os.environ.get("CRUSCOTTO_HOST", "127.0.0.1")
PORT = int(os.environ.get("CRUSCOTTO_PORT", "8765"))
MAX_UPLOAD = 80 * 1024 * 1024

APP_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/CruscottoAffitti")
ENGINE_VERSION_FILE = os.path.join(APP_SUPPORT_DIR, "WhatsApp_Engine_Version.json")

def read_whatsapp_engine_info():
    try:
        with open(ENGINE_VERSION_FILE, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict) and data.get("version"):
            return data
    except Exception:
        pass
    return None

def safe_name(raw):
    name = unquote(raw or "").strip()
    if not name:
        raise ValueError("Nome file vuoto")
    if name in (".", ".."):
        raise ValueError("Nome non valido")
    if "/" in name or "\\" in name or "\x00" in name:
        raise ValueError("Percorso non valido")
    if os.path.basename(name) != name:
        raise ValueError("Percorso non valido")
    return name

def data_path(name):
    return os.path.join(DATA_DIR, safe_name(name))

class Handler(BaseHTTPRequestHandler):
    server_version = "CruscottoAffitti/7.0"

    def log_message(self, fmt, *args):
        sys.stderr.write(
            "%s - - [%s] %s\n"
            % (self.client_address[0], self.log_date_time_string(), fmt % args)
        )

    def send_no_cache(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, PUT, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")

    def send_json(self, obj, status=200):
        payload = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_no_cache()
        self.end_headers()
        self.wfile.write(payload)

    def send_error_json(self, message, status=400):
        self.send_json({"ok": False, "error": str(message)}, status=status)

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/api/health":
            self.send_json({
                "ok": True,
                "mode": "server-filesystem",
                "dataDir": DATA_DIR,
                "version": 7,
                "whatsappEngine": read_whatsapp_engine_info(),
            })
            return

        if parsed.path == "/api/fs/list":
            try:
                os.makedirs(DATA_DIR, exist_ok=True)
                items = []
                for name in os.listdir(DATA_DIR):
                    path = os.path.join(DATA_DIR, name)
                    if os.path.isfile(path):
                        st = os.stat(path)
                        items.append({
                            "kind": "file",
                            "name": name,
                            "lastModified": int(st.st_mtime * 1000),
                            "size": int(st.st_size),
                        })
                self.send_json(items)
            except Exception as exc:
                self.send_error_json(exc, 500)
            return

        if parsed.path == "/api/fs/file":
            try:
                query = parse_qs(parsed.query)
                name = safe_name((query.get("name") or [""])[0])
                path = data_path(name)
                if not os.path.isfile(path):
                    self.send_error_json("File non trovato", 404)
                    return
                with open(path, "rb") as fh:
                    data = fh.read()
                mime = mimetypes.guess_type(name)[0] or "application/octet-stream"
                st = os.stat(path)
                self.send_response(200)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("X-Last-Modified-Ms", str(int(st.st_mtime * 1000)))
                self.send_no_cache()
                self.end_headers()
                self.wfile.write(data)
            except ValueError as exc:
                self.send_error_json(exc, 400)
            except Exception as exc:
                self.send_error_json(exc, 500)
            return

        if parsed.path in ("/", "/" + HTML_NAME):
            try:
                if not os.path.isfile(HTML_PATH):
                    self.send_error_json("Generatore HTML non trovato", 404)
                    return
                with open(HTML_PATH, "rb") as fh:
                    data = fh.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.send_no_cache()
                self.end_headers()
                self.wfile.write(data)
            except Exception as exc:
                self.send_error_json(exc, 500)
            return

        self.send_error_json("Risorsa non trovata", 404)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_no_cache()
        self.end_headers()

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path == "/api/whatsapp/start":
            self.send_error_json(
                "Endpoint diagnostico non usato dalla v97. Usa /api/whatsapp/prepare.",
                409,
            )
            return

        if parsed.path == "/api/whatsapp/prepare":
            try:
                length = int(self.headers.get("Content-Length", "0") or "0")
                if length < 0 or length > 1024 * 1024:
                    self.send_error_json("Richiesta troppo grande", 413)
                    return

                raw = self.rfile.read(length).decode("utf-8")
                data = json.loads(raw or "{}")
                pdf_name = safe_name(str(data.get("pdfName") or ""))
                message_text = str(data.get("messageText") or "").strip()

                pdf_path = data_path(pdf_name)
                if not os.path.isfile(pdf_path):
                    self.send_error_json("PDF non trovato: " + pdf_name, 404)
                    return

                os.makedirs(DATA_DIR, exist_ok=True)

                with open(os.path.join(DATA_DIR, "Ricevuta_Da_Inviare.txt"), "w", encoding="utf-8") as fh:
                    fh.write(pdf_name)

                with open(os.path.join(DATA_DIR, "Messaggio_Da_Inviare.txt"), "w", encoding="utf-8") as fh:
                    fh.write(message_text)

                helper_app = os.path.expanduser("~/Applications/Invia Ricevuta WhatsApp.app")
                if not os.path.isdir(helper_app):
                    self.send_error_json(
                        "Helper WhatsApp v97 non trovato in ~/Applications.",
                        500,
                    )
                    return

                log_path = "/tmp/Invia_Ricevuta_WhatsApp_Server.log"
                log_fh = open(log_path, "ab", 0)
                subprocess.Popen(
                    ["/usr/bin/open", helper_app],
                    stdout=log_fh,
                    stderr=log_fh,
                    close_fds=True,
                )
                log_fh.close()

                self.send_json({
                    "ok": True,
                    "prepared": pdf_name,
                    "started": "whatsapp-helper-v97",
                })
            except ValueError as exc:
                self.send_error_json(exc, 400)
            except Exception as exc:
                self.send_error_json(exc, 500)
            return

        self.send_error_json("Risorsa non trovata", 404)

    def do_PUT(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/fs/file":
            self.send_error_json("Risorsa non trovata", 404)
            return

        try:
            query = parse_qs(parsed.query)
            name = safe_name((query.get("name") or [""])[0])

            length = int(self.headers.get("Content-Length", "0") or "0")
            if length < 0 or length > MAX_UPLOAD:
                self.send_error_json("File troppo grande", 413)
                return

            payload = self.rfile.read(length)
            os.makedirs(DATA_DIR, exist_ok=True)
            target = data_path(name)
            temp = target + ".cruscotto-tmp-%d" % os.getpid()

            with open(temp, "wb") as fh:
                fh.write(payload)
                fh.flush()
                os.fsync(fh.fileno())

            os.replace(temp, target)
            self.send_json({"ok": True, "name": name, "size": len(payload)})
        except ValueError as exc:
            self.send_error_json(exc, 400)
        except Exception as exc:
            try:
                if "temp" in locals() and os.path.exists(temp):
                    os.unlink(temp)
            except Exception:
                pass
            self.send_error_json(exc, 500)

    def do_DELETE(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/fs/file":
            self.send_error_json("Risorsa non trovata", 404)
            return

        try:
            query = parse_qs(parsed.query)
            name = safe_name((query.get("name") or [""])[0])
            path = data_path(name)
            if not os.path.exists(path):
                self.send_error_json("File non trovato", 404)
                return
            if not os.path.isfile(path):
                self.send_error_json("Non è un file", 400)
                return
            os.unlink(path)
            self.send_json({"ok": True, "name": name})
        except ValueError as exc:
            self.send_error_json(exc, 400)
        except Exception as exc:
            self.send_error_json(exc, 500)

def main():
    os.makedirs(DATA_DIR, exist_ok=True)
    httpd = HTTPServer((HOST, PORT), Handler)
    print("Cruscotto Affitti server attivo su http://%s:%d" % (HOST, PORT))
    print("Dati:", DATA_DIR)
    httpd.serve_forever()

if __name__ == "__main__":
    main()
