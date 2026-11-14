# -*- coding: utf-8 -*-
r"""Procesar los CSV de RESULTADOS ya en disco (equivale a la skill
procesar-csv-resultados, sin gastar tokens).

NO abre el navegador ni toca Flashscore: solo carga en Postgres los RESULTS que
ya estan en C:\\data\\basketball\\competitions\\...  La carga es idempotente.

Secuencia fija:
  1. ESTADO.bat (antes)
  2. PROCESAR_CSV_RESULTADOS.bat [LIGA] [todos]   (~30 s por liga)
  3. ESTADO.bat (despues)
  4. Tabla liga a liga: partidos nuevos en Postgres + bloque RESUMEN del importador.

Uso:
  python scripts\py\procesar_csv_resultados.py                 (mas reciente de cada liga)
  python scripts\py\procesar_csv_resultados.py EUROLIGA        (solo esa liga)
  python scripts\py\procesar_csv_resultados.py ALL todos       (todo el historico)
"""
import sys
from estado_lib import (
    leer_estado, imprimir_tabla_ligas, _run_capturando, EJECUTAR,
)

PROCESAR_BAT = EJECUTAR / "PROCESAR_CSV_RESULTADOS.bat"


def extraer_bloque_resumen(texto):
    """Devuelve las lineas del ultimo bloque 'RESUMEN' de la salida del importador."""
    lineas = texto.splitlines()
    idx = None
    for i, l in enumerate(lineas):
        if "RESUMEN" in l.upper():
            idx = i
    if idx is None:
        return []
    return [l for l in lineas[idx:] if l.strip()]


def main():
    args = sys.argv[1:]
    liga = args[0] if args else "ALL"
    todos = len(args) > 1 and args[1].lower() == "todos"

    print("== 1/3 Estado antes ==")
    antes = leer_estado()
    if antes["contenedores"].get("postgres") != "OK":
        print("ERROR: Postgres no responde. Arranca el stack antes (skill arrancar-web).")
        return 1

    cmd = ["cmd", "/c", str(PROCESAR_BAT), liga]
    if todos:
        cmd.append("todos")
    etiqueta = f"{liga}" + (" (historico completo)" if todos else " (mas reciente)")
    print(f"\n== 2/3 Procesando CSV de RESULTS: {etiqueta} ==")
    codigo, salida = _run_capturando(cmd, eco=True)

    print("\n== 3/3 Estado despues ==")
    despues = leer_estado()

    imprimir_tabla_ligas(antes, despues)

    bloque = extraer_bloque_resumen(salida)
    if bloque:
        print("\n  RESUMEN del importador:")
        for l in bloque:
            print(f"   {l}")

    print(f"\n(PROCESAR_CSV_RESULTADOS devolvio codigo {codigo})")
    return codigo


if __name__ == "__main__":
    sys.exit(main())
