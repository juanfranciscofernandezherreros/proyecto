"""Extract all finished NBA games from the latest Flashscore game date."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

from proyecto_config import CONFIG, path

from recent_competition import DATASETS, SCORE, SCRAPER, WORKSPACE, completed_matches, extract_bundle, match_id, missing_datasets, invoke


DATA_ROOT = path("DATA_DIR")
URL = "https://www.flashscore.com/basketball/usa/nba/results/"
DATE = re.compile(r"\b(\d{1,2}\.\d{1,2}\.)")


def game_date(row: dict[str, object]) -> str:
    """Return Flashscore's displayed day token, failing rather than guessing a slate."""
    found = DATE.search(str(row.get("Time", "")))
    if not found:
        raise ValueError(f"Finished NBA game has no displayed date: {row.get('Match')!r}")
    return found.group(1)


def latest_game_day(rows: list[dict[str, object]]) -> tuple[str, list[dict[str, object]]]:
    finished = [row for row in rows if SCORE.fullmatch(str(row.get("Result", "")))]
    if not finished:
        raise RuntimeError("Flashscore returned no finished NBA games")
    latest = game_date(finished[0])
    selected = [row for row in finished if game_date(row) == latest]
    if not selected:
        raise RuntimeError("No NBA matches found for the latest game date")
    return latest, selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, choices=(1, 2, 3), default=3)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--recover", action="store_true")
    args = parser.parse_args()
    report_dir = DATA_ROOT / "reports" / "usa" / "nba"
    run_dir = DATA_ROOT / "competitions" / "usa" / "nba"
    report_dir.mkdir(parents=True, exist_ok=True)
    run_dir.mkdir(parents=True, exist_ok=True)

    if args.recover:
        selections = sorted(report_dir.glob("last-game-day-*.json"), key=lambda path: path.stat().st_mtime_ns)
        if not selections:
            raise RuntimeError("No saved NBA game-day selection exists to recover")
        selection = json.loads(selections[-1].read_text(encoding="utf-8"))
        stamp = str(selection["run_id"])
        pending = []
        for row in selection["matches"]:
            source = {"Match Link": row["url"], "Match": row["match"], "Result": row["result"]}
            datasets = missing_datasets(run_dir, row["match_id"], stamp)
            if datasets:
                pending.append((source, datasets))
        failures: list[str] = []
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(extract_bundle, row, run_dir, stamp, True, datasets) for row, datasets in pending]
            for future in as_completed(futures):
                identifier, succeeded = future.result()
                if not succeeded:
                    failures.append(identifier)
        selection["recovered_at"] = datetime.now(timezone.utc).isoformat()
        selection["failed_match_ids"] = failures
        selections[-1].write_text(json.dumps(selection, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return 3 if failures else 0

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    results_base = report_dir / f"RESULTS_{stamp}_usa_nba.csv"
    raw_json = report_dir / f"last-game-day-{stamp}.raw.json"
    invoke([sys.executable, str(SCRAPER / "extract_flashscore_matches.py"), URL, "--skip-periods",
            "--output", str(results_base), "--raw-json", str(raw_json), "--run-id", stamp], cwd=SCRAPER)
    rows = json.loads(raw_json.read_text(encoding="utf-8"))
    date, selected = latest_game_day(rows)
    published_results = next(report_dir.glob(f"RESULTS_{stamp}_*.csv"), None)
    if not published_results:
        raise RuntimeError("RESULTS CSV was not published")
    shutil.copy2(published_results, run_dir / published_results.name)
    selection = {"run_id": stamp, "source_url": URL, "game_date": date,
                 "match_count": len(selected), "match_ids": [match_id(row) for row in selected],
                 "matches": [{"match_id": match_id(row), "match": row.get("Match"), "result": row.get("Result"), "url": row.get("Match Link")} for row in selected]}
    selection_path = report_dir / f"last-game-day-{stamp}.json"
    selection_path.write_text(json.dumps(selection, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    failures: list[str] = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(extract_bundle, row, run_dir, stamp, args.resume) for row in selected]
        for future in as_completed(futures):
            identifier, succeeded = future.result()
            if not succeeded:
                failures.append(identifier)
    selection["finished_at"] = datetime.now(timezone.utc).isoformat()
    selection["failed_match_ids"] = failures
    selection_path.write_text(json.dumps(selection, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 3 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
