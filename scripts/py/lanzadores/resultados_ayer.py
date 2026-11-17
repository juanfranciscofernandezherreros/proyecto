# -*- coding: utf-8 -*-
r"""Lanzador: resultados de ayer de todas las ligas en un solo fichero.

Uso: resultados_ayer.py [AAAA-MM-DD]   (por defecto, ayer en Europe/Madrid)

No extrae nada: usa los RESULTS ya extraidos. Del ultimo RESULTS_*.csv de cada liga
toma los partidos de ese dia y los escribe en
   REPORTS_DIR\resultados-ayer\RESULTS_YESTERDAY_<AAAAMMDD>.csv
   (columnas del RESULTS con country y competition delante).

El fichero va fuera de competitions\ para que la importacion de RESULTS no lo recoja.
"""
import csv
import sys
from datetime import datetime
from pathlib import Path

from _base import CFG
import cuadrar_dia as C

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ligas import catalogo


def filas_de_liga(filas, dia, country, competition):
    """Filas (dict) de un RESULTS cuyo eventDatetime cae en `dia` (Madrid), con la liga delante."""
    out = []
    for f in filas:
        texto = (f.get("eventDatetime") or "").strip()
        try:
            dt = datetime.fromisoformat(texto)
        except ValueError:
            continue
        if (dt.astimezone(C.MADRID) if dt.tzinfo else dt).date() == dia:
            out.append({"country": country, "competition": competition, **f})
    return out


def nombre_fichero(dia):
    return f"RESULTS_YESTERDAY_{dia:%Y%m%d}.csv"


def main(argv):
    if len(argv) > 1:
        print("Uso: basket resultados-ayer [AAAA-MM-DD]")
        return 1
    try:
        dia = C.validar_fecha(argv[0] if argv else None)
    except ValueError as e:
        print(f"ERROR: {e}")
        return 1

    filas, cabecera, resumen = [], ["country", "competition"], []
    for liga in catalogo.cargar_ligas():
        fichero = C.ultimo_results(liga)
        if fichero is None:
            resumen.append((liga["code"], 0, "sin RESULTS_*.csv"))
            continue
        with open(fichero, encoding="utf-8-sig", newline="") as fh:
            lector = csv.DictReader(fh)
            for col in lector.fieldnames or []:
                if col not in cabecera:
                    cabecera.append(col)
            de_liga = filas_de_liga(lector, dia, liga["country"], liga["competition"])
        filas.extend(de_liga)
        resumen.append((liga["code"], len(de_liga), fichero.name))

    salida = Path(CFG.get("REPORTS_DIR")) / "resultados-ayer" / nombre_fichero(dia)
    salida.parent.mkdir(parents=True, exist_ok=True)
    with open(salida, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cabecera, extrasaction="ignore")
        w.writeheader()
        w.writerows(filas)

    print(f"== RESULTADOS DEL {dia.isoformat()} ==")
    for code, n, origen in resumen:
        print(f"  {code:<9} {n:>3}  ({origen})")
    print(f"Total: {len(filas)} partidos -> {salida}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
