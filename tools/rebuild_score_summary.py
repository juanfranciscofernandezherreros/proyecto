"""Rebuild a launcher-ready SCORE_SUMMARY file without touching raw CSVs."""

import csv
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
from proyecto_config import path as config_path  # noqa: E402


SOURCE = config_path("COMPETITIONS_DIR") / "europe" / "euroleague"
TARGET = config_path("READY_DIR") / "SCORE_SUMMARY_retry.csv"

rows: dict[tuple[str, str], dict[str, str]] = {}
fieldnames: list[str] | None = None
for path in SOURCE.rglob("SCORE_SUMMARY_*.csv"):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = fieldnames or reader.fieldnames
        for row in reader:
            match_id = (row.get("match_id") or "").strip()
            side = (row.get("side") or "").strip().lower()
            if match_id and side in {"home", "away"}:
                rows[(match_id, side)] = row

if not fieldnames:
    raise RuntimeError("No SCORE_SUMMARY CSV files found")
TARGET.parent.mkdir(parents=True, exist_ok=True)
with TARGET.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    for key in sorted(rows, key=lambda item: (item[0], 0 if item[1] == "home" else 1)):
        writer.writerow(rows[key])
print(TARGET)
