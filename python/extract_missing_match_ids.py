"""Launch resumable Flashscore bundles for a plain list of match URLs."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRAPER = ROOT / "python-pyppeter" / "extract_flashscore_match_bundle.py"
MATCH_ID = re.compile(r"/match/([A-Za-z0-9]+)/")


def run(url: str, data_dir: Path, logs_dir: Path) -> tuple[str, int]:
    match = MATCH_ID.search(url)
    if not match:
        return url, 2
    match_id = match.group(1)
    log = logs_dir / f"{match_id}.log"
    command = [sys.executable, str(SCRAPER), url, "--data-dir", str(data_dir), "--resume"]
    with log.open("w", encoding="utf-8") as handle:
        handle.write(f"started_at_utc={datetime.now(timezone.utc).isoformat()}\nurl={url}\n\n")
        completed = subprocess.run(command, cwd=SCRAPER.parent, stdout=handle, stderr=subprocess.STDOUT)
    return match_id, completed.returncode


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--logs-dir", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=3)
    args = parser.parse_args()
    urls = [line.strip() for line in args.input.read_text(encoding="utf-8").splitlines() if line.strip()]
    args.data_dir.mkdir(parents=True, exist_ok=True)
    args.logs_dir.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(run, url, args.data_dir, args.logs_dir) for url in urls]
        for future in as_completed(futures):
            match_id, code = future.result()
            print(f"{'DONE' if code == 0 else 'FAILED'} {match_id}", flush=True)
            if code:
                failures.append(match_id)
    (args.logs_dir / "failed_match_ids.txt").write_text("\n".join(failures) + ("\n" if failures else ""), encoding="utf-8")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
