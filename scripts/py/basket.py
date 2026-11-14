# -*- coding: utf-8 -*-
r"""basket - CLI unico del proyecto Basketball (sustituye los 20 .bat de 1_EJECUTAR).

Cada subcomando ejecuta su lanzador de scripts\py\lanzadores\. Sin subcomando
(o doble clic en basket.cmd) muestra un menu.

Uso:  python scripts\py\basket.py <comando> [args]
      basket.cmd <comando> [args]          (shim de Windows)
Ejemplos:  basket estado | basket resultados EUROLIGA | basket ciclo-diario
"""
import subprocess
import sys
from pathlib import Path

LANZADORES = Path(__file__).resolve().parent / "lanzadores"

# comando coherente -> (modulo lanzador, descripcion)
COMANDOS = {
    "estado":            ("estado",                    "Estado del sistema (solo lectura)"),
    "arrancar":          ("arrancar_todo",             "Arrancar web, API, projector y launcher"),
    "verificar":         ("verificar",                 "Verificacion del SDD (verde/rojo)"),
    "antibloqueo":       ("antibloqueo",               "Mantener el PC despierto"),
    "resultados":        ("extraer_resultados",        "Extraer RESULTS [LIGA] [limite]"),
    "procesar-csv":      ("procesar_csv_resultados",   "Cargar en Postgres los RESULTS ya en disco [LIGA] [todos]"),
    "orquestar":         ("ligas_orquestar",           "Orquestar ligas [LIGA] [results|datos|todo] [limite]"),
    "ligas":             ("ligas_resultados",          "Ejecutar ligas (menu o todas)"),
    "datos":             ("datos_euroliga",            "Flujo de datos por dataset [pais] [competicion] [limite]"),
    "extraer-todo":      ("extraer_csv_completo",      "Extraer el resto de CSV y procesar pendientes [LIGA] [limite]"),
    "ultimos":           ("ultimos_partidos",          "Procesar los ultimos partidos de una liga"),
    "pendientes":        ("matchids_pendientes",       "Procesar los partidos pendientes [csv] [limite]"),
    "comprobar":         ("comprobar_results_fixtures","Comprobar que RESULTS y FIXTURES estan listos"),
    "auditoria":         ("auditoria_fixtures",        "Lanzar la auditoria de fixtures"),
    "ids-ayer":          ("ids_partidos_ayer",         "Imprimir los match_id de ayer"),
    "monitor":           ("monitor_pendientes",        "Abrir el monitor de pendientes en vivo"),
    "grafana":           ("grafana_pendientes",        "Abrir el dashboard de pendientes en Grafana"),
    "vigilar":           ("vigilar_servicios",         "Vigilante de servicios [minutos|una-vez]"),
    "ciclo-diario":      ("ciclo_diario",              "Ciclo diario (tarea programada)"),
    "inicio-automatico": ("automatico_inicio",         "Procesamiento al iniciar sesion (tarea programada)"),
}


def _ejecutar(comando, args):
    modulo = COMANDOS[comando][0]
    return subprocess.run([sys.executable, str(LANZADORES / f"{modulo}.py"), *args]).returncode


def _menu():
    print("\n" + "=" * 60)
    print(" BASKETBALL - comandos disponibles")
    print("=" * 60)
    claves = list(COMANDOS)
    for i, c in enumerate(claves, 1):
        print(f"  [{i:>2}] {c:<18} {COMANDOS[c][1]}")
    print("  [ 0] salir")
    sel = input("\nElige un comando (numero o nombre): ").strip()
    if sel in ("0", ""):
        return 0
    if sel.isdigit():
        n = int(sel)
        if 1 <= n <= len(claves):
            return _ejecutar(claves[n - 1], [])
        print("Seleccion no valida.")
        return 1
    if sel in COMANDOS:
        return _ejecutar(sel, [])
    print(f"Comando desconocido: {sel}")
    return 1


def main():
    args = sys.argv[1:]
    if not args:
        return _menu()
    comando = args[0].lower()
    if comando in ("-h", "--help", "ayuda", "help"):
        print(__doc__)
        print("Comandos:")
        for c, (_m, d) in COMANDOS.items():
            print(f"  {c:<18} {d}")
        return 0
    if comando not in COMANDOS:
        print(f"Comando desconocido: {comando}. Usa 'basket ayuda' para ver la lista.")
        return 1
    return _ejecutar(comando, args[1:])


if __name__ == "__main__":
    sys.exit(main())
