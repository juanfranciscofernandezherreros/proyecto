# -*- coding: utf-8 -*-
r"""Lanzador: extraer RESULTS (EXTRAER_RESULTADOS.bat). Envoltorio de orquestar en
modo results.  Uso: extraer_resultados.py [LIGA] [limite]"""
import sys
from _base import ensure, run_mod

if __name__ == "__main__":
    a = sys.argv[1:]
    liga = a[0] if len(a) > 0 else "ALL"
    limite = a[1] if len(a) > 1 else "10"
    print(f"Extrayendo RESULTS de {liga} (limite: {a[1] if len(a) > 1 else ''})...")
    if ensure("antibloqueo", "postgres", "launcher", "navegador"):
        sys.exit(1)
    rc = run_mod("ligas/orquestar.py", liga, "results", limite)
    print(f"\nTerminado con codigo {rc}. Los marcadores se cargan en Postgres (results.results).")
    sys.exit(rc)
