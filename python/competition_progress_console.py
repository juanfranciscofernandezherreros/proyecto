"""Show only events actually emitted by a competition extraction."""

from __future__ import annotations

import argparse
import csv
import re
import time
from datetime import datetime
from pathlib import Path


DATA_ROOT = Path(r"C:\data\basketball")
MATCH = re.compile(r"[?&]mid=([A-Za-z0-9]+)")
CSV = re.compile(r"CSV created:\s+(.+\.csv)")
EVENT = re.compile(r"(extract_flashscore_match_bundle\.py|CSV created:|Generated files:|Manifest creado:|Browser timeout|Traceback|ERROR|failed)", re.IGNORECASE)


def latest_log(report_dir: Path) -> Path | None:
    logs = sorted(report_dir.glob("mcp-*.out.log"), key=lambda path: path.stat().st_mtime_ns)
    return logs[-1] if logs else None


def format_event(line: str) -> str | None:
    if not EVENT.search(line):
        return None
    match = MATCH.search(line)
    if "extract_flashscore_match_bundle.py" in line and match:
        return f"INICIADO      {match.group(1)}"
    csv = CSV.search(line)
    if csv:
        return f"GENERADO      {Path(csv.group(1)).name}"
    if "Generated files:" in line:
        return f"PARTIDO TERMINADO  {line.strip()}"
    return f"EVENTO        {line.strip()}"


def latest_file(directory: Path, pattern: str) -> Path | None:
    candidates = sorted(directory.glob(pattern), key=lambda path: path.stat().st_mtime_ns)
    return candidates[-1] if candidates else None


def read_matches(results: Path | None) -> dict[str, str]:
    if results is None:
        return {}
    try:
        with results.open(encoding="utf-8-sig", newline="") as handle:
            return {
                row["matchId"]: f"{row['homeTeam']} vs {row['awayTeam']}"
                for row in csv.DictReader(handle)
                if row.get("matchId")
            }
    except (OSError, KeyError):
        return {}


def live_snapshot(run_dir: Path) -> tuple[str, tuple[str, ...]]:
    inventory = latest_file(run_dir, "INVENTORY_*.csv")
    matches = read_matches(latest_file(run_dir, "RESULTS_*.csv"))
    counts: dict[str, int] = {}
    if inventory:
        try:
            with inventory.open(encoding="utf-8-sig", newline="") as handle:
                for row in csv.DictReader(handle):
                    status = row.get("status", "unknown") or "unknown"
                    counts[status] = counts.get(status, 0) + 1
        except OSError:
            pass
    # A bundle log is created when a worker starts it. While the child extractor
    # is running it has no final output yet, so its log remains empty.
    threshold = time.time() - 15 * 60
    active = []
    for bundle_log in (run_dir / "logs").glob("*_bundle.log"):
        if bundle_log.stat().st_size == 0 and bundle_log.stat().st_mtime >= threshold:
            match_id = bundle_log.name.removesuffix("_bundle.log")
            active.append(f"{match_id}: {matches.get(match_id, 'equipo no resuelto')}")
    summary = " ".join(f"{name}={count}" for name, count in sorted(counts.items()))
    return summary or "sin inventario", tuple(sorted(active))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("country")
    parser.add_argument("competition")
    args = parser.parse_args()
    report_dir = DATA_ROOT / "reports" / args.country / args.competition
    run_dir = DATA_ROOT / "competitions" / args.country / args.competition
    print(f"Progreso real — {args.country}/{args.competition}")
    print("Muestra sólo comandos, CSV creados y errores emitidos por el extractor. Cierra esta ventana para salir.\n", flush=True)
    active: Path | None = None
    offset = 0
    previous_snapshot: tuple[str, tuple[str, ...]] | None = None
    while True:
        snapshot = live_snapshot(run_dir)
        if snapshot != previous_snapshot:
            summary, active_bundles = snapshot
            print(f"[{datetime.now():%H:%M:%S}] ESTADO        {summary}", flush=True)
            if active_bundles:
                for bundle in active_bundles:
                    print(f"[{datetime.now():%H:%M:%S}] EN CURSO      {bundle}", flush=True)
            previous_snapshot = snapshot
        candidate = latest_log(report_dir)
        if candidate != active:
            active, offset = candidate, 0
            if active:
                print(f"LOG ACTIVO: {active}", flush=True)
        if active and active.is_file():
            with active.open("r", encoding="utf-8", errors="replace") as handle:
                handle.seek(offset)
                for line in handle:
                    event = format_event(line)
                    if event:
                        print(f"[{datetime.now():%H:%M:%S}] {event}", flush=True)
                offset = handle.tell()
        time.sleep(2)


if __name__ == "__main__":
    raise SystemExit(main())
