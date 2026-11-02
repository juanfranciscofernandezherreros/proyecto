"""Consolidate one canonical competition run and submit it to the batch launcher."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


WORKSPACE = Path(__file__).resolve().parents[1]
SCRAPER = WORKSPACE / "python-pyppeter"
DATA_ROOT = Path(r"C:\data\basketball")
READY_ROOT = Path(r"C:\data\basketball-ready")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("country")
    parser.add_argument("competition")
    parser.add_argument("--launcher-url", default="http://localhost:8088")
    parser.add_argument("--match-id", action="append", default=[], help="Only ingest these match IDs; repeatable")
    args = parser.parse_args()
    raw = DATA_ROOT / "competitions" / args.country / args.competition
    if not raw.is_dir():
        parser.error(f"Canonical run does not exist: {raw}")
    match_ids = list(args.match_id)
    if not match_ids and args.country == "usa" and args.competition == "nba":
        selections = sorted((DATA_ROOT / "reports" / "usa" / "nba").glob("last-game-day-*.json"), key=lambda path: path.stat().st_mtime_ns)
        if not selections:
            parser.error("No NBA game-day selection found; provide --match-id explicitly")
        match_ids = json.loads(selections[-1].read_text(encoding="utf-8")).get("match_ids", [])
    command = [sys.executable, str(SCRAPER / "consolidate_csv.py"), "--input", str(raw), "--output", str(READY_ROOT)]
    for match_id in match_ids:
        command.extend(["--match-id", str(match_id)])
    subprocess.run(command, cwd=SCRAPER, check=True)
    subprocess.run([sys.executable, str(SCRAPER / "run_all_csv_batches.py"), "--root", str(READY_ROOT / "current"), "--launcher-url", args.launcher_url, "--timeout-seconds", "7200"], cwd=SCRAPER, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
