"""Reusable extraction of the newest completed basketball matches in a competition."""

from __future__ import annotations

import json
import csv
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse

WORKSPACE = Path(__file__).resolve().parents[1]
SCRAPER = WORKSPACE / "python-pyppeter"
DATA_ROOT = Path(r"C:\data\basketball")
SCORE = re.compile(r"^\s*\d+\s*-\s*\d+\s*$")
DATASETS = {"match_details.csv": "MATCH_DETAILS", "score_summary.csv": "SCORE_SUMMARY", "player_stats.csv": "PLAYER_STATS", "stats_all_periods.csv": "STATS_ALL_PERIODS", "point_by_point.csv": "POINT_BY_POINT", "h2h.csv": "H2H", "odds_home_away.csv": "ODDS_HOME_AWAY", "odds_1x2.csv": "ODDS_1X2", "odds_over_under.csv": "ODDS_OVER_UNDER", "odds_asian_handicap.csv": "ODDS_ASIAN_HANDICAP"}

def completed_matches(rows: list[dict[str, object]], limit: int) -> list[dict[str, object]]:
    """Keep the newest completed matches from Flashscore's result order."""
    selected = [row for row in rows if SCORE.fullmatch(str(row.get("Result", "")))]
    if len(selected) < limit:
        raise RuntimeError(f"Flashscore returned only {len(selected)} completed matches; expected {limit}")
    return selected[:limit]

def match_id(row: dict[str, object]) -> str:
    values = parse_qs(urlparse(str(row["Match Link"])).query).get("mid", [])
    if not values or not re.fullmatch(r"[A-Za-z0-9]+", values[0]):
        raise ValueError(f"Invalid Flashscore match URL: {row.get('Match Link')!r}")
    return values[0]

def invoke(command: list[str], *, cwd: Path) -> None:
    print("+", subprocess.list2cmdline(command), flush=True)
    subprocess.run(command, cwd=cwd, check=True)

def extract_bundle(row: dict[str, object], run_dir: Path, stamp: str, resume: bool, datasets: list[str] | None = None) -> tuple[str, bool]:
    identifier = match_id(row)
    command = [sys.executable, str(SCRAPER / "extract_flashscore_match_bundle.py"), str(row["Match Link"]), "--data-dir", str(run_dir), "--run-id", stamp]
    if resume:
        command.append("--resume")
    for dataset in datasets or []:
        command += ["--dataset", dataset]
    try:
        invoke(command, cwd=SCRAPER)
        return identifier, True
    except subprocess.CalledProcessError:
        return identifier, False

def missing_datasets(run_dir: Path, identifier: str, stamp: str) -> list[str]:
    directory = run_dir / identifier
    return [dataset for dataset, prefix in DATASETS.items() if not any(directory.glob(f"{prefix}_{stamp}_{identifier}.csv"))]

def publish_selected_results(source: Path, destination: Path, selected_ids: set[str]) -> None:
    """Publish only the selected match rows while retaining the raw listing in reports."""
    with source.open("r", encoding="utf-8-sig", newline="") as input_file:
        reader = csv.DictReader(input_file)
        if not reader.fieldnames or "matchId" not in reader.fieldnames:
            raise RuntimeError(f"RESULTS CSV has no matchId column: {source}")
        rows = [row for row in reader if row.get("matchId") in selected_ids]
    if len(rows) != len(selected_ids):
        found = {row["matchId"] for row in rows}
        raise RuntimeError(f"RESULTS CSV is missing selected match IDs: {sorted(selected_ids - found)}")
    partial = destination.with_suffix(destination.suffix + ".partial")
    with partial.open("w", encoding="utf-8", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=reader.fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    partial.replace(destination)

def _extract_pending(pending: list[tuple[dict[str, object], list[str] | None]], run_dir: Path, stamp: str, workers: int, resume: bool = True) -> list[str]:
    failures: list[str] = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(extract_bundle, row, run_dir, stamp, resume, datasets) for row, datasets in pending]
        for future in as_completed(futures):
            identifier, succeeded = future.result()
            if not succeeded:
                failures.append(identifier)
    return failures

def bundle_progress(run_dir: Path, selection: dict[str, object]) -> dict[str, list[str]]:
    """Return missing datasets by selected match ID for one immutable selection."""
    stamp = str(selection["run_id"])
    return {
        str(row["match_id"]): missing_datasets(run_dir, str(row["match_id"]), stamp)
        for row in selection["matches"]
    }

def _write_selection(path: Path, selection: dict[str, object]) -> None:
    path.write_text(json.dumps(selection, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def _recover_selected(selection: dict[str, object], run_dir: Path, workers: int, attempts: int) -> dict[str, list[str]]:
    """Retry only missing CSV datasets, refreshing the persisted progress after each pass."""
    stamp = str(selection["run_id"])
    sources = {
        str(row["match_id"]): {"Match Link": row["url"], "Match": row["match"], "Result": row["result"]}
        for row in selection["matches"]
    }
    for attempt in range(1, attempts + 1):
        missing = bundle_progress(run_dir, selection)
        pending = [(sources[match], datasets) for match, datasets in missing.items() if datasets]
        if not pending:
            return missing
        _extract_pending(pending, run_dir, stamp, workers, True)
        selection["recovery_attempt"] = attempt
        selection["last_recovery_at"] = datetime.now(timezone.utc).isoformat()
    return bundle_progress(run_dir, selection)

def run_recent_competition(*, url: str, country: str, competition: str, matches: int, workers: int, resume: bool, recover: bool, selection_name: str = "last-results", attempts: int = 3) -> int:
    """Extract or recover a persisted selection of newest completed matches."""
    if not 1 <= matches <= 30 or not 1 <= attempts <= 5:
        raise ValueError("matches must be 1-30 and attempts must be 1-5")
    report_dir = DATA_ROOT / "reports" / country / competition
    run_dir = DATA_ROOT / "competitions" / country / competition
    report_dir.mkdir(parents=True, exist_ok=True)
    run_dir.mkdir(parents=True, exist_ok=True)
    if recover:
        selections = sorted(
            (path for path in report_dir.glob(f"{selection_name}-*.json") if not path.name.endswith(".raw.json")),
            key=lambda path: path.stat().st_mtime_ns,
        )
        if not selections:
            raise RuntimeError(f"No saved {competition} selection exists to recover")
        selection_path = selections[-1]
        selection = json.loads(selection_path.read_text(encoding="utf-8"))
        stamp = str(selection["run_id"])
        selection["state"] = "recovering"
        _write_selection(selection_path, selection)
        missing = _recover_selected(selection, run_dir, workers, attempts)
        selection["recovered_at"] = datetime.now(timezone.utc).isoformat()
        selection["missing_datasets"] = missing
        selection["failed_match_ids"] = [match for match, datasets in missing.items() if datasets]
        selection["state"] = "complete" if not selection["failed_match_ids"] else "incomplete"
        _write_selection(selection_path, selection)
        return 3 if selection["failed_match_ids"] else 0
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    results_base = report_dir / f"RESULTS_{stamp}_{country}_{competition}.csv"
    raw_json = report_dir / f"{selection_name}-{stamp}.raw.json"
    invoke([sys.executable, str(SCRAPER / "extract_flashscore_matches.py"), url, "--skip-periods", "--output", str(results_base), "--raw-json", str(raw_json), "--run-id", stamp], cwd=SCRAPER)
    selected = completed_matches(json.loads(raw_json.read_text(encoding="utf-8")), matches)
    published_results = next(report_dir.glob(f"RESULTS_{stamp}_*.csv"), None)
    if not published_results:
        raise RuntimeError("RESULTS CSV was not published")
    publish_selected_results(published_results, run_dir / published_results.name, {match_id(row) for row in selected})
    selection = {"run_id": stamp, "source_url": url, "selection": "newest completed matches in Flashscore order", "state": "extracting", "match_count": len(selected), "match_ids": [match_id(row) for row in selected], "matches": [{"match_id": match_id(row), "match": row.get("Match"), "result": row.get("Result"), "url": row.get("Match Link")} for row in selected]}
    selection_path = report_dir / f"{selection_name}-{stamp}.json"
    _write_selection(selection_path, selection)
    _extract_pending([(row, None) for row in selected], run_dir, stamp, workers, resume)
    missing = _recover_selected(selection, run_dir, workers, attempts)
    selection["finished_at"] = datetime.now(timezone.utc).isoformat()
    selection["missing_datasets"] = missing
    selection["failed_match_ids"] = [match for match, datasets in missing.items() if datasets]
    selection["state"] = "complete" if not selection["failed_match_ids"] else "incomplete"
    _write_selection(selection_path, selection)
    return 3 if selection["failed_match_ids"] else 0
