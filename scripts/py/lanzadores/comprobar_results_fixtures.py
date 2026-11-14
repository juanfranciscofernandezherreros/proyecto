# -*- coding: utf-8 -*-
r"""Lanzador: comprobar que RESULTS y FIXTURES estan listos (COMPROBAR_RESULTS_FIXTURES.bat).
Solo lectura; requiere Postgres arrancado."""
import sys
from _base import psql, WORKSPACE

SQL = WORKSPACE / "sql" / "consultas" / "2026-11-03_1710_results-y-fixtures-listos-para-pendientes.sql"

if __name__ == "__main__":
    rc = psql([], sql_input=SQL.read_bytes(), compose=True)
    if rc:
        print("Error: no se pudo hacer la comprobacion.")
    sys.exit(1 if rc else 0)
