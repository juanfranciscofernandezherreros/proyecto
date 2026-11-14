# -*- coding: utf-8 -*-
r"""Monitor en vivo de partidos pendientes segun la auditoria de fixtures (equivale a
scripts\monitor\VER_PENDIENTES_FIXTURES_EN_VIVO.ps1 + .bat, sin PowerShell).

Refresca cada 5 s desde el endpoint /latest. Ctrl+C para cerrar.

Uso:  python scripts\py\monitor\ver_pendientes.py [--una-vez]
"""
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

SCRIPTS_PY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_PY))
import config as _config
sys.path.insert(0, str(SCRIPTS_PY / "arranque"))
import asegurar

CFG = _config.cargar()
URI = f"{CFG['AUDIT_URL']}/latest"
COLS = ["matchDate", "country", "competition", "matchId", "homeTeam", "awayTeam", "datasets_faltantes"]


def _tabla(matches):
    filas = [{**{c: m.get(c, "") for c in COLS[:-1]},
              "datasets_faltantes": ",".join(m.get("pendingDatasets") or [])} for m in matches]
    anchos = {c: max(len(c), *(len(str(f.get(c, ""))) for f in filas)) if filas else len(c) for c in COLS}
    out = ["  ".join(c.ljust(anchos[c]) for c in COLS),
           "  ".join("-" * anchos[c] for c in COLS)]
    for f in filas:
        out.append("  ".join(str(f.get(c, "")).ljust(anchos[c]) for c in COLS))
    return "\n".join(out)


def _render():
    try:
        snapshot = json.loads(urllib.request.urlopen(URI, timeout=8).read().decode("utf-8"))
        os.system("cls")
        print("PENDIENTES DE PROCESAR - AUDITORIA DE FIXTURES")
        print(f"Actualizado: {snapshot.get('refreshedAt')} | Estado: {snapshot.get('status')} | "
              f"Pendientes: {snapshot.get('pendingFixtures')}")
        print("La lista se refresca desde PostgreSQL cada 5 segundos. Cierra con Ctrl+C.")
        if snapshot.get("status") != "COMPLETED":
            print(f"Error de auditoria: {snapshot.get('error')}")
        elif not snapshot.get("pendingMatches"):
            print("No quedan partidos pendientes.")
        else:
            print(_tabla(snapshot["pendingMatches"]))
    except Exception as e:
        os.system("cls")
        print("PENDIENTES DE PROCESAR - AUDITORIA DE FIXTURES")
        print(f"Esperando endpoint {URI}: {e}")


def main():
    una_vez = "--una-vez" in sys.argv
    if not una_vez:
        asegurar.main(["auditoria"])
    while True:
        _render()
        if una_vez:
            return 0
        time.sleep(5)


if __name__ == "__main__":
    sys.exit(main())
