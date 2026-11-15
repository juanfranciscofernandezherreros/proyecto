# -*- coding: utf-8 -*-
r"""Lanzador: reextraer y reimportar partidos concretos, aunque ya esten importados.
Uso: reextraer.py [--dataset equipo|jugadores|resumen|jugadas|todo] [--fichero lista.txt] [--progreso progreso.txt] <match_id...>"""
import sys
from _base import ensure, run_mod

if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        print("Uso: basket reextraer [--dataset equipo|jugadores|resumen|jugadas|todo] [--fichero lista.txt] [--progreso progreso.txt] <match_id...>")
        sys.exit(1)
    if ensure("antibloqueo", "postgres", "launcher", "navegador"):
        sys.exit(1)
    rc = run_mod("extraer/reextraer.py", *a)
    print(f"\nTerminado con codigo {rc}.")
    sys.exit(rc)
