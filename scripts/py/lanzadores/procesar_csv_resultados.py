# -*- coding: utf-8 -*-
r"""Lanzador: procesar CSV de RESULTS ya en disco (PROCESAR_CSV_RESULTADOS.bat).
Uso: procesar_csv_resultados.py [LIGA] [todos]"""
import sys
from _base import ensure, run_mod

if __name__ == "__main__":
    a = sys.argv[1:]
    liga = a[0] if len(a) > 0 else "ALL"
    if ensure("postgres", "launcher"):
        sys.exit(1)
    extra = ["todos"] if len(a) > 1 and a[1].lower() == "todos" else []
    sys.exit(run_mod("importar/resultados_todas.py", liga, *extra))
