# -*- coding: utf-8 -*-
r"""Lanzador: procesar partidos pendientes (MATCHIDS_PENDIENTES.bat).
Uso: matchids_pendientes.py [csv_seleccion] [limite]

Como resultados-ayer, llega hasta el projector: levanta tambien el runtime (Mongo,
projector, API y web) y, al terminar, espera al projector y comprueba en Mongo que
cada partido procesado esta y con que secciones. Termina con una linea RESUMEN que
tambien se manda al bot de Telegram."""
import csv
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

from _base import ensure, run_mod, CFG

# Resumen de la ejecucion; se imprime al final en una sola linea RESUMEN.
_R = {}


def filas_ejecucion(inicio):
    """Filas del PROCESAR_MATCHIDS_*.csv de esta ejecucion (el mas reciente creado
    despues de `inicio`). Vacio si no hay (nada que procesar)."""
    carpeta = Path(CFG.get("REPORT_DIR"))
    cands = [p for p in carpeta.glob("PROCESAR_MATCHIDS_*.csv")
             if "ERRORES" not in p.name and p.stat().st_mtime >= inicio]
    if not cands:
        return []
    with open(max(cands, key=lambda p: p.stat().st_mtime), encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh))


def procesados_desde(inicio):
    """match_id COMPLETED de esta ejecucion, con su liga y equipos."""
    return [f for f in filas_ejecucion(inicio) if f.get("status") == "COMPLETED"]


def comprobar_en_mongo(filas):
    """Espera al projector y comprueba en Mongo cada partido. Devuelve cuantos no estan
    y deja en _R cuantos estan y cuantos tienen todas las secciones."""
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
        _R.update(en_mongo=0, completos=0)
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
    _R.update(en_mongo=len(filas) - ausentes, completos=completos)
    return ausentes


def quedan_pendientes():
    """pendingFixtures de la ultima auditoria, o None si no responde."""
    try:
        with urllib.request.urlopen(f"{CFG.get('AUDIT_URL')}/latest", timeout=10) as r:
            return json.loads(r.read().decode("utf-8")).get("pendingFixtures")
    except Exception:
        return None


def linea_resumen(r):
    """Una linea con como acabo. Que falten secciones no es fallo (pueden no estar
    publicadas); si lo son los errores y los partidos que no llegan a Mongo."""
    quedan = f" · quedan {r['quedan']}" if r.get("quedan") is not None else ""
    if r.get("error"):
        return f"❌ Pendientes · ERROR: {r['error']}{quedan}"
    procesados, errores = r.get("procesados", 0), r.get("errores", 0)
    if not procesados and not errores:
        return f"✅ Pendientes · nada que procesar{quedan}"
    partes = [f"{procesados} procesados"]
    if errores:
        partes.append(f"{errores} con error")
    if procesados:
        partes.append(f"{r.get('en_mongo', 0)} de {procesados} en Mongo ({r.get('completos', 0)} completos)")
    mal = bool(errores) or r.get("en_mongo", 0) < procesados
    return f"{'❌' if mal else '✅'} Pendientes · " + " · ".join(partes) + quedan


def _avisar(linea):
    """Imprime la linea RESUMEN y la manda al bot (si esta configurado; si falla, avisa)."""
    print(f"RESUMEN: {linea}")
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "monitor"))
        import telegram_csv
        if telegram_csv.configurado():
            telegram_csv.enviar_texto(linea)
    except Exception as e:
        print(f"[AVISO] Telegram: no se pudo enviar el resumen: {e}")


def _ejecutar(a):
    if ensure("antibloqueo", "postgres", "auditoria", "launcher", "runtime", "navegador"):
        print("ERROR: no se pudieron asegurar los servicios necesarios.")
        _R["error"] = "no se pudieron arrancar los servicios"
        return 1
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
        _R["error"] = f"el procesado termino con codigo {rc}"
    else:
        print(f"Procesamiento terminado. Consulta el CSV de resumen generado en {CFG.get('REPORT_DIR')}.")
    filas = filas_ejecucion(inicio)
    completados = [f for f in filas if f.get("status") == "COMPLETED"]
    _R.update(procesados=len(completados), errores=sum(1 for f in filas if f.get("status") == "ERROR"))
    ausentes = comprobar_en_mongo(completados)
    return rc or (1 if ausentes else 0)


def main(a):
    _R.clear()
    try:
        rc = _ejecutar(a)
    except Exception as e:  # cualquier fallo inesperado tambien se resume y avisa
        _R["error"] = str(e)[:200]
        rc = 1
    _R["quedan"] = quedan_pendientes()
    _avisar(linea_resumen(_R))
    return rc


if __name__ == "__main__":
    os.environ["SKIP_CSV_WATCHER"] = "1"
    sys.exit(main(sys.argv[1:]))
