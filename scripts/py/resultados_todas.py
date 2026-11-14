# -*- coding: utf-8 -*-
r"""Resultados de todas las ligas (equivale a la skill resultados-todas-las-ligas,
sin gastar tokens).

Secuencia fija, sin decisiones:
  1. ESTADO.bat (antes)
  2. EXTRAER_RESULTADOS.bat ALL   -> marcadores + parciales de las 11 ligas (~15 min)
  3. ESTADO.bat (despues)
  4. Tabla liga a liga: partidos nuevos, ligas que siguen sin resultado y ligas
     que fallaron (del CSV de resumen del orquestador).

Uso:  python scripts\py\resultados_todas.py
Solo marcadores: NO lanza jugada a jugada, estadisticas ni pendientes.
"""
import sys
import csv
import time
from datetime import datetime
from estado_lib import (
    leer_estado, parsear_estado, imprimir_tabla_ligas,
    _run_capturando, EJECUTAR, report_dir,
)

EXTRAER_BAT = EJECUTAR / "EXTRAER_RESULTADOS.bat"


def resumen_orquestador(desde_ts):
    """Lee el CSV ligas-orquestar-resumen-*.csv creado durante esta ejecucion y
    devuelve (ok, fallos) donde fallos es lista de (liga, paso, detalle)."""
    rd = report_dir()
    candidatos = [
        p for p in rd.glob("ligas-orquestar-resumen-*.csv")
        if p.stat().st_mtime >= desde_ts
    ]
    if not candidatos:
        return None, []
    ultimo = max(candidatos, key=lambda p: p.stat().st_mtime)
    ok, fallos = 0, []
    with open(ultimo, encoding="utf-8-sig", newline="") as fh:
        for fila in csv.DictReader(fh):
            estado = (fila.get("Estado") or "").upper()
            if estado == "OK":
                ok += 1
            else:
                fallos.append((
                    fila.get("Liga", "?"), fila.get("Paso", "?"),
                    fila.get("Detalle", ""),
                ))
    return ok, fallos


def main():
    liga = sys.argv[1] if len(sys.argv) > 1 else "ALL"
    inicio = time.time()

    print("== 1/3 Estado antes ==")
    antes = leer_estado()
    if antes["contenedores"].get("postgres") != "OK":
        print("ERROR: Postgres no responde. Arranca el stack antes (skill arrancar-web).")
        return 1

    print(f"\n== 2/3 Extrayendo RESULTS de {liga} (puede tardar ~15 min) ==")
    codigo, _ = _run_capturando(
        ["cmd", "/c", str(EXTRAER_BAT), liga], eco=True,
    )

    print("\n== 3/3 Estado despues ==")
    despues = leer_estado()

    imprimir_tabla_ligas(antes, despues)

    ok, fallos = resumen_orquestador(inicio)
    if ok is not None:
        print(f"\n  Pasos OK en el orquestador: {ok}")
    if fallos:
        print("\n  LIGAS CON FALLO (repetir con: EXTRAER_RESULTADOS.bat <LIGA>):")
        for lg, paso, det in fallos:
            print(f"     - {lg} [{paso}] {det}")

    print(f"\n(EXTRAER_RESULTADOS devolvio codigo {codigo})")
    return codigo


if __name__ == "__main__":
    sys.exit(main())
