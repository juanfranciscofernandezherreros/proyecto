# -*- coding: utf-8 -*-
r"""Lanzador: vigilante de servicios (VIGILAR_SERVICIOS.bat). Cada N minutos comprueba
los servicios y arranca los parados.  Uso: vigilar_servicios.py [minutos|una-vez] [servicio...]"""
import io
import sys
import time
from contextlib import redirect_stdout
from datetime import datetime
from pathlib import Path
from _base import ensure, CFG

DEFAULT = ["antibloqueo", "postgres", "auditoria", "launcher", "grafana"]


def _una_pasada(servicios, log):
    print(f"\n[{datetime.now():%d/%m/%Y %H:%M:%S}] Comprobando servicios...")
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = ensure(*servicios)
    salida = buf.getvalue()
    sys.stdout.write(salida)
    if any(k in salida for k in ("arrancando", "reiniciando", "ERROR")):
        with open(log, "a", encoding="utf-8") as fh:
            fh.write(f"[{datetime.now():%d/%m/%Y %H:%M:%S}] codigo {rc}\n{salida}")
    return rc


def main():
    a = sys.argv[1:]
    once = bool(a) and a[0].lower() == "una-vez"
    if once:
        a = a[1:]
        interval = 5
    else:
        interval = int(a[0]) if a and a[0].isdigit() else 5
        if a and a[0].isdigit():
            a = a[1:]
    if interval == 0:
        interval = 1
    servicios = a if a else DEFAULT
    report_dir = Path(CFG["REPORT_DIR"])
    report_dir.mkdir(parents=True, exist_ok=True)
    log = report_dir / "vigilancia-servicios.log"
    if not once:
        print(f"Vigilando cada {interval} min: {' '.join(servicios)}\nRegistro: {log}")
    while True:
        rc = _una_pasada(servicios, log)
        if once:
            return rc
        time.sleep(interval * 60 + 1)


if __name__ == "__main__":
    sys.exit(main())
