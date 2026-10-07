#!/usr/bin/env python3
"""Esporta in formato Prometheus lo stato di Ollama (/api/ps, /api/tags, /api/version).

Ollama non ha un endpoint /metrics e non espone latenza o token/s per richiesta:
qui ci sono solo modelli caricati, VRAM, contesto e scadenza. I token processati
dal modello locale arrivano dalle metriche OTel di Claude Code (label `model`).
"""
import json
import os
import urllib.request
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

OLLAMA = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")
PORT = int(os.environ.get("EXPORTER_PORT", "9778"))


def get(path):
    with urllib.request.urlopen(OLLAMA + path, timeout=3) as r:
        return json.load(r)


def esc(v):
    return str(v).replace("\\", "\\\\").replace('"', '\\"')


def epoch(iso):
    # ISO 8601 con offset, es. 2026-10-07T17:59:50+02:00
    try:
        return datetime.fromisoformat(iso).timestamp()
    except ValueError:
        return 0


def render():
    out = []

    def metric(name, help_, typ, rows):
        out.append(f"# HELP {name} {help_}")
        out.append(f"# TYPE {name} {typ}")
        for labels, value in rows:
            lab = ",".join(f'{k}="{esc(v)}"' for k, v in labels.items())
            out.append(f"{name}{{{lab}}} {value}" if lab else f"{name} {value}")

    try:
        version = get("/api/version").get("version", "")
        running = get("/api/ps").get("models", [])
        installed = get("/api/tags").get("models", [])
        up = 1
    except Exception:
        version, running, installed, up = "", [], [], 0

    metric("ollama_up", "1 se Ollama risponde", "gauge", [({"version": version}, up)])
    if up:
        metric("ollama_models_installed", "Modelli scaricati", "gauge", [({}, len(installed))])
        base = lambda m: {
            "model": m["name"],
            "family": m.get("details", {}).get("family", ""),
            "parameter_size": m.get("details", {}).get("parameter_size", ""),
        }
        metric("ollama_model_loaded", "1 per ogni modello caricato in memoria", "gauge",
               [(base(m), 1) for m in running])
        metric("ollama_model_size_bytes", "Dimensione del modello caricato", "gauge",
               [(base(m), m.get("size", 0)) for m in running])
        metric("ollama_model_size_vram_bytes", "Parte del modello in VRAM / memoria unificata", "gauge",
               [(base(m), m.get("size_vram", 0)) for m in running])
        metric("ollama_model_context_length", "Contesto con cui il modello e' caricato", "gauge",
               [(base(m), m.get("context_length", 0)) for m in running])
        metric("ollama_model_expires_timestamp_seconds", "Quando Ollama scarica il modello", "gauge",
               [(base(m), epoch(m.get("expires_at", ""))) for m in running])
    return "\n".join(out) + "\n"


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        body = render().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), H).serve_forever()
