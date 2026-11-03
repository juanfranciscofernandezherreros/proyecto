"""Extract and import only the requested datasets for one Flashscore match."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
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

def mark_dataset_unavailable(match_id: str, logical: str, attempts: int) -> bool:
    """Registra en la auditoria que Flashscore no publica `logical` para `match_id`.

    Asi la auditoria deja de marcar ese dataset como pendiente y el orquestador no vuelve
    a reabrir el partido en cada arranque. Devuelve True si el registro quedo guardado.
    """
    audit_url = CONFIG.get("AUDIT_URL", "").rstrip("/")
    if not audit_url:
        print(f"[{match_id}] AVISO: AUDIT_URL no configurada; no se pudo registrar {logical} como SIN DATOS.", flush=True)
        return False
    payload = json.dumps({
        "matchId": match_id, "dataset": logical,
        "reason": f"EMPTY_AFTER_{attempts}_ATTEMPTS", "attempts": attempts,
    }).encode("utf-8")
    request = urllib.request.Request(f"{audit_url}/dataset-unavailable", data=payload,
                                     headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            response.read()
        return True
    except (urllib.error.URLError, OSError) as error:
        print(f"[{match_id}] AVISO: no se pudo registrar {logical} como SIN DATOS: {error}", flush=True)
        return False

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
    unavailable: list[str] = []
    for logical in dict.fromkeys(args.datasets):
        dataset, prefix = DATASETS[logical]
        empty_after_retries = False
        for attempt in range(1, 4):
            print(f"[{args.match_id}] extracting {logical} (attempt {attempt}/3)...", flush=True)
            call(str(PYTHON), str(SCRAPER), url, "--data-dir", str(root), "--dataset", dataset)
            if latest_data(match_dir, prefix):
                break
            if attempt == 3:
                empty_after_retries = True
                break
            print(f"[{args.match_id}] {logical} CSV is empty; retrying...", flush=True)
        if empty_after_retries:
            # La fuente no publica este dataset (CSV vacio tras 3 intentos). No es un error
            # del proceso: se marca como SIN DATOS para que la auditoria no lo vuelva a pedir
            # y se continua con el resto de datasets del partido.
            print(f"[{args.match_id}] {logical} SIN DATOS EN LA FUENTE tras 3 intentos; se marca y se omite.", flush=True)
            mark_dataset_unavailable(args.match_id, logical, 3)
            unavailable.append(logical)
            continue
        csv_path = latest_data(match_dir, prefix)
        print(f"[{args.match_id}] consolidating {csv_path.name}...", flush=True)
        call(str(PYTHON), str(CONSOLIDATOR), "--input", str(root), "--output", str(READY), "--match-id", args.match_id, "--prefix", prefix)
        print(f"[{args.match_id}] submitting {logical} to batch launcher...", flush=True)
        call(str(PYTHON), str(SUBMITTER), "--root", str(READY / "current" / args.match_id), "--prefix", prefix, "--launcher-url", CONFIG["LAUNCHER_URL"], "--timeout-seconds", "120")
        print(f"[{args.match_id}] {logical} import completed.", flush=True)
    if unavailable:
        print(f"[{args.match_id}] datasets sin datos en la fuente: {','.join(unavailable)}.", flush=True)
    print(f"[{args.match_id}] all requested datasets completed.", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
