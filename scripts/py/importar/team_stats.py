# -*- coding: utf-8 -*-
r"""Importa los TEAM_STATS (STATS_ALL_PERIODS) de la ultima RESULTS en PostgreSQL
(equivale a PROCESAR_TEAM_STATS_EUROLIGA_A_POSTGRESQL.ps1 + IMPORTAR_TEAM_STATS.bat).

Uso:  python scripts\py\importar\team_stats.py [pais] [competicion]   (def. europe/euroleague)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import stats_common as S
from stats_common import _mas_reciente


def _buscar(competition_root, match_ids):
    entries, missing = [], []
    for mid in match_ids:
        candidatos = list(competition_root.glob(f"STATS_ALL_PERIODS_*{mid}.csv"))
        candidatos += list((competition_root / mid).glob("STATS_ALL_PERIODS_*.csv"))
        f = _mas_reciente(candidatos)
        if f:
            entries.append((f, mid))
        else:
            missing.append(mid)
    if missing:
        print(f"AVISO: Aun no hay TEAM_STATS para: {', '.join(missing)}")
    return entries


def team_stats(country="europe", competition="euroleague"):
    S.procesar(country, competition, "TEAM_STATS", "team-stats-import",
               "Partidos detectados: {n}. TEAM_STATS a procesar: {m}.", _buscar)


def main():
    code = S.cli(team_stats)
    print("[OK] TEAM_STATS importado en PostgreSQL." if code == 0 else "[ERROR] Importacion TEAM_STATS fallida.")
    return code


if __name__ == "__main__":
    sys.exit(main())
