"""Run a complete, resumable competition CSV workflow from this workspace.

The orchestrator keeps the host awake, starts the live CSV watcher, extracts a
competition into the canonical raw directory, audits/retries incomplete files,
and publishes one consolidated CSV run.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from threading import Thread
from pathlib import Path


WORKSPACE = Path(__file__).resolve().parents[1]
SCRAPER = WORKSPACE / "python-pyppeter"
DATA_ROOT = Path(r"C:\data\basketball")
READY_ROOT = Path(r"C:\data\basketball-ready")
ANTIBLOQUEO = WORKSPACE / "scripts" / "arranque" / "MANTENER_DESPIERTO.bat"
WATCHER = WORKSPACE / "scripts" / "monitor" / "watch_csv_imports.bat"
POSTGRES_CONTAINER = "local-validation-postgres-1"
DATABASE_COUNT_QUERY = """
SELECT 'results', count(*) FROM results.results
UNION ALL SELECT 'fixtures', count(*) FROM fixtures.fixtures
UNION ALL SELECT 'match_summary', count(*) FROM match_summary.match_summary
UNION ALL SELECT 'team_stats', count(*) FROM team_stats.team_stats
UNION ALL SELECT 'stats_player', count(*) FROM stats_player.stats_player
UNION ALL SELECT 'point_by_point', count(*) FROM point_by_point.point_by_point_event
ORDER BY 1;
"""


def run(command: list[str], *, cwd: Path) -> None:
    print("+", subprocess.list2cmdline(command), flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def audit(command: list[str]) -> int:
    """Run the read-only audit and return its exact pending-match count."""
    print("+", subprocess.list2cmdline(command), flush=True)
    result = subprocess.run(command, cwd=SCRAPER, text=True, capture_output=True, check=True)
    if result.stdout:
        print(result.stdout, end="", flush=True)
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr, flush=True)
    plan = json.loads(result.stdout)
    return int(plan["match_count"])


def manifest_snapshot(path: Path) -> dict:
    """Summarize the published CSV run without reading whole CSV files."""
    manifest_path = path / "manifest.json"
    if not manifest_path.is_file():
        return {"present": False, "flows": {}}
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    flows = {}
    for entry in manifest.get("files", []):
        if not isinstance(entry, dict) or not entry.get("flow"):
            continue
        flows[str(entry["flow"])] = {
            "rows": int(entry.get("rows", 0)),
            "file": entry.get("path"),
            "sha256": entry.get("sha256"),
        }
    return {"present": True, "run_id": manifest.get("runId"), "created_at": manifest.get("createdAt"), "flows": flows}


def inventory_snapshot(raw_run: Path) -> dict:
    inventories = sorted(raw_run.glob("INVENTORY_*.csv"), key=lambda item: item.stat().st_mtime_ns)
    if not inventories:
        return {"present": False, "matches": 0, "statuses": {}}
    statuses: dict[str, int] = {}
    match_ids: set[str] = set()
    with inventories[-1].open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            status = (row.get("status") or "unknown").strip() or "unknown"
            statuses[status] = statuses.get(status, 0) + 1
            if row.get("match_id"):
                match_ids.add(row["match_id"])
    return {"present": True, "inventory": inventories[-1].name, "matches": len(match_ids), "statuses": statuses}


def write_audit(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".json.partial")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def database_snapshot() -> dict[str, int]:
    """Return global PostgreSQL table counts using a read-only query."""
    command = [
        "docker", "exec", POSTGRES_CONTAINER, "psql", "-U", "test", "-d", "basketball",
        "-At", "-F", "|", "-c", DATABASE_COUNT_QUERY,
    ]
    result = subprocess.run(command, text=True, capture_output=True, check=True)
    counts: dict[str, int] = {}
    for line in result.stdout.splitlines():
        name, separator, value = line.partition("|")
        if not separator or not name or not value.isdigit():
            raise RuntimeError(f"Invalid PostgreSQL audit output: {line!r}")
        counts[name] = int(value)
    expected = {"results", "fixtures", "match_summary", "team_stats", "stats_player", "point_by_point"}
    if set(counts) != expected:
        raise RuntimeError("PostgreSQL audit did not return every required table")
    return counts


def start_monitor(script: Path, label: str, *, relay_output: bool = False) -> subprocess.Popen[str]:
    if not script.is_file():
        raise FileNotFoundError(f"{label} not found: {script}")
    process = subprocess.Popen(
        ["cmd.exe", "/c", str(script)],
        text=relay_output,
        stdout=subprocess.PIPE if relay_output else None,
        stderr=subprocess.STDOUT if relay_output else None,
    )
    print(f"{label} started (PID {process.pid})", flush=True)
    if relay_output and process.stdout:
        def relay() -> None:
            for line in process.stdout:
                print(f"[{label}] {line.rstrip()}", flush=True)
        Thread(target=relay, name=f"{label}-output", daemon=True).start()
    return process


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", help="Flashscore competition URL")
    parser.add_argument("--country", required=True, help="Lowercase country slug, e.g. germany")
    parser.add_argument("--competition", required=True, help="Lowercase competition slug, e.g. bbl")
    parser.add_argument("--workers", type=int, choices=(1, 2, 3), default=2)
    parser.add_argument("--resume", action="store_true", help="Resume the canonical raw competition directory")
    parser.add_argument("--recover-attempts", type=int, default=3)
    parser.add_argument("--retry-forever", action="store_true", help="Retry the whole CSV workflow until audit is complete")
    parser.add_argument("--retry-delay", type=int, default=60, help="Seconds between persistent retries")
    parser.add_argument("--no-monitors", action="store_true", help="Do not start antibloqueo or watcher")
    parser.add_argument("--skip-extract", action="store_true", help="Use an existing raw run")
    parser.add_argument("--no-db-audit", action="store_true", help="Skip read-only PostgreSQL table counts")
    args = parser.parse_args()
    if args.recover_attempts < 1 or args.retry_delay < 1:
        parser.error("Recovery attempts and retry delay must be positive")
    if args.country != args.country.lower() or args.competition != args.competition.lower():
        parser.error("--country and --competition must be lowercase slugs")

    raw_country = DATA_ROOT / "competitions" / args.country
    raw_run = raw_country / args.competition
    report_dir = DATA_ROOT / "reports" / args.country / args.competition
    audit_path = report_dir / f"csv-audit-{datetime.now(timezone.utc):%Y%m%d%H%M%S}.json"
    audit_report = {
        "started_at": datetime.now(timezone.utc).isoformat(),
        "competition": {"country": args.country, "slug": args.competition, "url": args.url},
        "before_ready": manifest_snapshot(READY_ROOT / "current"),
        "status": "running",
    }
    if not args.no_db_audit:
        audit_report["database_before"] = database_snapshot()
    write_audit(audit_path, audit_report)
    monitors: list[subprocess.Popen[str]] = []
    try:
        if not args.no_monitors:
            monitors.append(start_monitor(ANTIBLOQUEO, "antibloqueo"))
            monitors.append(start_monitor(WATCHER, "watcher", relay_output=True))
        attempt = 0
        while True:
            attempt += 1
            try:
                if not args.skip_extract:
                    command = [sys.executable, str(SCRAPER / "extract_competition_all.py"), args.url,
                               "--data-dir", str(raw_country), "--workers", str(args.workers)]
                    if (args.resume or raw_run.exists()) and (raw_run / "run.json").is_file():
                        command += ["--resume", str(raw_run)]
                    run(command, cwd=SCRAPER)
                if not raw_run.is_dir():
                    raise FileNotFoundError(f"Raw competition directory not found: {raw_run}")

                audit_command = [sys.executable, str(SCRAPER / "recover_incomplete_csv.py"), str(raw_run)]
                pending = audit(audit_command)
                if pending:
                    run(audit_command + ["--execute", "--attempts", str(args.recover_attempts)], cwd=SCRAPER)
                    pending = audit(audit_command)
                if pending:
                    raise RuntimeError(f"Audit still has {pending} pending matches")

                run([sys.executable, str(SCRAPER / "consolidate_csv.py"), "--input", str(raw_run),
                     "--output", str(READY_ROOT)], cwd=SCRAPER)
                after_ready = manifest_snapshot(READY_ROOT / "current")
                before_flows = audit_report["before_ready"]["flows"]
                differences = {
                    flow: details["rows"] - int(before_flows.get(flow, {}).get("rows", 0))
                    for flow, details in after_ready["flows"].items()
                }
                audit_report.update({
                    "finished_at": datetime.now(timezone.utc).isoformat(),
                    "status": "complete",
                    "pending_matches": 0,
                    "inventory": inventory_snapshot(raw_run),
                    "after_ready": after_ready,
                    "row_difference_from_previous_ready": differences,
                })
                if not args.no_db_audit:
                    database_after = database_snapshot()
                    audit_report["database_after"] = database_after
                    audit_report["database_difference"] = {
                        table: database_after[table] - audit_report["database_before"][table]
                        for table in database_after
                    }
                write_audit(audit_path, audit_report)
                print("CSV workflow complete: " + str(READY_ROOT / "current"), flush=True)
                print("CSV audit: " + str(audit_path), flush=True)
                return 0
            except (subprocess.CalledProcessError, OSError, RuntimeError, json.JSONDecodeError) as error:
                audit_report.update({
                    "last_error": str(error),
                    "inventory": inventory_snapshot(raw_run) if raw_run.is_dir() else {"present": False},
                })
                write_audit(audit_path, audit_report)
                if not args.retry_forever:
                    raise
                print(f"Attempt {attempt} incomplete: {error}. Retrying in {args.retry_delay}s.", file=sys.stderr, flush=True)
                time.sleep(args.retry_delay)
    finally:
        failed = [str(process.pid) for process in monitors if process.poll() is not None]
        if failed:
            print("A monitor exited unexpectedly: " + ", ".join(failed), file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
