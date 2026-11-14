# -*- coding: utf-8 -*-
r"""Lanzador: procesar partidos pendientes (MATCHIDS_PENDIENTES.bat).
Uso: matchids_pendientes.py [csv_seleccion] [limite]"""
import os
import sys
from _base import ensure, run_mod, CFG

if __name__ == "__main__":
    os.environ["SKIP_CSV_WATCHER"] = "1"
    a = sys.argv[1:]
    if ensure("antibloqueo", "postgres", "auditoria", "launcher", "navegador"):
        print("ERROR: no se pudieron asegurar los servicios necesarios.")
        sys.exit(1)
    print("El proceso refrescara la auditoria antes de empezar y despues de cada partido.")
    rc = run_mod("pendientes/procesar_matchids.py", *a)
    if rc:
        print(f"ERROR: el procesamiento termino con codigo {rc}.")
    else:
        print(f"Procesamiento terminado. Consulta el CSV de resumen generado en {CFG.get('REPORT_DIR')}.")
    sys.exit(rc)
