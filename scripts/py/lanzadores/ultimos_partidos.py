# -*- coding: utf-8 -*-
r"""Lanzador: procesar ultimos partidos de una liga (ULTIMOS_PARTIDOS.bat)."""
import sys
from _base import ensure, run_mod

if __name__ == "__main__":
    if ensure("antibloqueo", "postgres", "launcher", "navegador"):
        sys.exit(1)
    rc = run_mod("ligas/ultimos_partidos.py", *sys.argv[1:])
    print("\n[OK] Flujo completo terminado." if rc == 0 else "\n[ERROR] Flujo terminado con errores.")
    sys.exit(rc)
