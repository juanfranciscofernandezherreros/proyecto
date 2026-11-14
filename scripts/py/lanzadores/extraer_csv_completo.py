# -*- coding: utf-8 -*-
r"""Lanzador: extraer el resto de CSV y procesar pendientes (EXTRAER_CSV_COMPLETO.bat).
Uso: extraer_csv_completo.py [LIGA] [limite]"""
import sys
from pathlib import Path
from _base import run_mod

LANZ = Path(__file__).resolve().parent

if __name__ == "__main__":
    a = sys.argv[1:]
    liga = a[0] if len(a) > 0 else "ALL"
    limite = a[1] if len(a) > 1 else ""
    print(f"\n=== 1) Extraer datos (point-by-point, team-stats, player-stats) de {liga} ===")
    args = [liga, "datos"] + ([limite] if limite else [])
    if run_mod("lanzadores/ligas_orquestar.py", *args):
        print("[AVISO] La extraccion de datos devolvio error; se continua con los pendientes.")
    print("\n=== 2) Procesar partidos pendientes ===")
    rc = run_mod("lanzadores/matchids_pendientes.py")
    print(f"\nTerminado con codigo {rc}.")
    sys.exit(rc)
