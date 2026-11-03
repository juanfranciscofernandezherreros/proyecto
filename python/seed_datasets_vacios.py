"""Sembrado seguro del registro de datasets VACIOS/NO_PUBLICADOS.

Marca un (match_id, dataset) como sin datos en la fuente SOLO cuando hay evidencia
fiable y no destructiva:
  (a) el manifest.json en disco de ese partido clasifica el dataset como
      'not_available' o 'empty' (pagina valida, 0 filas), y
  (b) la auditoria sigue viendo ese dataset como pendiente (ausente en la BD).

NUNCA marca a partir de 'failed' (ambiguo: casi siempre es que ese dataset no se
extrajo en la ultima pasada, no que no exista), ni datasets que ya tienen datos.
Asi se limpia el bucle de los partidos ya intentados sin re-scrapear nada y sin
riesgo de ocultar pendientes reales.

Uso:  python\\process... (el .venv), por ejemplo:
      python-pyppeter\\.venv\\Scripts\\python.exe python\\seed_datasets_vacios.py
"""
from __future__ import annotations

import json
import urllib.request

from proyecto_config import CONFIG, path

RAW = path("COMPETITIONS_DIR")
AUDIT_URL = CONFIG.get("AUDIT_URL", "").rstrip("/")
# dataset logico -> fichero en el manifest
FILE_BY_LOGICAL = {
    "MATCH_SUMMARY": "score_summary.csv",
    "TEAM_STATS": "stats_all_periods.csv",
    "PLAYER_STATS": "player_stats.csv",
    "POINT_BY_POINT": "point_by_point.csv",
}
# estados del manifest que SI son evidencia de "la fuente no lo publica"
EVIDENCIA_VACIO = {"not_available", "empty"}


def audit_pending() -> list[dict]:
    with urllib.request.urlopen(f"{AUDIT_URL}/run", data=b"", timeout=120) as response:
        snapshot = json.loads(response.read())
    if snapshot.get("status") != "COMPLETED":
        raise RuntimeError(f"La auditoria devolvio {snapshot.get('status')}: {snapshot.get('error')}")
    return snapshot.get("pendingMatches", [])


def manifest_status(match_dir, dataset_file: str) -> tuple[str, int]:
    manifest = match_dir / "manifest.json"
    if not manifest.is_file():
        return "", 0
    try:
        payload = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "", 0
    entry = payload.get("files", {}).get(dataset_file)
    if entry is None and dataset_file == "score_summary.csv":
        entry = payload.get("raw_details")
    entry = entry or {}
    return (entry.get("status") or "").lower(), int(entry.get("rows", 0) or 0)


def mark(match_id: str, dataset: str, country: str, competition: str, estado: str, rows: int) -> None:
    payload = json.dumps({
        "matchId": match_id, "dataset": dataset, "country": country, "competition": competition,
        "estado": estado, "reason": f"SEED_{estado}", "rows": rows, "sourceUrl": None, "attempts": 1,
    }).encode("utf-8")
    request = urllib.request.Request(f"{AUDIT_URL}/dataset-unavailable", data=payload,
                                     headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def main() -> int:
    if not AUDIT_URL:
        print("AVISO: AUDIT_URL no configurada; nada que sembrar.")
        return 1
    pending = audit_pending()
    marcados = 0
    revisados = 0
    for match in pending:
        match_id = match["matchId"]
        country = match.get("country", "")
        competition = match.get("competition", "")
        match_dir = RAW / country / competition / match_id
        for logical in match.get("pendingDatasets", []):
            dataset_file = FILE_BY_LOGICAL.get(logical)
            if not dataset_file:
                continue
            revisados += 1
            status, rows = manifest_status(match_dir, dataset_file)
            if status not in EVIDENCIA_VACIO:
                continue  # 'failed' o sin manifest: no hay evidencia fiable, no se toca
            estado = "VACIO" if status == "empty" else "NO_PUBLICADO"
            mark(match_id, logical, country, competition, estado, rows)
            marcados += 1
            print(f"[{country}/{competition}] {match_id} {logical} -> {estado} (manifest={status})")
    print(f"Sembrado terminado. Datasets pendientes revisados: {revisados}; marcados como vacios: {marcados}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
