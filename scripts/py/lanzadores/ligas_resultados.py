# -*- coding: utf-8 -*-
r"""Lanzador: ejecutar ligas (LIGAS_RESULTADOS.bat). Con argumentos, todas las ligas;
sin argumentos, menu."""
import sys
from _base import ensure, run_mod


def main():
    a = sys.argv[1:]
    if not a:
        print("\n" + "=" * 60)
        print(" RESULTADOS DE BALONCESTO")
        print("=" * 60)
        print(" [1] Ejecutar todas las ligas del JSON")
        print(" [2] Elegir una liga concreta")
        op = input("Selecciona una opcion: ").strip()
        if ensure("antibloqueo", "postgres", "launcher", "navegador"):
            print("\nERROR: No se pudieron iniciar los requisitos de ejecucion.")
            return 1
        if op == "2":
            print("\nLigas disponibles:")
            return run_mod("ligas/ejecutar_liga.py")
        return run_mod("ligas/ejecutar_todas.py")
    if ensure("antibloqueo", "postgres", "launcher", "navegador"):
        print("\nERROR: No se pudieron iniciar los requisitos de ejecucion.")
        return 1
    print("[INFO] Lanzando el proceso para todas las ligas...")
    rc = run_mod("ligas/ejecutar_todas.py", *a)
    print("\n[OK] Proceso finalizado." if rc == 0 else "\n[ERROR] El proceso termino con errores.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
