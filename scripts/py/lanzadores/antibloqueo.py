# -*- coding: utf-8 -*-
r"""Lanzador: antibloqueo (ANTIBLOQUEO.bat). Mantiene el PC despierto."""
import sys
from _base import ensure

if __name__ == "__main__":
    sys.exit(ensure("antibloqueo"))
