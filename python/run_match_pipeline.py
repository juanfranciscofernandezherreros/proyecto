"""Run the canonical CSV pipeline for exactly one Flashscore match ID.

The raw bundle remains under ``competitions/<country>/<competition>/<match>``.
Only that match is published to ``basketball-ready/current`` and submitted to
the batch launcher.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


WORKSPACE = Path(__file__).resolve().parents[1]
SCRAPER = WORKSPACE / "python-pyppeter"
RESOLVER = WORKSPACE / "python" / "resolve_flashscore_redirect.py"
CONSOLIDATOR = SCRAPER / "consolidate_csv.py"
DATA_ROOT = Path(r"C:\data\basketball")
READY_ROOT = Path(r"C:\data\basketball-ready")
MATCH_ID = re.compile(r"^[A-Za-z0-9]+$")
SLUG = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def command(*args: str) -> None:
    print(subprocess.list2cmdline(list(args)), flush=True)
    subprocess.run(list(args), cwd=WORKSPACE, check=True)


def match_url(match_id: str) -> str:
    """Resolve an ID in the browser and return only Flashscore's canonical URL."""
    if not RESOLVER.is_file():
        raise RuntimeError(f"Canonical URL resolver not found: {RESOLVER}")
    completed = subprocess.run(
        [sys.executable, str(RESOLVER), match_id], cwd=WORKSPACE,
        text=True, capture_output=True,
    )
    url = completed.stdout.strip()
    if completed.returncode != 0:
        detail = completed.stderr.strip() or "resolver exited without details"
        raise RuntimeError(f"Could not resolve canonical Flashscore URL for {match_id}: {detail}")
    parsed = urlparse(url)
    if parsed.scheme != "https" or "flashscore" not in parsed.netloc or parse_qs(parsed.query).get("mid") != [match_id]:
        raise RuntimeError(f"Resolver returned a non-canonical URL for {match_id}: {url}")
    return url


def manifest_is_complete(run_dir: Path, match_id: str) -> bool:
    path = run_dir / match_id / "manifest.json"
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return manifest.get("match_id") == match_id and not any(
        item.get("status") == "failed"
        for item in manifest.get("files", {}).values()
    )


def refresh_player_stats(run_dir: Path, match_id: str, country: str, competition: str) -> None:
    """Refresh player stats in an existing bundle without replacing other datasets."""
    manifest = json.loads((run_dir / match_id / "manifest.json").read_text(encoding="utf-8"))
    bundle_run_id = manifest.get("run_id")
    if not bundle_run_id:
        raise RuntimeError("Existing bundle is missing run_id")
    command(
        sys.executable, str(SCRAPER / "extract_flashscore_match_bundle.py"),
        match_url(match_id), "--data-dir", str(run_dir), "--run-id", bundle_run_id,
        "--dataset", "player_stats.csv",
    )


def publish_results_csv(run_dir: Path, match_id: str, country: str, competition: str, run_id: str) -> None:
    """Create the mandatory RESULTS record from this bundle.

    Detail bundles own the score source.  RESULTS is kept at the competition
    root because it establishes the match record consumed by every detail
    batch.  FIXTURES is deliberately excluded from this match-ID flow.
    """
    match_dir = run_dir / match_id
    manifest = json.loads((match_dir / "manifest.json").read_text(encoding="utf-8"))
    details = next(match_dir.glob("MATCH_DETAILS_*_*.csv"), None)
    summary = next(match_dir.glob("SCORE_SUMMARY_*_*.csv"), None)
    if details is None or summary is None:
        raise RuntimeError("Complete bundle is missing MATCH_DETAILS or SCORE_SUMMARY")
    scores: dict[str, str] = {}
    with summary.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            scores[row.get("side", "").strip()] = row.get("total", "").strip()
    if not scores.get("home", "").isdigit() or not scores.get("away", "").isdigit():
        raise RuntimeError("SCORE_SUMMARY does not contain numeric home and away totals")
    periods: dict[str, str] = {}
    with details.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            label = row.get("label", "")
            value = row.get("value", "").strip()
            if row.get("record_type") == "score_period" and re.fullmatch(r"(home|away)_period_[1-5]", label) and value.isdigit():
                periods[label] = value
    results = run_dir / f"RESULTS_{run_id}_{country}_{competition}.csv"
    with results.open("w", encoding="utf-8", newline="") as handle:
        fields = ["matchId", "eventTime", "eventDatetime", "homeTeam", "awayTeam", "homeScore", "awayScore", *[f"home_score{i}" for i in range(1, 6)], *[f"away_score{i}" for i in range(1, 6)]]
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerow({"matchId": match_id, "eventTime": "", "eventDatetime": "", "homeTeam": manifest.get("home_team", ""), "awayTeam": manifest.get("away_team", ""), "homeScore": scores["home"], "awayScore": scores["away"], **{f"home_score{i}": periods.get(f"home_period_{i}", "") for i in range(1, 6)}, **{f"away_score{i}": periods.get(f"away_period_{i}", "") for i in range(1, 6)}})


def verify_projected_match(match_id: str, timeout_seconds: int = 120) -> None:
    """Wait for the projector and require the API detail endpoint to expose it."""
    url = f"http://localhost:8082/api/v1/matches/{match_id}"
    deadline = time.monotonic() + timeout_seconds
    last_error = "not projected yet"
    while time.monotonic() < deadline:
        try:
            with urlopen(url, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))
            if payload.get("matchId") == match_id:
                return
            last_error = "API returned a different match"
        except (HTTPError, URLError, OSError, json.JSONDecodeError) as error:
            last_error = str(error)
        time.sleep(2)
    raise RuntimeError(f"Projector/API did not expose {match_id}: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("match_id", help="Exact, case-sensitive Flashscore match ID")
    parser.add_argument("country", help="Lowercase Flashscore country slug")
    parser.add_argument("competition", help="Lowercase Flashscore competition slug")
    parser.add_argument("--attempts", type=int, default=3, choices=range(1, 6))
    parser.add_argument("--timeout-seconds", type=int, default=7200)
    args = parser.parse_args()
    if not MATCH_ID.fullmatch(args.match_id):
        parser.error("match_id must be an alphanumeric Flashscore ID")
    if not SLUG.fullmatch(args.country) or not SLUG.fullmatch(args.competition):
        parser.error("country and competition must be lowercase Flashscore slugs")

    run_dir = DATA_ROOT / "competitions" / args.country / args.competition
    report_dir = DATA_ROOT / "reports" / args.country / args.competition
    report_dir.mkdir(parents=True, exist_ok=True)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")

    # A valid existing bundle is reused.  Otherwise retry only this match;
    # no league-wide extraction is ever triggered by this entrypoint.
    for attempt in range(1, args.attempts + 1):
        if manifest_is_complete(run_dir, args.match_id):
            break
        command(
            sys.executable, str(SCRAPER / "extract_flashscore_match_bundle.py"),
            match_url(args.match_id), "--data-dir", str(run_dir), "--run-id", run_id,
            "--resume",
        )
        if attempt == args.attempts and not manifest_is_complete(run_dir, args.match_id):
            raise RuntimeError(f"The bundle for {args.match_id} is incomplete after {args.attempts} attempts")

    refresh_player_stats(run_dir, args.match_id, args.country, args.competition)

    publish_results_csv(run_dir, args.match_id, args.country, args.competition, run_id)

    # The manifest above validates the target bundle.  Competition-wide validation
    # would incorrectly block this isolated repair on unrelated historic bundles.
    if not manifest_is_complete(run_dir, args.match_id):
        raise RuntimeError("Target bundle became incomplete during player refresh")
    if not CONSOLIDATOR.is_file():
        raise RuntimeError(f"Launcher CSV consolidator not found: {CONSOLIDATOR}")
    staged_match_dir = READY_ROOT / "current" / args.match_id
    command(
        sys.executable, str(CONSOLIDATOR),
        "--input", str(run_dir), "--output", str(READY_ROOT),
        "--match-id", args.match_id,
    )
    command(
        sys.executable, str(SCRAPER / "run_all_csv_batches.py"),
        "--root", str(staged_match_dir), "--launcher-url", "http://localhost:8088",
        "--timeout-seconds", str(args.timeout_seconds),
    )
    # Restrict quarter reconciliation to the match just published.  The
    # backfill tool is intentionally invoked after RESULTS has been ingested.
    command(
        sys.executable, str(SCRAPER / "backfill_results_quarters.py"),
        "--root", str(run_dir), "--match-id", args.match_id,
    )
    verify_projected_match(args.match_id)
    print(json.dumps({"match_id": args.match_id, "state": "complete"}), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
