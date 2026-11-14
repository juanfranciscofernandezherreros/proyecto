# -*- coding: utf-8 -*-
r"""Selecciona la ultima jornada de un CSV de RESULTS (equivale a
Get-LatestMatchdayRows de EJECUTAR_LIGA_BASKET.ps1).

Agrupa por fecha de evento, de la mas reciente hacia atras, y va acumulando dias
hasta que un dia repite un equipo ya visto: ahi corta. Asi se queda con la jornada
mas reciente sin mezclar partidos de un mismo equipo de jornadas distintas.
"""
from datetime import datetime
from itertools import groupby


def ultima_jornada(filas):
    datadas = []
    for r in filas:
        ev = r.get("eventDatetime")
        if ev and ev.strip():
            d = datetime.fromisoformat(ev).date()
            datadas.append((d, r))
    if not datadas:
        raise ValueError("El CSV no contiene resultados con fecha.")

    # Agrupar por fecha, de la mas reciente a la mas antigua.
    datadas.sort(key=lambda t: t[0], reverse=True)
    seleccion = []
    equipos = set()
    for _dia, grupo in groupby(datadas, key=lambda t: t[0]):
        day_rows = [r for _d, r in grupo]
        repite = any((r.get("homeTeam", "").lower() in equipos
                      or r.get("awayTeam", "").lower() in equipos) for r in day_rows)
        if seleccion and repite:
            break
        for r in day_rows:
            seleccion.append(r)
            equipos.add(r.get("homeTeam", "").lower())
            equipos.add(r.get("awayTeam", "").lower())
    return seleccion
