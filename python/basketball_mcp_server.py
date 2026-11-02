"""Local MCP server for the canonical Basketball CSV pipeline.

The server is deliberately stdio-only and constrains filesystem and database
access to the paths and PostgreSQL instance mandated by AGENTS.md.
"""

from __future__ import annotations

import csv
import io
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from proyecto_config import CONFIG, path
from typing import Any

from mcp.server.fastmcp import FastMCP


WORKSPACE = Path(__file__).resolve().parents[1]
SCRAPER = WORKSPACE / "python-pyppeter"
DATA_ROOT = path("DATA_DIR")
READY_ROOT = path("READY_DIR")
REPORTS_ROOT = DATA_ROOT / "reports"
ANTIBLOQUEO = WORKSPACE / "scripts" / "arranque" / "MANTENER_DESPIERTO.bat"
WATCHER = WORKSPACE / "scripts" / "monitor" / "watch_csv_imports.bat"
SLUG = re.compile(r"^[a-z0-9][a-z0-9-]*$")
READ_ONLY_SQL = re.compile(r"^\s*(select|with|explain)\b", re.IGNORECASE)

mcp = FastMCP(
    "basketball-operations",
    instructions=(
        "Operate only the canonical Basketball CSV paths. Start and verify "
        "antibloqueo plus the visible CSV watcher before extraction. Use "
        "read-only database queries unless a separate persistence tool is used. "
        "For the full EuroLeague match-table snapshot, use get_euroleague_all_tables."
    ),
)


def _slug(value: str, label: str) -> str:
    if not SLUG.fullmatch(value):
        raise ValueError(f"{label} must be a lowercase Flashscore slug")
    return value


def _run_dir(country: str, competition: str) -> Path:
    return DATA_ROOT / "competitions" / _slug(country, "country") / _slug(competition, "competition")


def _report_dir(country: str, competition: str) -> Path:
    return REPORTS_ROOT / _slug(country, "country") / _slug(competition, "competition")


def _json_file(path: Path) -> Any | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _latest_selection(country: str, competition: str, selection_name: str) -> tuple[Path, dict[str, Any]] | None:
    report_dir = _report_dir(country, competition)
    selections = sorted(
        (path for path in report_dir.glob(f"{selection_name}-*.json") if not path.name.endswith(".raw.json")),
        key=lambda path: path.stat().st_mtime_ns,
    )
    if not selections:
        return None
    selection = _json_file(selections[-1])
    return (selections[-1], selection) if isinstance(selection, dict) else None


def _tail(path: Path, lines: int) -> list[str]:
    if not path.is_file():
        return []
    return path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:]


def _start(command: list[str], log_path: Path) -> dict[str, Any]:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    handle = log_path.open("a", encoding="utf-8")
    process = subprocess.Popen(command, cwd=WORKSPACE, stdout=handle, stderr=subprocess.STDOUT)
    return {"pid": process.pid, "log": str(log_path), "command": subprocess.list2cmdline(command)}


@mcp.tool()
def watcher_status() -> dict[str, Any]:
    """Report whether the required anti-lock and visible CSV watcher are running."""
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", "Get-CimInstance Win32_Process | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"],
        text=True, capture_output=True, check=True,
    )
    processes = json.loads(result.stdout or "[]")
    if isinstance(processes, dict):
        processes = [processes]
    return {
        "antibloqueo": any("MANTENER_DESPIERTO.bat" in (item.get("CommandLine") or "") for item in processes),
        "watcher": any("watch_csv_imports.bat" in (item.get("CommandLine") or "") for item in processes),
    }


@mcp.tool()
def open_csv_watcher() -> dict[str, Any]:
    """Open the required watcher in a visible console window and start anti-lock hidden."""
    if not ANTIBLOQUEO.is_file() or not WATCHER.is_file():
        raise FileNotFoundError("Required BAT files were not found")
    flags = getattr(subprocess, "CREATE_NEW_CONSOLE", 0)
    anti = subprocess.Popen(["cmd.exe", "/c", str(ANTIBLOQUEO)], creationflags=subprocess.CREATE_NO_WINDOW)
    watcher = subprocess.Popen(["cmd.exe", "/k", str(WATCHER)], creationflags=flags)
    return {"antibloqueo_pid": anti.pid, "watcher_pid": watcher.pid, "watcher_visible": True}


@mcp.tool()
def open_competition_status_watcher(country: str, competition: str, selection_name: str = "last-results") -> dict[str, Any]:
    """Open a visible console showing missing CSV datasets for the latest selected matches."""
    if selection_name not in ("last-results", "last-round", "last-game-day"):
        raise ValueError("Unsupported selection_name")
    command = ["cmd.exe", "/k", sys.executable, "-u", str(WORKSPACE / "python" / "competition_progress_console.py"), country, competition]
    flags = getattr(subprocess, "CREATE_NEW_CONSOLE", 0)
    process = subprocess.Popen(command, cwd=WORKSPACE, creationflags=flags)
    return {"pid": process.pid, "visible": True, "command": subprocess.list2cmdline(command)}


@mcp.tool()
def get_extraction_status(country: str, competition: str) -> dict[str, Any]:
    """Summarize completed bundles, incomplete manifests, latest CSV activity and logs."""
    run_dir = _run_dir(country, competition)
    report_dir = _report_dir(country, competition)
    matches = []
    for directory in sorted((item for item in run_dir.glob("*") if item.is_dir()), key=lambda item: item.name):
        manifest = _json_file(directory / "manifest.json")
        csvs = sorted(path.name for path in directory.glob("*.csv"))
        matches.append({"match_id": directory.name, "complete": bool(manifest and not manifest.get("failures")), "csv_count": len(csvs)})
    return {
        "run_dir": str(run_dir), "report_dir": str(report_dir),
        "completed_matches": sum(1 for item in matches if item["complete"]),
        "observed_matches": len(matches), "matches": matches,
        "latest_log": _tail(report_dir / "extract-15.out.log", 30),
        "latest_errors": _tail(report_dir / "extract-15.err.log", 20),
        "watcher": watcher_status(),
    }


@mcp.tool()
def tail_extraction_log(country: str, competition: str, lines: int = 50) -> dict[str, Any]:
    """Return the tail of the extraction and error logs without opening a terminal."""
    if not 1 <= lines <= 500:
        raise ValueError("lines must be between 1 and 500")
    report_dir = _report_dir(country, competition)
    return {"output": _tail(report_dir / "extract-15.out.log", lines), "errors": _tail(report_dir / "extract-15.err.log", lines)}


@mcp.tool()
def list_csv_artifacts(country: str, competition: str, match_id: str | None = None) -> list[dict[str, Any]]:
    """List final CSV artifacts, sizes and modification times for one run or match."""
    root = _run_dir(country, competition)
    if match_id:
        if not re.fullmatch(r"[A-Za-z0-9]+", match_id):
            raise ValueError("Invalid match_id")
        root = root / match_id
    return [
        {"path": str(path), "bytes": path.stat().st_size, "modified_at": datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()}
        for path in sorted(root.rglob("*.csv"))
    ]


@mcp.tool()
def start_competition_extraction(url: str, country: str, competition: str, workers: int = 2, resume: bool = True) -> dict[str, Any]:
    """Start a resumable canonical competition extraction in the background."""
    if workers not in (1, 2, 3) or not url.startswith(("https://www.flashscore.com/", "https://www.flashscore.es/")):
        raise ValueError("Use a Flashscore URL and 1-3 workers")
    report_dir = _report_dir(country, competition)
    command = [sys.executable, str(WORKSPACE / "python" / "orchestrate_competition.py"), url, "--country", country, "--competition", competition, "--workers", str(workers), "--retry-forever"]
    if resume:
        command.append("--resume")
    return _start(command, report_dir / "mcp-extraction.log")


@mcp.tool()
def start_liga_endesa_last_results(matches: int = 10, workers: int = 3, resume: bool = True, attempts: int = 3) -> dict[str, Any]:
    """Extract, automatically recover, and persist status for 10 or 15 Liga Endesa bundles."""
    if matches not in (10, 15) or workers not in (1, 2, 3) or not 1 <= attempts <= 5:
        raise ValueError("matches must be 10 or 15; workers and attempts must be 1-3 and 1-5")
    monitors = watcher_status()
    if not monitors["antibloqueo"] or not monitors["watcher"]:
        monitors = open_csv_watcher()
    report_dir = _report_dir("spain", "acb")
    command = [sys.executable, str(WORKSPACE / "python" / "liga_endesa_last_results.py"), "--matches", str(matches), "--workers", str(workers), "--attempts", str(attempts)]
    if resume:
        command.append("--resume")
    status_watcher = open_competition_status_watcher("spain", "acb")
    return {"monitors": monitors, "status_watcher": status_watcher, **_start(command, report_dir / "mcp-liga-endesa-last-results.log")}


@mcp.tool()
def recover_liga_endesa_last_results(workers: int = 3, attempts: int = 3) -> dict[str, Any]:
    """Recover only missing CSV datasets from the latest Liga Endesa 10/15-match selection."""
    if workers not in (1, 2, 3) or not 1 <= attempts <= 5:
        raise ValueError("workers must be 1-3 and attempts must be 1-5")
    monitors = watcher_status()
    if not monitors["antibloqueo"] or not monitors["watcher"]:
        monitors = open_csv_watcher()
    report_dir = _report_dir("spain", "acb")
    command = [sys.executable, str(WORKSPACE / "python" / "liga_endesa_last_results.py"), "--recover", "--workers", str(workers), "--attempts", str(attempts)]
    return {"monitors": monitors, **_start(command, report_dir / "mcp-liga-endesa-recovery.log")}


@mcp.tool()
def get_liga_endesa_last_results_status() -> dict[str, Any]:
    """Return the exact completion state of the latest 10/15-match Liga Endesa selection."""
    latest = _latest_selection("spain", "acb", "last-results")
    if not latest:
        return {"found": False}
    path, selection = latest
    return {
        "found": True, "manifest": str(path), "run_id": selection.get("run_id"),
        "state": selection.get("state", "unknown"), "match_count": selection.get("match_count"),
        "complete_matches": selection.get("match_count", 0) - len(selection.get("failed_match_ids", [])),
        "failed_match_ids": selection.get("failed_match_ids", []),
        "missing_datasets": selection.get("missing_datasets", {}),
    }


@mcp.tool()
def start_lnb_last_results(matches: int = 10, workers: int = 3, resume: bool = True, attempts: int = 3) -> dict[str, Any]:
    """Extract, automatically recover, and persist status for 10 or 15 French LNB bundles."""
    if matches not in (10, 15) or workers not in (1, 2, 3) or not 1 <= attempts <= 5:
        raise ValueError("matches must be 10 or 15; workers and attempts must be 1-3 and 1-5")
    monitors = watcher_status()
    if not monitors["antibloqueo"] or not monitors["watcher"]:
        monitors = open_csv_watcher()
    report_dir = _report_dir("france", "lnb")
    command = [sys.executable, str(WORKSPACE / "python" / "lnb_last_results.py"), "--matches", str(matches), "--workers", str(workers), "--attempts", str(attempts)]
    if resume:
        command.append("--resume")
    status_watcher = open_competition_status_watcher("france", "lnb")
    return {"monitors": monitors, "status_watcher": status_watcher, **_start(command, report_dir / "mcp-lnb-last-results.log")}


@mcp.tool()
def recover_lnb_last_results(workers: int = 3, attempts: int = 3) -> dict[str, Any]:
    """Automatically retry only missing CSV datasets from the latest French LNB selection."""
    if workers not in (1, 2, 3) or not 1 <= attempts <= 5:
        raise ValueError("workers must be 1-3 and attempts must be 1-5")
    monitors = watcher_status()
    if not monitors["antibloqueo"] or not monitors["watcher"]:
        monitors = open_csv_watcher()
    report_dir = _report_dir("france", "lnb")
    command = [sys.executable, str(WORKSPACE / "python" / "lnb_last_results.py"), "--recover", "--workers", str(workers), "--attempts", str(attempts)]
    return {"monitors": monitors, **_start(command, report_dir / "mcp-lnb-recovery.log")}


@mcp.tool()
def get_lnb_last_results_status() -> dict[str, Any]:
    """Return the exact completion state of the latest 10/15-match French LNB selection."""
    latest = _latest_selection("france", "lnb", "last-results")
    if not latest:
        return {"found": False}
    path, selection = latest
    return {
        "found": True, "manifest": str(path), "run_id": selection.get("run_id"),
        "state": selection.get("state", "unknown"), "match_count": selection.get("match_count"),
        "complete_matches": selection.get("match_count", 0) - len(selection.get("failed_match_ids", [])),
        "failed_match_ids": selection.get("failed_match_ids", []),
        "missing_datasets": selection.get("missing_datasets", {}),
    }


@mcp.tool()
def start_lega_a_last_results(matches: int = 10, workers: int = 3, resume: bool = True, attempts: int = 3) -> dict[str, Any]:
    """Extract, automatically recover, and persist status for 10 or 15 Italian Lega A bundles."""
    if matches not in (10, 15) or workers not in (1, 2, 3) or not 1 <= attempts <= 5:
        raise ValueError("matches must be 10 or 15; workers and attempts must be 1-3 and 1-5")
    monitors = watcher_status()
    if not monitors["antibloqueo"] or not monitors["watcher"]:
        monitors = open_csv_watcher()
    report_dir = _report_dir("italy", "lega-a")
    command = [sys.executable, str(WORKSPACE / "python" / "lega_a_last_results.py"), "--matches", str(matches), "--workers", str(workers), "--attempts", str(attempts)]
    if resume:
        command.append("--resume")
    status_watcher = open_competition_status_watcher("italy", "lega-a")
    return {"monitors": monitors, "status_watcher": status_watcher, **_start(command, report_dir / "mcp-lega-a-last-results.log")}


@mcp.tool()
def recover_lega_a_last_results(workers: int = 3, attempts: int = 3) -> dict[str, Any]:
    """Automatically retry only missing CSV datasets from the latest Italian Lega A selection."""
    if workers not in (1, 2, 3) or not 1 <= attempts <= 5:
        raise ValueError("workers must be 1-3 and attempts must be 1-5")
    monitors = watcher_status()
    if not monitors["antibloqueo"] or not monitors["watcher"]:
        monitors = open_csv_watcher()
    report_dir = _report_dir("italy", "lega-a")
    command = [sys.executable, str(WORKSPACE / "python" / "lega_a_last_results.py"), "--recover", "--workers", str(workers), "--attempts", str(attempts)]
    return {"monitors": monitors, **_start(command, report_dir / "mcp-lega-a-recovery.log")}


@mcp.tool()
def get_lega_a_last_results_status() -> dict[str, Any]:
    """Return the exact completion state of the latest 10/15-match Italian Lega A selection."""
    latest = _latest_selection("italy", "lega-a", "last-results")
    if not latest:
        return {"found": False}
    path, selection = latest
    return {
        "found": True, "manifest": str(path), "run_id": selection.get("run_id"),
        "state": selection.get("state", "unknown"), "match_count": selection.get("match_count"),
        "complete_matches": selection.get("match_count", 0) - len(selection.get("failed_match_ids", [])),
        "failed_match_ids": selection.get("failed_match_ids", []),
        "missing_datasets": selection.get("missing_datasets", {}),
    }


@mcp.tool()
def start_euroleague_last_round(matches: int = 10, workers: int = 3, resume: bool = True, attempts: int = 3) -> dict[str, Any]:
    """Extract the newest completed EuroLeague results and complete CSV bundles in the background."""
    if not 1 <= matches <= 30 or workers not in (1, 2, 3) or not 1 <= attempts <= 5:
        raise ValueError("matches must be 1-30; workers and attempts must be 1-3 and 1-5")
    monitors = watcher_status()
    if not monitors["antibloqueo"] or not monitors["watcher"]:
        monitors = open_csv_watcher()
    report_dir = _report_dir("europe", "euroleague")
    command = [sys.executable, str(WORKSPACE / "python" / "euroliga_last_round.py"), "--matches", str(matches), "--workers", str(workers), "--attempts", str(attempts)]
    if resume:
        command.append("--resume")
    status_watcher = open_competition_status_watcher("europe", "euroleague", "last-round")
    return {"monitors": monitors, "status_watcher": status_watcher, **_start(command, report_dir / "mcp-euroleague-last-round.log")}


@mcp.tool()
def recover_euroleague_last_round(workers: int = 3, attempts: int = 3) -> dict[str, Any]:
    """Recover only missing CSV datasets from the most recent EuroLeague last-round MCP selection."""
    if workers not in (1, 2, 3) or not 1 <= attempts <= 5:
        raise ValueError("workers must be 1-3 and attempts must be 1-5")
    report_dir = _report_dir("europe", "euroleague")
    command = [sys.executable, str(WORKSPACE / "python" / "euroliga_last_round.py"), "--recover", "--workers", str(workers), "--attempts", str(attempts)]
    return _start(command, report_dir / "mcp-euroleague-recovery.log")


@mcp.tool()
def start_nba_last_game_day(workers: int = 3, resume: bool = True) -> dict[str, Any]:
    """Extract every finished NBA game from Flashscore's latest game date with complete CSV bundles."""
    if workers not in (1, 2, 3):
        raise ValueError("workers must be 1, 2, or 3")
    monitors = watcher_status()
    if not monitors["antibloqueo"] or not monitors["watcher"]:
        monitors = open_csv_watcher()
    report_dir = _report_dir("usa", "nba")
    command = [sys.executable, str(WORKSPACE / "python" / "nba_last_game_day.py"), "--workers", str(workers)]
    if resume:
        command.append("--resume")
    return {"monitors": monitors, **_start(command, report_dir / "mcp-nba-last-game-day.log")}


@mcp.tool()
def recover_nba_last_game_day(workers: int = 3) -> dict[str, Any]:
    """Recover only missing CSV datasets from the most recent NBA MCP game-day selection."""
    if workers not in (1, 2, 3):
        raise ValueError("workers must be 1, 2, or 3")
    report_dir = _report_dir("usa", "nba")
    return _start([sys.executable, str(WORKSPACE / "python" / "nba_last_game_day.py"), "--recover", "--workers", str(workers)], report_dir / "mcp-nba-recovery.log")


@mcp.tool()
def recover_incomplete_csv(country: str, competition: str, execute: bool = False, attempts: int = 3) -> dict[str, Any]:
    """Audit a run, or launch targeted recovery of missing/invalid match CSVs."""
    if not 1 <= attempts <= 5:
        raise ValueError("attempts must be between 1 and 5")
    run_dir, report_dir = _run_dir(country, competition), _report_dir(country, competition)
    command = [sys.executable, str(SCRAPER / "recover_incomplete_csv.py"), str(run_dir)]
    if execute:
        command += ["--execute", "--attempts", str(attempts)]
        return {"started": True, **_start(command, report_dir / "mcp-recovery.log")}
    completed = subprocess.run(command, cwd=SCRAPER, text=True, capture_output=True, check=False)
    return {"started": False, "returncode": completed.returncode, "plan": json.loads(completed.stdout)}


@mcp.tool()
def validate_competition_run(country: str, competition: str) -> dict[str, Any]:
    """Validate CSV contracts and manifests for a canonical competition run."""
    run_dir = _run_dir(country, competition)
    completed = subprocess.run([sys.executable, str(SCRAPER / "validate_run.py"), "--json", str(run_dir)], cwd=SCRAPER, text=True, capture_output=True, check=False)
    return {"returncode": completed.returncode, "report": json.loads(completed.stdout)}


@mcp.tool()
def consolidate_competition(country: str, competition: str) -> dict[str, Any]:
    """Publish one validated run to the sole launcher-ready directory, basketball-ready/current."""
    run_dir, report_dir = _run_dir(country, competition), _report_dir(country, competition)
    return _start([sys.executable, str(SCRAPER / "consolidate_csv.py"), "--input", str(run_dir), "--output", str(READY_ROOT.parent)], report_dir / "mcp-consolidate.log")


@mcp.tool()
def run_batch_ingestion(timeout_seconds: int = 3600) -> dict[str, Any]:
    """Start batch ingestion from basketball-ready/current in its mandatory dataset order."""
    if not 60 <= timeout_seconds <= 14400:
        raise ValueError("timeout_seconds must be between 60 and 14400")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    return _start([sys.executable, str(SCRAPER / "run_all_csv_batches.py"), "--root", str(READY_ROOT), "--launcher-url", CONFIG["LAUNCHER_URL"], "--timeout-seconds", str(timeout_seconds)], REPORTS_ROOT / "batch" / f"mcp-batch-{stamp}.log")


@mcp.tool()
def query_postgres(sql: str) -> dict[str, Any]:
    """Execute one read-only SELECT/WITH/EXPLAIN query against basketball on localhost:55432."""
    if not READ_ONLY_SQL.match(sql) or ";" in sql.rstrip().rstrip(";"):
        raise ValueError("Only one read-only SELECT, WITH, or EXPLAIN statement is permitted")
    command = ["docker", "exec", CONFIG["POSTGRES_CONTAINER"], "psql", "-U", CONFIG["DB_USER"], "-d", CONFIG["DB_NAME"], "-v", "ON_ERROR_STOP=1", "-P", "pager=off", "-c", f"SET TRANSACTION READ ONLY; {sql}"]
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    return {"returncode": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}


@mcp.tool()
def get_euroleague_all_tables() -> dict[str, Any]:
    """Run the one-query EuroLeague join across fixtures, results, team_stats, stats_player, match_summary and point_by_point. Export every returned field and child row to a JSON snapshot; this is read-only and preserves source values as stored."""
    query_path = WORKSPACE / "sql" / "euroleague_all_tables.sql"
    if not query_path.is_file():
        raise FileNotFoundError(f"The canonical query file is missing: {query_path}")
    query = query_path.read_text(encoding="utf-8")
    command = [
        "docker", "exec", CONFIG["POSTGRES_CONTAINER"], "psql",
        "-X", "-U", CONFIG["DB_USER"], "-d", CONFIG["DB_NAME"], "--csv", "-v",
        "ON_ERROR_STOP=1", "-c", query,
    ]
    completed = subprocess.run(
        command, text=True, encoding="utf-8", capture_output=True, check=False
    )
    if completed.returncode != 0:
        raise RuntimeError(f"EuroLeague query failed: {completed.stderr.strip()}")

    reader = csv.DictReader(io.StringIO(completed.stdout))
    nested_columns = (
        "fixtures", "results", "team_stats", "stats_player",
        "match_summary", "point_by_point",
    )
    count_columns = (
        "fixture_rows", "result_rows", "team_stats_rows", "stats_player_rows",
        "match_summary_rows", "point_by_point_rows",
    )
    matches: list[dict[str, Any]] = []
    for raw_row in reader:
        row: dict[str, Any] = dict(raw_row)
        for column in nested_columns:
            row[column] = json.loads(row[column] or "[]")
        for column in count_columns:
            row[column] = int(row[column] or 0)
        matches.append(row)

    if not matches:
        raise RuntimeError("The EuroLeague query returned no fixture or result rows")

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    report_dir = REPORTS_ROOT / "europe" / "euroleague"
    report_dir.mkdir(parents=True, exist_ok=True)
    output_path = report_dir / f"all-tables-{stamp}.json"
    snapshot = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "database": "basketball",
        "competition": "EuroLeague",
        "query_file": str(query_path),
        "match_count": len(matches),
        "table_row_counts": {
            column.removesuffix("_rows"): sum(row[column] for row in matches)
            for column in count_columns
        },
        "matches": matches,
    }
    output_path.write_text(
        json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    preview = [
        {
            "match_id": row["match_id"],
            "event_datetime": row["event_datetime"],
            "home_team": row["home_team"],
            "away_team": row["away_team"],
            "rows": {column.removesuffix("_rows"): row[column] for column in count_columns},
        }
        for row in matches[:10]
    ]
    return {
        "query_executed": True,
        "read_only": True,
        "match_count": len(matches),
        "table_row_counts": snapshot["table_row_counts"],
        "json_snapshot": str(output_path),
        "query_file": str(query_path),
        "preview_first_10": preview,
        "note": "All child-table rows are included in the JSON arrays. Source values are preserved without correction.",
    }


@mcp.tool()
def runtime_services_status() -> dict[str, Any]:
    """Report local PostgreSQL, MongoDB, projector, API and batch-launcher availability."""
    completed = subprocess.run(["docker", "ps", "--format", "{{.Names}}|{{.Status}}"], text=True, capture_output=True, check=True)
    services = [line.split("|", 1) for line in completed.stdout.splitlines() if "|" in line]
    try:
        launcher = subprocess.run(["powershell.exe", "-NoProfile", "-Command", f"(Invoke-WebRequest -UseBasicParsing {CONFIG['LAUNCHER_URL']} -TimeoutSec 3).StatusCode"], text=True, capture_output=True, timeout=5).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        launcher = False
    return {"containers": [{"name": name, "status": status} for name, status in services], "batch_launcher_reachable": launcher}


@mcp.tool()
def start_runtime_services() -> dict[str, Any]:
    """Start PostgreSQL, MongoDB, projector, API and web services through local-validation compose."""
    command = ["docker", "compose", "-f", str(WORKSPACE / "local-validation" / "docker-compose.yml"), "up", "-d", "postgres", "mongo", "basketball-match-projector", "basketball-match-api", "basketball-match-web"]
    completed = subprocess.run(command, cwd=WORKSPACE, text=True, capture_output=True, check=True)
    return {"started": True, "output": completed.stdout, "status": runtime_services_status()}


@mcp.tool()
def start_batch_launcher() -> dict[str, Any]:
    """Start the host batch launcher with Java 21 and canonical PostgreSQL/JAR configuration."""
    java = path("JAVA_EXE")
    if not java.is_file():
        raise FileNotFoundError("Java 21 is required for csv-batch-launcher")
    jars = {
        "RESULTS_BATCH_JAR": WORKSPACE / "csv-extra-batch" / "results" / "target" / "csv-results-batch.jar",
        "FIXTURES_BATCH_JAR": WORKSPACE / "csv-extra-batch" / "fixtures" / "target" / "csv-fixtures-batch.jar",
        "TEAM_STATS_BATCH_JAR": WORKSPACE / "csv-extra-batch" / "team-stats" / "target" / "csv-team-stats-batch.jar",
        "MATCH_STATS_BATCH_JAR": WORKSPACE / "csv-extra-batch" / "match-summary" / "target" / "csv-stats-match-batch.jar",
        "PLAYER_STATS_BATCH_JAR": WORKSPACE / "csv-extra-batch" / "stats-player" / "target" / "csv-stats-player-batch.jar",
        "POINT_BY_POINT_BATCH_JAR": WORKSPACE / "csv-extra-batch" / "point-by-point" / "target" / "csv-point-by-point-batch.jar",
        "EXTRA_BATCH_JAR": WORKSPACE / "csv-extra-batch" / "extra-importer" / "target" / "csv-extra-importer-batch.jar",
    }
    if any(not path.is_file() for path in jars.values()):
        raise FileNotFoundError("One or more batch JARs are missing")
    environment = os.environ | {"DB_URL": CONFIG["DB_URL"], "DB_USER": CONFIG["DB_USER"], "DB_PASS": CONFIG["DB_PASS"], "BATCH_DB_URL": CONFIG["DB_URL"], "BATCH_DB_USER": CONFIG["DB_USER"], "BATCH_DB_PASS": CONFIG["DB_PASS"], "CSV_ALLOWED_ROOT": CONFIG["READY_ROOT"], **{name: str(path) for name, path in jars.items()}}
    log = REPORTS_ROOT / "batch-launcher-mcp.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    handle = log.open("a", encoding="utf-8")
    process = subprocess.Popen([str(java), "-jar", str(WORKSPACE / "csv-extra-batch" / "launcher" / "target" / "csv-batch-launcher.jar")], cwd=WORKSPACE / "csv-extra-batch" / "launcher", stdout=handle, stderr=subprocess.STDOUT, env=environment)
    return {"pid": process.pid, "log": str(log)}


@mcp.tool()
def start_competition_batch(country: str, competition: str) -> dict[str, Any]:
    """Consolidate one canonical competition run then submit its CSVs in mandatory batch order."""
    report_dir = _report_dir(country, competition)
    return _start([sys.executable, str(WORKSPACE / "python" / "ingest_competition_batch.py"), country, competition], report_dir / "mcp-batch-ingestion.log")


@mcp.tool()
def start_match_pipeline(match_id: str, country: str, competition: str, attempts: int = 3, timeout_seconds: int = 7200) -> dict[str, Any]:
    """Extract, validate, consolidate, batch-ingest and reconcile one match ID.

    The match ID is case-sensitive.  The operation resolves its Flashscore URL
    itself, never starts a league-wide extraction, and publishes only this
    match to the canonical launcher-ready directory.
    """
    if not re.fullmatch(r"[A-Za-z0-9]+", match_id):
        raise ValueError("match_id must be an alphanumeric Flashscore ID")
    _slug(country, "country")
    _slug(competition, "competition")
    if not 1 <= attempts <= 5 or not 60 <= timeout_seconds <= 14400:
        raise ValueError("attempts must be 1-5 and timeout_seconds must be 60-14400")
    monitors = watcher_status()
    if not monitors["antibloqueo"] or not monitors["watcher"]:
        monitors = open_csv_watcher()

    # A match pipeline is self-contained: persistence, projection and the
    # launcher must be ready before CSV processing starts.  Compose is
    # idempotent, so this also safely handles the second through 105th match.
    services = start_runtime_services()
    if not runtime_services_status()["batch_launcher_reachable"]:
        # The launcher is a host process rather than a compose service.
        start_batch_launcher()
    launcher_deadline = time.monotonic() + 45
    while time.monotonic() < launcher_deadline:
        if runtime_services_status()["batch_launcher_reachable"]:
            break
        time.sleep(2)
    else:
        raise RuntimeError("The CSV batch launcher did not become reachable")

    report_dir = _report_dir(country, competition)
    command = [
        sys.executable, str(WORKSPACE / "python" / "run_match_pipeline.py"), match_id,
        country, competition, "--attempts", str(attempts),
        "--timeout-seconds", str(timeout_seconds),
    ]
    return {
        "match_id": match_id,
        "monitors": monitors,
        "runtime_services": services["status"],
        "batch_launcher_ready": True,
        "scope": "single_match",
        **_start(command, report_dir / f"mcp-match-pipeline-{match_id}.log"),
    }


if __name__ == "__main__":
    mcp.run(transport="stdio")
