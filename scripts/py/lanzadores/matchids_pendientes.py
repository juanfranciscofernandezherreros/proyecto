# -*- coding: utf-8 -*-
r"""Lanzador: procesar partidos pendientes (MATCHIDS_PENDIENTES.bat).
Uso: matchids_pendientes.py [csv_seleccion] [limite]

Como resultados-ayer, llega hasta el projector: levanta tambien el runtime (Mongo,
projector, API y web) y, al terminar, espera al projector y comprueba en Mongo que
cada partido procesado esta y con que secciones."""
import csv
import os
import sys
import time
from pathlib import Path

from _base import ensure, run_mod, CFG


def procesados_desde(inicio):
    """match_id COMPLETED del PROCESAR_MATCHIDS_*.csv de esta ejecucion (el mas reciente
    creado despues de `inicio`), con su liga y equipos. Vacio si no hay."""
    carpeta = Path(CFG.get("REPORT_DIR"))
    cands = [p for p in carpeta.glob("PROCESAR_MATCHIDS_*.csv")
             if "ERRORES" not in p.name and p.stat().st_mtime >= inicio]
    if not cands:
        return []
    with open(max(cands, key=lambda p: p.stat().st_mtime), encoding="utf-8-sig", newline="") as fh:
        return [f for f in csv.DictReader(fh) if f.get("status") == "COMPLETED"]


def comprobar_en_mongo(filas):
    """Espera al projector y comprueba en Mongo cada partido. Devuelve cuantos no estan."""
    import cuadrar_dia as C
    if not filas:
        print("No hay partidos procesados que comprobar en Mongo.")
        return 0
    espera = int(CFG.get("CICLO_ESPERA_CUADRE") or 90)
    print(f"Esperando {espera} s a que el projector lo lleve a Mongo...")
    time.sleep(espera)
    try:
        mongo = C.leer_mongo({f["match_id"] for f in filas})
    except RuntimeError as e:
        print(f"ERROR: {e}")
        return len(filas)
    ausentes = completos = 0
    for f in filas:
        m = mongo.get(f["match_id"])
        if m is None:
            estado = "NO ESTA EN MONGO"
            ausentes += 1
        else:
            faltan = [s for s in C.SECCIONES if s not in (m.get("secciones") or [])]
            estado = "OK" if not faltan else "FALTAN " + ",".join(faltan)
            completos += not faltan
        print(f"  {estado:<5} {f['match_id']}  {f['country']}/{f['competition']}  "
              f"{f.get('home_team')} - {f.get('away_team')}")
    print(f"En Mongo (projector): {len(filas) - ausentes} de {len(filas)} partidos; "
          f"{completos} con todas las secciones.")
    return ausentes


if __name__ == "__main__":
    os.environ["SKIP_CSV_WATCHER"] = "1"
    a = sys.argv[1:]
    if ensure("antibloqueo", "postgres", "auditoria", "launcher", "runtime", "navegador"):
        print("ERROR: no se pudieron asegurar los servicios necesarios.")
        sys.exit(1)
    inicio = time.time()
    # Paso previo: los datos de los partidos de ayer que hay en fixtures. Un fallo aqui
    # no impide procesar el resto de pendientes.
    import datos_ayer
    if datos_ayer.activo(os.environ, CFG):
        print("Paso previo: datos de los partidos de ayer en fixtures (basket datos-ayer)...")
        if datos_ayer.main([]):
            print("[AVISO] datos-ayer devolvio error; se continua con los pendientes.")
    else:
        print("Paso previo datos-ayer desactivado (SKIP_DATOS_AYER=1 o DATOS_AYER=0).")
    print("El proceso refrescara la auditoria antes de empezar y despues de cada partido.")
    rc = run_mod("pendientes/procesar_matchids.py", *a)
    if rc:
        print(f"ERROR: el procesamiento termino con codigo {rc}.")
    else:
        print(f"Procesamiento terminado. Consulta el CSV de resumen generado en {CFG.get('REPORT_DIR')}.")
    ausentes = comprobar_en_mongo(procesados_desde(inicio))
    sys.exit(rc or (1 if ausentes else 0))
