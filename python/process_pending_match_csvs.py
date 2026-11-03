"""Extract and import only the requested datasets for one Flashscore match.

Clave del flujo: que a un partido le falte un dataset NO significa que este
incompleto. Flashscore no publica todos los datasets para todas las ligas (p. ej.
la LNB francesa no da point-by-point ni el desglose de estadisticas por cuartos).
Cuando la fuente no tiene un dato, se marca como VACIO/NO_PUBLICADO en la auditoria
(un dashboard lo muestra) y el partido se considera completo; solo los errores
transitorios de verdad (timeout, red, driver) se reintentan en otra pasada.
"""
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
# logical -> (fichero del dataset en el manifest, prefijo de los CSV consolidables)
DATASETS = {
    "MATCH_SUMMARY": ("score_summary.csv", "SCORE_SUMMARY_"),
    "TEAM_STATS": ("stats_all_periods.csv", "STATS_ALL_PERIODS_"),
    "PLAYER_STATS": ("player_stats.csv", "PLAYER_STATS_"),
    "POINT_BY_POINT": ("point_by_point.csv", "POINT_BY_POINT_"),
}
MAX_ATTEMPTS = 3
# Un fallo del scraper con alguna de estas senales es transitorio: se reintenta.
# Cualquier otro fallo (o el estado empty/not_available) se trata como que la fuente
# no publica el dato -> se marca VACIO y no se vuelve a pedir.
TRANSIENT_HINTS = (
    "timeout", "timed out", "connection", "net::", "err_", "reset",
    "session", "driver", "chrome", "edge", "renderer", "disconnected",
    "temporarily", "unreachable",
)


def run_scraper(url: str, root: Path, dataset: str) -> int:
    """Lanza el scraper de un dataset y devuelve su codigo de salida sin abortar.

    El bundle usa codigos estables (0 ok/vacio, 3 parcial, etc.). La decision real
    se toma leyendo el manifest, no el codigo, asi que aqui no se lanza excepcion.
    """
    completed = subprocess.run(
        (str(PYTHON), str(SCRAPER), url, "--data-dir", str(root), "--dataset", dataset),
        cwd=WORKSPACE,
    )
    return completed.returncode


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


def manifest_entry(match_dir: Path, dataset: str) -> dict | None:
    """Entrada del manifest para el dataset recien extraido (status/rows/error)."""
    manifest = match_dir / "manifest.json"
    if not manifest.is_file():
        return None
    try:
        payload = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if dataset == "score_summary.csv":
        # El resumen va bajo raw_details ademas de files segun el schema.
        entry = payload.get("files", {}).get(dataset)
        return entry if entry is not None else payload.get("raw_details")
    return payload.get("files", {}).get(dataset)


def classify(status: str, error: str, source_url: str) -> str:
    """Devuelve COMPLETE | VACIO | NO_PUBLICADO | TRANSITORIO | DESCONOCIDO."""
    status = (status or "").strip().lower()
    if status == "complete":
        return "COMPLETE"
    if status == "empty":
        return "VACIO"
    if status == "not_available":
        return "NO_PUBLICADO"
    if status == "failed":
        hay = (error or "").lower()
        if any(hint in hay for hint in TRANSIENT_HINTS):
            return "TRANSITORIO"
        # Fallo no transitorio (bloque/enlace inexistente, 404, sin error concreto):
        # la fuente no publica el dato.
        return "NO_PUBLICADO"
    return "DESCONOCIDO"


def mark_dataset_unavailable(match_id: str, logical: str, *, country: str, competition: str,
                             estado: str, reason: str, rows: int, source_url: str, attempts: int) -> bool:
    """Registra en la auditoria que la fuente no publica `logical` para `match_id`.

    `estado` es VACIO (pagina valida con 0 filas) o NO_PUBLICADO (bloque/enlace que no
    existe). La auditoria deja de marcar ese dataset como pendiente y el orquestador no
    reabre el partido. Un dashboard lee la tabla. Devuelve True si quedo guardado.
    """
    audit_url = CONFIG.get("AUDIT_URL", "").rstrip("/")
    if not audit_url:
        print(f"[{match_id}] AVISO: AUDIT_URL no configurada; no se pudo registrar {logical} como {estado}.", flush=True)
        return False
    payload = json.dumps({
        "matchId": match_id, "dataset": logical, "country": country, "competition": competition,
        "estado": estado, "reason": reason, "rows": rows, "sourceUrl": source_url, "attempts": attempts,
    }).encode("utf-8")
    request = urllib.request.Request(f"{audit_url}/dataset-unavailable", data=payload,
                                     headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            response.read()
        return True
    except (urllib.error.URLError, OSError) as error:
        print(f"[{match_id}] AVISO: no se pudo registrar {logical} como {estado}: {error}", flush=True)
        return False


def import_dataset(match_id: str, logical: str, prefix: str, root: Path) -> None:
    csv_path = latest_data(root / match_id, prefix)
    print(f"[{match_id}] consolidating {csv_path.name}...", flush=True)
    call(str(PYTHON), str(CONSOLIDATOR), "--input", str(root), "--output", str(READY), "--match-id", match_id, "--prefix", prefix)
    print(f"[{match_id}] submitting {logical} to batch launcher...", flush=True)
    call(str(PYTHON), str(SUBMITTER), "--root", str(READY / "current" / match_id), "--prefix", prefix, "--launcher-url", CONFIG["LAUNCHER_URL"], "--timeout-seconds", "120")
    print(f"[{match_id}] {logical} import completed.", flush=True)


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

    sin_datos: list[str] = []          # datasets que la fuente no publica (VACIO/NO_PUBLICADO)
    transitorios: list[str] = []       # fallos reales que quedan para reintentar en otra pasada
    for logical in dict.fromkeys(args.datasets):
        dataset, prefix = DATASETS[logical]
        resultado = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            print(f"[{args.match_id}] extracting {logical} (attempt {attempt}/{MAX_ATTEMPTS})...", flush=True)
            run_scraper(url, root, dataset)
            entry = manifest_entry(match_dir, dataset) or {}
            resultado = classify(entry.get("status", ""), entry.get("error", ""), url)
            # Un CSV con filas manda aunque el estado llegue raro: hay datos que importar.
            if resultado != "COMPLETE" and latest_data(match_dir, prefix):
                resultado = "COMPLETE"
            if resultado != "TRANSITORIO":
                break
            if attempt < MAX_ATTEMPTS:
                print(f"[{args.match_id}] {logical} fallo transitorio ({entry.get('error', '')[:120]}); reintentando...", flush=True)

        if resultado == "COMPLETE":
            import_dataset(args.match_id, logical, prefix, root)
            continue

        if resultado in ("VACIO", "NO_PUBLICADO"):
            rows = int((manifest_entry(match_dir, dataset) or {}).get("rows", 0) or 0)
            print(f"[{args.match_id}] {logical} ESTA VACIO en la fuente ({resultado}); se marca y el partido sigue completo.", flush=True)
            mark_dataset_unavailable(
                args.match_id, logical, country=args.country, competition=args.competition,
                estado=resultado, reason=f"{resultado}_{(manifest_entry(match_dir, dataset) or {}).get('status', '')}",
                rows=rows, source_url=url, attempts=MAX_ATTEMPTS if resultado == "NO_PUBLICADO" else 1,
            )
            sin_datos.append(f"{logical}:{resultado}")
            continue

        # TRANSITORIO o DESCONOCIDO: no se marca; queda pendiente para reintentar en otra pasada.
        detalle = (manifest_entry(match_dir, dataset) or {}).get("error", "") or "sin detalle"
        print(f"[{args.match_id}] {logical} fallo persistente tras {MAX_ATTEMPTS} intentos: {detalle[:160]}", file=sys.stderr, flush=True)
        transitorios.append(logical)

    if sin_datos:
        print(f"[{args.match_id}] datasets vacios/no publicados en la fuente: {','.join(sin_datos)}.", flush=True)
    if transitorios:
        print(f"[{args.match_id}] datasets con fallo transitorio (siguen pendientes): {','.join(transitorios)}.", flush=True)
        # Error real pendiente: el partido no esta resuelto; se senala para que el orquestador
        # lo cuente como ERROR, pero sin bucle: la proxima pasada reintenta solo esto.
        return 1
    print(f"[{args.match_id}] all requested datasets completed.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
