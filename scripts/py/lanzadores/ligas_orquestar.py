# -*- coding: utf-8 -*-
r"""Lanzador interno: orquesta ligas (LIGAS_ORQUESTAR.bat).
Uso: ligas_orquestar.py [ALL|CODE] [results|datos|todo] [limite]"""
import sys
from _base import ensure, run_mod

if __name__ == "__main__":
    a = sys.argv[1:]
    league = a[0] if len(a) > 0 else "ALL"
    mode = a[1] if len(a) > 1 else "todo"
    limit = a[2] if len(a) > 2 else "10"
    if ensure("antibloqueo", "postgres", "launcher", "navegador"):
        sys.exit(1)
    sys.exit(run_mod("ligas/orquestar.py", league, mode, limit))
