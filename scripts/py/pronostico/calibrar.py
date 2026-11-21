# -*- coding: utf-8 -*-
r"""Calibracion del modelo de pronosticos con los partidos ya jugados (walk-forward).

Uso:  python scripts\py\pronostico\calibrar.py

Para cada partido usa solo los datos anteriores (como `previa.contrastar`) y compara, sobre Euroliga,
Liga Endesa y NBA (solo liga regular), el modelo con distintas localias, escalas y pesos:
  - Brier y log-loss de las probabilidades (menos es mejor), aciertos y error medio del margen.
  - La tabla de fiabilidad: probabilidad media del favorito frente a lo que acierta de verdad.
  - La ventaja de campo real de cada liga (margen medio del local).
Solo lee Postgres (sql\consultas\2026-11-15_2330_previa-jornada-datos.sql y la de partidos).
La calibracion del 2026-11-21 esta en docs\REVISION-PRONOSTICO-EUROLIGA-J12.md."""
import math
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
sys.path.insert(0, str(RAIZ / "scripts" / "py" / "pronostico"))
from _base import CFG  # noqa: E402
import previa  # noqa: E402

LIGAS = [("europe", "euroleague"), ("spain", "liga-endesa"), ("usa", "nba")]
INICIO_NBA = "2026-10-19T22:00:00Z"  # liga regular 2026-27 (la base de datos trae tambien la pretemporada)


def cargar():
    partidos = {}
    for pais, competicion in LIGAS:
        jugados = [p for p in previa.leer_partidos(CFG, pais, competicion) if p.get("home_score") is not None]
        if competicion == "nba":
            jugados = [p for p in jugados if p["inicio"] >= INICIO_NBA]
        partidos[competicion] = previa._ordenados(jugados)
    return partidos


def filas(partidos, localia, escala, peso=0.65):
    """(margen, probabilidad local 0-1, gana local 0/1, margen real) de cada partido evaluable."""
    previa.LOCALIA, previa.ESCALA = localia, escala
    previa.PESO_TEMPORADA, previa.PESO_RECIENTE = peso, 1 - peso
    historial, salida = {}, []
    for p in partidos:
        local, visitante = p["home_team"], p["away_team"]
        real = p["home_score"] - p["away_score"]
        pl, pv = historial.get(local, []), historial.get(visitante, [])
        if len(pl) >= previa.MIN_PREVIOS and len(pv) >= previa.MIN_PREVIOS:
            margen = previa.margen_local(
                {"dif_temp": sum(pl) / len(pl), "dif_ult5": sum(pl[-5:]) / len(pl[-5:])},
                {"dif_temp": sum(pv) / len(pv), "dif_ult5": sum(pv[-5:]) / len(pv[-5:])})
            salida.append((margen, previa.probabilidad_local(margen) / 100, 1 if real > 0 else 0, real))
        historial.setdefault(local, []).append(real)
        historial.setdefault(visitante, []).append(-real)
    return salida


def metricas(f):
    n = len(f)
    return {"n": n,
            "aciertos": sum((x[0] >= 0) == (x[3] > 0) for x in f),
            "brier": sum((x[1] - x[2]) ** 2 for x in f) / n,
            "logloss": sum(-math.log(max(1e-9, x[1] if x[2] else 1 - x[1])) for x in f) / n,
            "mae": sum(abs(x[0] - x[3]) for x in f) / n}


def juntas(partidos, localia, escala, peso=0.65):
    return [x for ps in partidos.values() for x in filas(ps, localia, escala, peso)]


def main():
    partidos = cargar()
    print("Ventaja de campo real (liga regular):")
    for c, ps in partidos.items():
        m = sum(p["home_score"] - p["away_score"] for p in ps) / len(ps)
        g = sum(p["home_score"] > p["away_score"] for p in ps) / len(ps)
        print(f"  {c:12s} {len(ps):3d} partidos  margen local {m:+.2f}  gana local {100 * g:.1f} %")
    print("\nLocalia (escala 14, pesos 65/35):")
    for loc in (2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0):
        r = metricas(juntas(partidos, loc, 14.0))
        print(f"  {loc:3.1f}: aciertos {r['aciertos']}/{r['n']} Brier {r['brier']:.4f} LL {r['logloss']:.4f} MAE {r['mae']:.2f}")
    print("\nEscala (localia 2,5):")
    for esc in (7, 9, 11, 13, 14, 15, 18):
        r = metricas(juntas(partidos, 2.5, float(esc)))
        print(f"  {esc:2d}: Brier {r['brier']:.4f} LL {r['logloss']:.4f}")
    print("\nFiabilidad con la escala actual:")
    f = juntas(partidos, 2.5, 14.0)
    for lo, hi in ((50, 55), (55, 60), (60, 65), (65, 70), (70, 101)):
        g = [x for x in f if lo <= 100 * max(x[1], 1 - x[1]) < hi]
        if g:
            prevista = sum(max(x[1], 1 - x[1]) for x in g) / len(g)
            real = sum((x[0] >= 0) == (x[3] > 0) for x in g) / len(g)
            print(f"  favorito {lo}-{hi if hi < 101 else 100} %: n={len(g):3d}  prevista {100 * prevista:.1f} %  acierto {100 * real:.1f} %")


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    main()
