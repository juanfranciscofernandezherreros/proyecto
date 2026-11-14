# -*- coding: utf-8 -*-
r"""Lanzador: Grafana de pendientes (GRAFANA_PENDIENTES.bat). Arranca lo necesario y
abre el dashboard."""
import os
import sys
from _base import ensure, CFG

if __name__ == "__main__":
    if ensure("antibloqueo", "postgres", "auditoria", "grafana", extra=["--actualizar-dashboard"]):
        sys.exit(1)
    dashboard = f"{CFG['GRAFANA_URL']}/d/fixtures-audit-live"
    print(f"Abriendo {dashboard}")
    try:
        os.startfile(dashboard)
    except Exception:
        import webbrowser
        webbrowser.open(dashboard)
    sys.exit(0)
