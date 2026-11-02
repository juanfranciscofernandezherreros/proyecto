"""Extract and import only the requested datasets for one Flashscore match."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from proyecto_config import CONFIG, path

WORKSPACE = Path(__file__).resolve().parents[1]
PYTHON = WORKSPACE / "python-pyppeter" / ".venv" / "Scripts" / "python.exe"
SCRAPER = WORKSPACE / "python-pyppeter" / "extract_flashscore_match_bundle.py"
RESOLVER = WORKSPACE / "python" / "resolve_flashscore_redirect.py"
CONSOLIDATOR = WORKSPACE / "python-pyppeter" / "consolidate_csv.py"
SUBMITTER = WORKSPACE / "python-pyppeter" / "run_all_csv_batches.py"
RAW = path("COMPETITIONS_DIR")
READY = path("READY_ROOT")
DATASETS = {
    "MATCH_SUMMARY": ("score_summary.csv", "SCORE_SUMMARY_"),
    "TEAM_STATS": ("stats_all_periods.csv", "STATS_ALL_PERIODS_"),
    "PLAYER_STATS": ("player_stats.csv", "PLAYER_STATS_"),
    "POINT_BY_POINT": ("point_by_point.csv", "POINT_BY_POINT_"),
}

def call(*args: str) -> None:
    completed = subprocess.run(args, cwd=WORKSPACE)
    if completed.returncode:
        raise RuntimeError(f"Command failed with exit code {completed.returncode}: {subprocess.list2cmdline(args)}")

def canonical_url(match_id: str) -> str:
    completed = subprocess.run((str(PYTHON), str(RESOLVER), match_id), cwd=WORKSPACE, text=True, capture_output=True)
    url = completed.stdout.strip()
    if completed.returncode or not url:
        raise RuntimeError(f"Flashscore did not resolve a canonical URL for {match_id}: {completed.stderr.strip()}")
    return url

def has_rows(path: Path) -> bool:
    with path.open(encoding="utf-8-sig") as handle:
        next(handle, None)
        return next(handle, None) is not None

def latest_data(match_dir: Path, prefix: str) -> Path | None:
    return next((path for path in sorted(match_dir.glob(f"{prefix}*.csv"), key=lambda p: p.stat().st_mtime, reverse=True) if has_rows(path)), None)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("match_id")
    parser.add_argument("country")
    parser.add_argument("competition")
    parser.add_argument("datasets", nargs="+", choices=tuple(DATASETS))
    args = parser.parse_args()
    root = RAW / args.country / args.competition
    match_dir = root / args.match_id
    os.environ.setdefault("PYTHONUNBUFFERED", "1")
    print(f"[{args.match_id}] resolving canonical Flashscore URL...", flush=True)
    url = canonical_url(args.match_id)
    print(f"[{args.match_id}] canonical URL resolved; datasets={','.join(dict.fromkeys(args.datasets))}", flush=True)
    for logical in dict.fromkeys(args.datasets):
        dataset, prefix = DATASETS[logical]
        for attempt in range(1, 4):
            print(f"[{args.match_id}] extracting {logical} (attempt {attempt}/3)...", flush=True)
            call(str(PYTHON), str(SCRAPER), url, "--data-dir", str(root), "--dataset", dataset)
            if latest_data(match_dir, prefix):
                break
            if attempt == 3:
                raise RuntimeError(f"{logical} was empty after 3 attempts for {args.match_id}")
            print(f"[{args.match_id}] {logical} CSV is empty; retrying...", flush=True)
        csv_path = latest_data(match_dir, prefix)
        print(f"[{args.match_id}] consolidating {csv_path.name}...", flush=True)
        call(str(PYTHON), str(CONSOLIDATOR), "--input", str(root), "--output", str(READY), "--match-id", args.match_id, "--prefix", prefix)
        print(f"[{args.match_id}] submitting {logical} to batch launcher...", flush=True)
        call(str(PYTHON), str(SUBMITTER), "--root", str(READY / "current" / args.match_id), "--prefix", prefix, "--launcher-url", CONFIG["LAUNCHER_URL"], "--timeout-seconds", "120")
        print(f"[{args.match_id}] {logical} import completed.", flush=True)
    print(f"[{args.match_id}] all requested datasets completed.", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
