# -*- coding: utf-8 -*-
r"""Lanzador: match_id de fixtures de ayer (IDS_PARTIDOS_AYER.bat)."""
import sys
from _base import ensure, psql

Q = ("SELECT f.match_id FROM fixtures.fixtures f "
     "WHERE (f.event_datetime AT TIME ZONE 'Europe/Madrid')::date = "
     "((now() AT TIME ZONE 'Europe/Madrid')::date - 1) ORDER BY f.match_id;")

if __name__ == "__main__":
    if ensure("postgres"):
        sys.exit(1)
    rc = psql(["-Atc", Q], compose=True)
    if rc:
        print("\nError: no se pudieron consultar los partidos de ayer.")
    sys.exit(1 if rc else 0)
