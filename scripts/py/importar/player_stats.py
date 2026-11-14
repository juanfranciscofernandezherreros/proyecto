# -*- coding: utf-8 -*-
r"""Importa los PLAYER_STATS de la ultima RESULTS en PostgreSQL (equivale a
PROCESAR_PLAYER_STATS_EUROLIGA_A_POSTGRESQL.ps1 + IMPORTAR_PLAYER_STATS.bat).

Uso:  python scripts\py\importar\player_stats.py [pais] [competicion]   (def. europe/euroleague)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import stats_common as S
from stats_common import _mas_reciente


def _primera_fila_datos(path):
    """Primera linea de datos (tras la cabecera); '' si no hay."""
    with open(path, encoding="utf-8-sig") as fh:
        it = iter(fh)
        next(it, None)  # cabecera
        return (next(it, "") or "").strip()


def _buscar(competition_root, match_ids):
    entries, missing, empty = [], [], []
    for mid in match_ids:
        f = _mas_reciente((competition_root / mid).glob("PLAYER_STATS_*.csv"))
        if f:
            if _primera_fila_datos(f):
                entries.append((f, mid))
            else:
                empty.append(mid)
        else:
            missing.append(mid)
    if missing:
        print(f"AVISO: Aun no hay PLAYER_STATS para: {', '.join(missing)}")
    if empty:
        print(f"AVISO: PLAYER_STATS vacios publicados por Flashscore (se omiten): {', '.join(empty)}")
    return entries


def player_stats(country="europe", competition="euroleague"):
    S.procesar(country, competition, "PLAYER_STATS", "player-stats-import",
               "Partidos detectados: {n}. CSV PLAYER_STATS a procesar: {m}.", _buscar)


def main():
    code = S.cli(player_stats)
    print("[OK] PLAYER_STATS importado en PostgreSQL." if code == 0 else "[ERROR] Importacion PLAYER_STATS fallida.")
    return code


if __name__ == "__main__":
    sys.exit(main())
