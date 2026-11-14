# -*- coding: utf-8 -*-
r"""Lanzador: ciclo diario (CICLO_DIARIO.bat). RESULTS + pendientes + archivado."""
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from _base import ensure, SCRIPTS_PY, PY, CFG

REPORT_DIR = Path(CFG["REPORT_DIR"])


def _run_log(rel, log, *args):
    with open(log, "a", encoding="utf-8") as fh:
        return subprocess.run([PY, str(SCRIPTS_PY / rel), *args],
                              stdout=fh, stderr=subprocess.STDOUT).returncode


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

    print("Procesando partidos pendientes...")
    rc = _run_log("lanzadores/matchids_pendientes.py", log)
    with open(log, "a", encoding="utf-8") as fh:
        fh.write("--- Archivado de CSV repetidos:\n")
    _run_log("pendientes/archivar_csv.py", log, "aplicar")
    with open(log, "a", encoding="utf-8") as fh:
        fh.write(f"[{datetime.now():%d/%m/%Y %H:%M:%S}] Fin del ciclo diario. Codigo {rc}\n")
    print(f"Terminado con codigo {rc}. Registro: {log}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
