# -*- coding: utf-8 -*-
r"""Muestra, por competicion, los partidos del calendario (fixtures) ya jugados que
aun no tienen resultado (equivale a scripts\pendientes\FIXTURES_SIN_RESULTS.bat, sin
PowerShell). Solo lectura; requiere Postgres arrancado.

Uso:  python scripts\py\pendientes\fixtures_sin_results.py
"""
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config

SQL = Path(__file__).resolve().parents[3] / "sql" / "consultas" / "2026-11-03_1300_fixtures-jugados-sin-results.sql"


def main():
    cfg = _config.cargar()
    p = subprocess.run(
        ["docker", "compose", "-f", cfg.get("COMPOSE_FILE"), "exec", "-T", "postgres",
         "psql", "-U", cfg.get("DB_USER"), "-d", cfg.get("DB_NAME")],
        input=SQL.read_text(encoding="utf-8"), text=True, encoding="utf-8", errors="replace",
    )
    if p.returncode != 0:
        print("Error: no se pudieron consultar los partidos sin resultado.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
