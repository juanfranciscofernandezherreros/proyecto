# -*- coding: utf-8 -*-
r"""Estado del sistema, resumido y ordenado por lo que falla (equivale a la antigua skill
estado-del-sistema, pero sin gastar tokens).

Ejecuta ESTADO.bat (solo lectura), lo parsea y escribe un resumen corto
empezando por lo que no funciona, indicando que script lo arregla.

Uso:  python scripts\py\estado.py
Codigo de salida: 0 = todo responde, 1 = falta algo (el mismo de ESTADO.bat).
"""
import sys
from estado_lib import leer_estado


def clasificar(resumen):
    """Agrupa las lineas del RESUMEN y les asigna el script que lo resuelve."""
    arranque, sin_resultado, otros = [], [], []
    for item in resumen:
        bajo = item.lower()
        if "contenedor" in bajo or "servicio" in bajo:
            arranque.append(item)
        elif "sin resultado" in bajo:
            sin_resultado.append(item)
        else:
            otros.append(item)
    return arranque, sin_resultado, otros


def main():
    d = leer_estado()
    print()
    if not d["resumen"] and d["codigo"] == 0:
        print("TODO OK: web, API, Postgres, Mongo y datos al dia.")
        return 0

    arranque, sin_resultado, otros = clasificar(d["resumen"])

    print("LO QUE FALLA (empezando por lo mas importante):\n")
    if arranque:
        print("  [arrancar-web] servicios caidos:")
        for x in arranque:
            print(f"     - {x}")
    if sin_resultado:
        print("\n  [resultados-todas-las-ligas / extraer-resultados] partidos sin marcador:")
        for x in sin_resultado:
            print(f"     - {x}")
    if otros:
        print("\n  Otros:")
        for x in otros:
            print(f"     - {x}")

    pend = d["pendientes"].get("pendientes")
    if pend:
        print(f"\n  [procesar-pendientes] {pend} partidos con algun dataset por extraer.")

    print(f"\n(codigo de salida {d['codigo']})")
    return d["codigo"] if d["codigo"] is not None else 1


if __name__ == "__main__":
    sys.exit(main())
