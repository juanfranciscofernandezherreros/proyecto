# -*- coding: utf-8 -*-
r"""Lanzador: procesamiento automatico al iniciar sesion (AUTOMATICO_INICIO.bat)."""
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from _base import ensure, run_mod, SCRIPTS_PY, PY, CFG

REPORT_DIR = Path(CFG["REPORT_DIR"])


def _run_log(rel, log, *args):
    with open(log, "a", encoding="utf-8") as fh:
        return subprocess.run([PY, str(SCRIPTS_PY / rel), *args],
                              stdout=fh, stderr=subprocess.STDOUT).returncode


def _stamp(fh, msg):
    fh.write(f"[{datetime.now():%d/%m/%Y %H:%M:%S}] {msg}\n")


def main():
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    log = REPORT_DIR / f"automatico-inicio-{datetime.now():%Y%m%d-%H%M%S}.log"
    print(f"Procesamiento automatico iniciado. Registro: {log}")
    with open(log, "a", encoding="utf-8") as fh:
        _stamp(fh, "Inicio del procesamiento automatico")

    os.environ["ASEGURAR_LOG"] = str(log)
    print("Arrancando Docker y servicios...")
    if ensure("antibloqueo", "postgres", "auditoria", "launcher", "navegador"):
        with open(log, "a", encoding="utf-8") as fh:
            fh.write("[ERROR] No se pudieron arrancar los servicios; no se procesa nada.\n")
        print(f"ERROR: no se pudieron arrancar los servicios. Registro: {log}")
        return 1
    print("Arrancando Grafana...")
    if ensure("grafana", "consumo"):
        with open(log, "a", encoding="utf-8") as fh:
            fh.write("[AVISO] Grafana no quedo disponible; se continua con el procesamiento.\n")
    else:
        try:
            os.startfile(f"{CFG['GRAFANA_URL']}/d/fixtures-audit-live")
        except Exception:
            pass
        with open(log, "a", encoding="utf-8") as fh:
            fh.write("Dashboard abierto en el navegador.\n")
    os.environ.pop("ASEGURAR_LOG", None)

    if str(CFG.get("INICIO_RESULTS")) == "1":
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
            fh.write(f"RESULTS desactivado al inicio (INICIO_RESULTS={CFG.get('INICIO_RESULTS')}); se pasa a los pendientes.\n")

    print("Procesando partidos pendientes...")
    rc = _run_log("lanzadores/matchids_pendientes.py", log)
    with open(log, "a", encoding="utf-8") as fh:
        _stamp(fh, f"Fin del procesamiento automatico. Codigo {rc}")
    print(f"Terminado con codigo {rc}. Registro: {log}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
