# -*- coding: utf-8 -*-
r"""Helpers compartidos de los importadores (envio de CSV al launcher y verificacion
en Postgres). Sin PowerShell. Lo usan resultados.py y los PROCESAR_* de stats.
"""
import json
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "arranque"))
import asegurar


class FalloImport(Exception):
    pass


def run_id():
    return datetime.now().strftime("%Y%m%d%H%M%S")


def asegurar_servicios(*servicios):
    """Asegura postgres,launcher (equivale a '& ASEGURAR_SERVICIOS.ps1')."""
    if asegurar.main(list(servicios)) != 0:
        raise FalloImport(f"No se pudieron asegurar los servicios: {','.join(servicios)}.")


def _get(url, timeout=30):
    r = urllib.request.urlopen(url, timeout=timeout)
    return json.loads(r.read().decode("utf-8"))


def _post(url, payload, timeout=30):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST",
                                 headers={"Content-Type": "application/json"})
    r = urllib.request.urlopen(req, timeout=timeout)
    return json.loads(r.read().decode("utf-8"))


def submit_and_wait(cfg, file_path, timeout_min=15):
    """Envia un CSV al launcher y espera a que termine. Devuelve el dict final del
    request. Lanza FalloImport si no llega a estado terminal dentro del plazo."""
    base = cfg["LAUNCHER_URL"]
    req = _post(f"{base}/batch-launches", {"file": str(file_path)})
    deadline = time.time() + timeout_min * 60
    while req.get("status") in ("QUEUED", "RUNNING") and time.time() < deadline:
        if req.get("status") in ("COMPLETED", "FAILED"):
            return req
        time.sleep(2)
        req = _get(f"{base}/batch-launches/{req.get('requestId')}")
    if req.get("status") not in ("COMPLETED", "FAILED"):
        raise FalloImport(f"Tiempo de espera agotado para {Path(file_path).name}.")
    return req


def psql_valor(cfg, query):
    """Ejecuta una consulta de un solo valor via `docker compose exec postgres psql`.
    Devuelve el texto de la ultima linea, o lanza FalloImport si psql falla."""
    compose = cfg.get("COMPOSE_FILE")
    p = subprocess.run(
        ["docker", "compose", "-f", compose, "exec", "-T", "postgres",
         "psql", "-U", cfg.get("DB_USER"), "-d", cfg.get("DB_NAME"),
         "--no-psqlrc", "--tuples-only", "--no-align", "--command", query],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if p.returncode != 0:
        raise FalloImport("fallo la consulta de verificacion en PostgreSQL.")
    lineas = [l for l in p.stdout.splitlines() if l.strip()]
    return lineas[-1].strip() if lineas else ""


def tabla(filas, columnas):
    """Tabla de texto simple (aproxima Format-Table). filas: lista de dicts."""
    anchos = {c: max(len(c), *(len(str(f.get(c, ""))) for f in filas)) if filas else len(c) for c in columnas}
    out = ["  ".join(c.ljust(anchos[c]) for c in columnas),
           "  ".join("-" * anchos[c] for c in columnas)]
    for f in filas:
        out.append("  ".join(str(f.get(c, "")).ljust(anchos[c]) for c in columnas))
    return "\n".join(out)
