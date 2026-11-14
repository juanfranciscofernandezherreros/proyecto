# -*- coding: utf-8 -*-
r"""Importa los POINT_BY_POINT de la ultima RESULTS en PostgreSQL (equivale a
PROCESAR_POINT_BY_POINT_EUROLIGA_A_POSTGRESQL.ps1 + IMPORTAR_POINT_BY_POINT.bat).

Uso:  python scripts\py\importar\point_by_point.py [pais] [competicion]   (def. europe/euroleague)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import stats_common as S
from stats_common import _mas_reciente


def _buscar(competition_root, match_ids):
    entries, missing = [], []
    for mid in match_ids:
        f = _mas_reciente(competition_root.glob(f"POINT_BY_POINT_*{mid}.csv"))
        if f:
            entries.append((f, mid))
        else:
            missing.append(mid)
    if missing:
        print(f"AVISO: Aun no hay POINT_BY_POINT para: {', '.join(missing)}")
    return entries


def point_by_point(country="europe", competition="euroleague"):
    S.procesar(country, competition, "POINT_BY_POINT", "point-by-point-import",
               "Partidos detectados: {n}. CSV POINT_BY_POINT a procesar: {m}.", _buscar)


def main():
    code = S.cli(point_by_point)
    print("[OK] POINT_BY_POINT importado en PostgreSQL." if code == 0 else "[ERROR] Importacion POINT_BY_POINT fallida.")
    return code


if __name__ == "__main__":
    sys.exit(main())
