"""Visible console monitor for the selected-match CSV completeness of a competition."""

from __future__ import annotations

import argparse
import json
import time
from datetime import datetime
from pathlib import Path


DATA_ROOT = Path(r"C:\data\basketball")
PREFIXES = (
    "MATCH_DETAILS", "SCORE_SUMMARY", "PLAYER_STATS", "STATS_ALL_PERIODS",
    "POINT_BY_POINT", "H2H", "ODDS_HOME_AWAY", "ODDS_1X2",
    "ODDS_OVER_UNDER", "ODDS_ASIAN_HANDICAP",
)


def latest_selection(report_dir: Path, selection_name: str) -> tuple[Path, dict[str, object]] | None:
    paths = sorted(
        (path for path in report_dir.glob(f"{selection_name}-*.json") if not path.name.endswith(".raw.json")),
        key=lambda path: path.stat().st_mtime_ns,
    )
    if not paths:
        return None
    try:
        return paths[-1], json.loads(paths[-1].read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def missing_datasets(run_dir: Path, run_id: str, match_id: str) -> list[str]:
    directory = run_dir / match_id
    return [prefix for prefix in PREFIXES if not any(directory.glob(f"{prefix}_{run_id}_{match_id}.csv"))]


def snapshot(country: str, competition: str, selection_name: str) -> tuple[str, dict[str, tuple[str, set[str]]]]:
    report_dir = DATA_ROOT / "reports" / country / competition
    run_dir = DATA_ROOT / "competitions" / country / competition
    latest = latest_selection(report_dir, selection_name)
    if not latest:
        return "waiting", {}
    path, selection = latest
    run_id = str(selection.get("run_id", ""))
    matches = selection.get("matches", [])
    progress: dict[str, tuple[str, set[str]]] = {}
    for row in matches:
        if not isinstance(row, dict):
            continue
        match_id = str(row.get("match_id", ""))
        missing = missing_datasets(run_dir, run_id, match_id)
        label = str(row.get("match", match_id))
        progress[match_id] = (label, set(missing))
    return str(selection.get("state", "unknown")), progress


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("country")
    parser.add_argument("competition")
    parser.add_argument("--selection-name", default="last-results")
    parser.add_argument("--interval", type=int, default=5, choices=range(1, 61))
    args = parser.parse_args()
    print(f"Basketball CSV status — {args.country}/{args.competition}", flush=True)
    print("Se imprime sólo cuando cambia el estado. Cierra esta ventana para detener el monitor.", flush=True)
    previous: dict[str, tuple[str, set[str]]] | None = None
    while True:
        state, progress = snapshot(args.country, args.competition, args.selection_name)
        if not progress:
            if previous is None:
                print("Esperando la selección de partidos…", flush=True)
            previous = progress
            time.sleep(args.interval)
            continue
        if previous is None or previous == {}:
            total = len(progress) * len(PREFIXES)
            print(f"\nPLAN: {len(progress)} partidos; hasta {total} datasets por comprobar.", flush=True)
            for match_id, (label, missing) in progress.items():
                print(f"POR GENERAR  {match_id}  {label}: {', '.join(sorted(missing))}", flush=True)
        elif previous is not None:
            for match_id, (label, missing) in progress.items():
                old_missing = previous.get(match_id, (label, set(PREFIXES)))[1]
                for dataset in sorted(old_missing - missing):
                    print(f"GENERADO     {match_id}  {label}: {dataset}", flush=True)
                if old_missing and not missing:
                    print(f"PARTIDO COMPLETO  {match_id}  {label}", flush=True)
        complete = sum(1 for _label, missing in progress.values() if not missing)
        remaining = sum(len(missing) for _label, missing in progress.values())
        if previous != progress:
            print(f"AVANCE: {complete}/{len(progress)} partidos completos; {remaining} datasets pendientes; estado={state}", flush=True)
        previous = progress
        time.sleep(args.interval)


if __name__ == "__main__":
    raise SystemExit(main())
