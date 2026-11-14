# -*- coding: utf-8 -*-
r"""Lanzador: auditoria de fixtures (AUDITORIA_FIXTURES.bat). Lanza una auditoria nueva
y deja la lista de pendientes en un CSV."""
import csv
import json
import sys
import urllib.request
from datetime import datetime
from pathlib import Path
from _base import ensure, CFG

COLS = ["match_date", "country", "competition", "match_id", "home_team", "away_team", "pending_datasets"]


def main():
    print("Arrancando PostgreSQL y modulo persistente antes de consultar el endpoint...")
    if ensure("antibloqueo", "watcher", "postgres", "auditoria"):
        return 1
    print(f"Consultando auditoria de fixtures en {CFG['AUDIT_URL']}/run...")
    try:
        req = urllib.request.Request(f"{CFG['AUDIT_URL']}/run", method="POST")
        s = json.loads(urllib.request.urlopen(req, timeout=60).read().decode("utf-8"))
        if s.get("status") != "COMPLETED":
            raise RuntimeError(f"Auditoria fallo: {s.get('error')}")
    except Exception as e:
        print(f"ERROR: fallo la consulta a la auditoria.\n  {e}")
        return 1
    report_dir = Path(CFG["REPORT_DIR"])
    report_dir.mkdir(parents=True, exist_ok=True)
    rows = [{"match_date": m.get("matchDate"), "country": m.get("country"),
             "competition": m.get("competition"), "match_id": m.get("matchId"),
             "home_team": m.get("homeTeam"), "away_team": m.get("awayTeam"),
             "pending_datasets": ",".join(m.get("pendingDatasets") or [])}
            for m in (s.get("pendingMatches") or [])]
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    output = report_dir / f"FIXTURES_PROCESSING_AUDIT_PENDING_{stamp}.csv"
    with open(output, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=COLS)
        w.writeheader()
        w.writerows(rows)
    print(f"Corte: {s.get('cutoffDate')} | Fixtures: {s.get('totalFixtures')} | "
          f"Elegibles: {s.get('eligibleFixtures')} | Pendientes: {s.get('pendingFixtures')}")
    if rows:
        anchos = {c: max(len(c), *(len(str(r.get(c, "") or "")) for r in rows)) for c in COLS}
        print("  ".join(c.ljust(anchos[c]) for c in COLS))
        for r in rows:
            print("  ".join(str(r.get(c, "") or "").ljust(anchos[c]) for c in COLS))
    else:
        print("No quedan partidos pendientes.")
    print(f"Lista CSV: {output}")
    print(f"JSON en vivo: {CFG['AUDIT_URL']}/latest")
    return 0


if __name__ == "__main__":
    sys.exit(main())
