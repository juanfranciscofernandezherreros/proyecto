# -*- coding: utf-8 -*-
r"""Procesa los CSV de RESULTS ya en disco y los carga en PostgreSQL, sin extraer de
Flashscore (equivale a scripts\importar\IMPORTAR_RESULTADOS_TODAS.ps1, sin PowerShell).

Por defecto solo el CSV mas reciente de cada liga (contiene a los anteriores); con
'todos' importa todos. Un fallo en una liga no detiene las demas.

Uso:  python scripts\py\importar\resultados_todas.py [LIGA|ALL] [todos]
Codigo de salida: 0 si no hubo fallos, 1 si alguno fallo.
"""
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config
import launcher as L
import resultados


def _ligas(cfg):
    datos = json.loads(Path(cfg["LEAGUE_CATALOG"]).read_text(encoding="utf-8"))
    return datos if isinstance(datos, list) else [datos]


def main():
    args = sys.argv[1:]
    league = args[0] if args else "ALL"
    todos = len(args) > 1 and args[1].lower() == "todos"
    cfg = _config.cargar()

    todas = league.strip().upper() == "ALL"
    seleccion = [lg for lg in _ligas(cfg)
                 if todas or str(lg.get("code", "")).strip() == league.strip()]
    if not seleccion:
        print(f"[ERROR] Liga no encontrada: {league}")
        return 1

    resumen = []
    for lg in seleccion:
        code, country, comp = lg.get("code"), lg.get("country"), lg.get("competition")
        carpeta = Path(cfg["COMPETITIONS_DIR"]) / country / comp
        ficheros = []
        if carpeta.is_dir():
            ficheros = sorted(
                p for p in carpeta.glob(f"RESULTS_*_{country}_{comp}.csv")
                if re.match(r"^RESULTS_\d{14}_", p.name))
        if not ficheros:
            print(f"[OMITIDO] [{code}] no hay CSV de RESULTS en {carpeta}")
            resumen.append({"Liga": code, "Fichero": "-", "Filas": 0, "Estado": "OMITIDO", "Detalle": "sin CSV"})
            continue
        if not todos:
            ficheros = [ficheros[-1]]
        for f in ficheros:
            print(f"PROCESAR [{code}] {f.name}")
            filas = 0
            try:
                filas = len(resultados._leer_filas(f))
                resultados.importar(str(f), country, comp)
                resumen.append({"Liga": code, "Fichero": f.name, "Filas": filas, "Estado": "OK", "Detalle": ""})
            except Exception as e:
                print(f"[FALLO] [{code}] {e}")
                resumen.append({"Liga": code, "Fichero": f.name, "Filas": filas, "Estado": "FALLO", "Detalle": str(e)})

    print("")
    print("==================== RESUMEN ====================")
    print(L.tabla(resumen, ["Liga", "Fichero", "Filas", "Estado"]))
    fallos = [r for r in resumen if r["Estado"] == "FALLO"]
    ok = sum(1 for r in resumen if r["Estado"] == "OK")
    omitidos = sum(1 for r in resumen if r["Estado"] == "OMITIDO")
    print(f"CSV procesados: {ok} OK, {len(fallos)} con fallo, {omitidos} ligas sin CSV.")
    if not fallos:
        return 0
    print("Fallos:")
    for r in fallos:
        print(f"  [{r['Liga']}] {r['Fichero']}: {r['Detalle']}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
