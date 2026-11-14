# -*- coding: utf-8 -*-
r"""Lanzador: abre el monitor de pendientes en una ventana nueva (MONITOR_PENDIENTES.bat)."""
import subprocess
import sys
from _base import ensure, SCRIPTS_PY, PY, CFG

CREATE_NEW_CONSOLE = 0x00000010

if __name__ == "__main__":
    if ensure("antibloqueo", "watcher", "postgres", "auditoria"):
        sys.exit(1)
    subprocess.Popen([PY, str(SCRIPTS_PY / "monitor" / "ver_pendientes.py")],
                     creationflags=CREATE_NEW_CONSOLE)
    print(f"Consola de pendientes abierta. Endpoint: {CFG['AUDIT_URL']}/latest")
    sys.exit(0)
