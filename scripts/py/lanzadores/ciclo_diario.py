# -*- coding: utf-8 -*-
r"""Lanzador: ciclo diario (CICLO_DIARIO.bat). RESULTS + pendientes + archivado."""
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from _base import ensure, SCRIPTS_PY, PY, CFG

REPORT_DIR = Path(CFG["REPORT_DIR"])


def _run_log(rel, log, *args):
    with open(log, "a", encoding="utf-8") as fh:
        return subprocess.run([PY, str(SCRIPTS_PY / rel), *args],
                              stdout=fh, stderr=subprocess.STDOUT).returncode


def _cuadre(log, tras):
    """Cuadre de ayer Flashscore / fixtures / Mongo (skill cuadrar-partidos-dia).
    Antes espera a que el projector (cada ~60 s) pase a Mongo lo recien importado.
    Un fallo se anota como AVISO y no cambia el codigo del ciclo."""
    time.sleep(int(CFG.get("CICLO_ESPERA_CUADRE") or 90))
    with open(log, "a", encoding="utf-8") as fh:
        fh.write(f"--- Cuadre de ayer Flashscore / fixtures / Mongo tras {tras}:\n")
    if _run_log("lanzadores/cuadrar_dia.py", log):
        with open(log, "a", encoding="utf-8") as fh:
            fh.write(f"[AVISO] El cuadre tras {tras} tiene partidos con problemas (ver FALLO arriba).\n")


def main():
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    log = REPORT_DIR / f"ciclo-diario-{datetime.now():%Y%m%d-%H%M%S}.log"
    print(f"Ciclo diario iniciado. Registro: {log}")
    with open(log, "a", encoding="utf-8") as fh:
        fh.write(f"[{datetime.now():%d/%m/%Y %H:%M:%S}] Inicio del ciclo diario\n")

    os.environ["ASEGURAR_LOG"] = str(log)
    if ensure("antibloqueo", "postgres", "auditoria", "launcher", "navegador"):
        with open(log, "a", encoding="utf-8") as fh:
            fh.write("[ERROR] No se pudieron arrancar los servicios; no se procesa nada.\n")
        return 1
    os.environ.pop("ASEGURAR_LOG", None)

    # Orden: datos de ayer -> cuadre -> RESULTS -> cuadre -> pendientes.
    print("Extrayendo los datos de los partidos de ayer...")
    with open(log, "a", encoding="utf-8") as fh:
        fh.write("--- Datos de ayer (basket datos-ayer):\n")
    if _run_log("lanzadores/datos_ayer.py", log):
        with open(log, "a", encoding="utf-8") as fh:
            fh.write("[AVISO] Datos de ayer con fallos; se continua.\n")
    _cuadre(log, "los datos de ayer")

    if str(CFG.get("CICLO_RESULTS")) == "1":
        with open(log, "a", encoding="utf-8") as fh:
            fh.write("--- Partidos jugados sin resultado ANTES de RESULTS:\n")
        _run_log("pendientes/fixtures_sin_results.py", log)
        print("Extrayendo RESULTS de todas las ligas...")
        if _run_log("lanzadores/ligas_orquestar.py", log, "ALL", "results"):
            with open(log, "a", encoding="utf-8") as fh:
                fh.write("[AVISO] Alguna liga fallo en RESULTS; se continua con los pendientes.\n")
        with open(log, "a", encoding="utf-8") as fh:
            fh.write("--- Partidos jugados sin resultado DESPUES de RESULTS:\n")
        _run_log("pendientes/fixtures_sin_results.py", log)
    else:
        with open(log, "a", encoding="utf-8") as fh:
            fh.write(f"RESULTS desactivado en el ciclo diario (CICLO_RESULTS={CFG.get('CICLO_RESULTS')}); se pasa a los pendientes.\n")

    _cuadre(log, "los resultados")

    print("Procesando partidos pendientes...")
    os.environ["SKIP_DATOS_AYER"] = "1"   # ya se hizo al principio del ciclo
    rc = _run_log("lanzadores/matchids_pendientes.py", log)
    os.environ.pop("SKIP_DATOS_AYER", None)
    with open(log, "a", encoding="utf-8") as fh:
        fh.write("--- Archivado de CSV repetidos:\n")
    _run_log("pendientes/archivar_csv.py", log, "aplicar")
    with open(log, "a", encoding="utf-8") as fh:
        fh.write("--- Auditoria de datos (afectados = 0 es lo bueno):\n")
    if _run_log("lanzadores/auditar.py", log):
        with open(log, "a", encoding="utf-8") as fh:
            fh.write("[AVISO] La auditoria de datos no se pudo ejecutar.\n")
    with open(log, "a", encoding="utf-8") as fh:
        fh.write(f"[{datetime.now():%d/%m/%Y %H:%M:%S}] Fin del ciclo diario. Codigo {rc}\n")
    print(f"Terminado con codigo {rc}. Registro: {log}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
