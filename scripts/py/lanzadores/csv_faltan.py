# -*- coding: utf-8 -*-
r"""Lanzador: CSV que faltan por generar y por que (basket csv-faltan [match_id])."""
import sys
from _base import ensure, run_mod

if __name__ == "__main__":
    if ensure("postgres", "auditoria"):
        sys.exit(1)
    sys.exit(run_mod("pendientes/csv_faltan.py", *sys.argv[1:]))
