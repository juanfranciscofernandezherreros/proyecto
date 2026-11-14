# -*- coding: utf-8 -*-
r"""Match IDs que ya tienen filas de un dataset en PostgreSQL (equivale a
scripts\extraer\PARTIDOS_YA_IMPORTADOS.ps1, sin PowerShell). Los extractores los
saltan para no reabrir Flashscore ni regenerar un CSV ya importado.

Uso:  python scripts\py\extraer\ya_importados.py <MATCH_SUMMARY|TEAM_STATS|PLAYER_STATS|POINT_BY_POINT> [--salida fichero]
"""
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config

TABLES = {
    "MATCH_SUMMARY": "match_summary.match_summary",
    "TEAM_STATS": "team_stats.team_stats",
    "PLAYER_STATS": "stats_player.stats_player",
    "POINT_BY_POINT": "point_by_point.point_by_point_event",
}


def ya_importados(dataset):
    cfg = _config.cargar()
    if dataset not in TABLES:
        raise ValueError(f"Dataset no valido: {dataset}")
    compose = str(Path(cfg["WORKSPACE"]) / "local-validation" / "docker-compose.yml")
    p = subprocess.run(
        ["docker", "compose", "-f", compose, "exec", "-T", "postgres",
         "psql", "-U", cfg.get("DB_USER"), "-d", cfg.get("DB_NAME"), "--no-psqlrc", "-At",
         "-c", f"SELECT DISTINCT match_id FROM {TABLES[dataset]} WHERE match_id IS NOT NULL"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if p.returncode != 0:
        raise RuntimeError(f"No se pudieron leer los partidos ya importados de {dataset}.")
    return [l.strip() for l in p.stdout.splitlines() if l.strip()]


def main():
    args = sys.argv[1:]
    if not args:
        print("ERROR: indica el dataset.")
        return 1
    dataset = args[0]
    salida = None
    if "--salida" in args:
        salida = args[args.index("--salida") + 1]
    ids = ya_importados(dataset)
    if salida:
        Path(salida).write_text("\n".join(ids) + ("\n" if ids else ""), encoding="ascii")
    else:
        for i in ids:
            print(i)
    return 0


if __name__ == "__main__":
    sys.exit(main())
