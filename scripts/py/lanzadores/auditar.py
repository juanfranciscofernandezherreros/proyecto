# -*- coding: utf-8 -*-
r"""Lanzador: auditoria de integridad de datos en Postgres (solo lectura).
Ejecuta sql\consultas\2026-11-15_1445_auditoria-datos.sql y muestra el resultado.
Codigo de salida: 0 si la consulta se ejecuto (aunque haya controles con afectados),
1 si no se pudo ejecutar.  Uso: auditar.py"""
import sys
from _base import ensure, psql, WORKSPACE

SQL = WORKSPACE / "sql" / "consultas" / "2026-11-15_1445_auditoria-datos.sql"

if __name__ == "__main__":
    if not SQL.exists():
        print(f"[ERROR] No se encuentra la consulta de auditoria: {SQL}")
        sys.exit(1)
    if ensure("postgres"):
        sys.exit(1)
    sys.stdout.flush()
    rc = psql(["-v", "ON_ERROR_STOP=1"], sql_input=SQL.read_bytes())
    if rc != 0:
        print("[ERROR] La auditoria de datos no se pudo ejecutar.")
        sys.exit(1)
    print("Auditoria terminada. Como leerla: skill auditar-datos (afectados = 0 es lo bueno).")
    sys.exit(0)
