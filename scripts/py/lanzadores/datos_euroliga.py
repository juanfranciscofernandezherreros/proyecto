# -*- coding: utf-8 -*-
r"""Lanzador: flujo de datos Euroliga con menu (DATOS_EUROLIGA.bat).
Uso: datos_euroliga.py [pais] [competicion] [limite]"""
import sys
from _base import ensure, run_mod, SCRIPTS_PY
sys.path.insert(0, str(SCRIPTS_PY))
import proc

_ok = {"started": False}


def preflight():
    if _ok["started"]:
        return 0
    if ensure("antibloqueo", "watcher", "postgres", "launcher", "navegador"):
        return 1
    _ok["started"] = True
    return 0


def paso(extract, impo, country, competition, limit):
    if preflight():
        return 1
    if run_mod(*extract, country, competition, limit):
        return 1
    return run_mod(*impo, country, competition)


def main():
    a = sys.argv[1:]
    country = a[0] if len(a) > 0 else "europe"
    competition = a[1] if len(a) > 1 else "euroleague"
    try:
        limit = str(proc.validar_limite(a[2] if len(a) > 2 else "10", 10))
    except ValueError as e:
        print(f"[ERROR] {e}")
        return 1
    print(f"\n{'='*60}\n FLUJO EUROLIGA: {country} / {competition}  ({limit} partidos)\n{'='*60}")
    print(" [1] POINT_BY_POINT: extraer e importar")
    print(" [2] TEAM_STATS: extraer e importar")
    print(" [3] PLAYER_STATS: extraer e importar")
    print(" [4] Todo: PBP + equipo + jugadores")
    print(" [0] Salir")
    op = input("Selecciona una opcion: ").strip()
    pbp = (["extraer/point_by_point.py"], ["importar/point_by_point.py"])
    team = (["extraer/dataset.py", "stats_all_periods.csv"], ["importar/team_stats.py"])
    play = (["extraer/dataset.py", "player_stats.csv"], ["importar/player_stats.py"])
    if op == "0":
        return 0
    if op == "1":
        return paso(*pbp, country, competition, limit)
    if op == "2":
        return paso(*team, country, competition, limit)
    if op == "3":
        return paso(*play, country, competition, limit)
    if op == "4":
        for pares in (pbp, team, play):
            if paso(*pares, country, competition, limit):
                return 1
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
