# -*- coding: utf-8 -*-
r"""Monitor en vivo de las importaciones reales del CSV batch launcher (equivale a
scripts\monitor\watch_csv_processing.ps1 + watch_csv_imports.bat, sin PowerShell).

Refresca cada 2 s consultando public.batch_launch_request. Ctrl+C para cerrar.

Uso:  python scripts\py\monitor\watch_csv.py [--una-vez]
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

SCRIPTS_PY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_PY))
import config as _config
sys.path.insert(0, str(SCRIPTS_PY / "arranque"))
import asegurar

CFG = _config.cargar()
SQL = """
WITH active AS (
    SELECT request_id, batch_type, status, file_path, created_at, started_at, finished_at, error
    FROM public.batch_launch_request
    WHERE status IN ('QUEUED', 'RUNNING', 'BLOCKED')
), recent AS (
    SELECT request_id, batch_type, status, file_path, created_at, started_at, finished_at, error
    FROM public.batch_launch_request
    WHERE status IN ('COMPLETED', 'FAILED')
    ORDER BY finished_at DESC NULLS LAST
    LIMIT 15
), selected AS (
    SELECT *, 0 AS order_rank FROM active
    UNION ALL
    SELECT *, 1 AS order_rank FROM recent
)
SELECT COALESCE(json_agg(to_jsonb(selected) ORDER BY order_rank, created_at DESC), '[]'::json)::text
FROM selected;
"""
COLS = ["status", "batch_type", "csv", "solicitado", "inicio", "fin", "detalle"]


def _items():
    p = subprocess.run(
        ["docker", "exec", CFG.get("POSTGRES_CONTAINER"), "psql", "-U", CFG.get("DB_USER"),
         "-d", CFG.get("DB_NAME"), "-X", "-A", "-t", "-c", SQL],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise RuntimeError("No se pudo consultar batch_launch_request en PostgreSQL.")
    return json.loads(p.stdout.strip() or "[]")


def _fila(it):
    return {"status": it.get("status"), "batch_type": it.get("batch_type"),
            "csv": os.path.basename(it.get("file_path") or ""),
            "solicitado": it.get("created_at"), "inicio": it.get("started_at"),
            "fin": it.get("finished_at"), "detalle": it.get("error")}


def _render():
    try:
        items = _items()
        os.system("cls")
        print("IMPORTACIONES REALES DEL CSV BATCH LAUNCHER")
        en_cola = sum(1 for i in items if i.get("status") == "QUEUED")
        ejec = sum(1 for i in items if i.get("status") == "RUNNING")
        bloq = sum(1 for i in items if i.get("status") == "BLOCKED")
        print(f"Actualizado: {datetime.now():%H:%M:%S} | En cola: {en_cola} | Ejecutandose: {ejec} | Bloqueados: {bloq}")
        print("Se muestran solicitudes del launcher, no CSV meramente generados. Refresco cada 2 s. Ctrl+C para cerrar.")
        if not items:
            print("No hay importaciones en cola, en ejecucion o recientes.")
        else:
            filas = [_fila(i) for i in items]
            anchos = {c: max(len(c), *(len(str(f.get(c, "") or "")) for f in filas)) for c in COLS}
            print("  ".join(c.ljust(anchos[c]) for c in COLS))
            print("  ".join("-" * anchos[c] for c in COLS))
            for f in filas:
                print("  ".join(str(f.get(c, "") or "").ljust(anchos[c]) for c in COLS))
    except Exception as e:
        os.system("cls")
        print("IMPORTACIONES REALES DEL CSV BATCH LAUNCHER")
        print(str(e))


def main():
    una_vez = "--una-vez" in sys.argv
    if not una_vez:
        asegurar.main(["postgres"])
    while True:
        _render()
        if una_vez:
            return 0
        time.sleep(2)


if __name__ == "__main__":
    sys.exit(main())
