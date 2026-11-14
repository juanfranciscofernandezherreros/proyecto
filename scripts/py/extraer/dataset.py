# -*- coding: utf-8 -*-
r"""Extrae de Flashscore un dataset por partido (SCORE_SUMMARY / STATS_ALL_PERIODS /
PLAYER_STATS) de los partidos de la ultima RESULTS que aun no estan en PostgreSQL
(equivale a scripts\extraer\EXTRAER_DATASET_PENDIENTE.ps1 + EXTRAER_DATASET.bat y los
wrappers MATCH_SUMMARY/TEAM_STATS/PLAYER_STATS, sin PowerShell).

Uso:  python scripts\py\extraer\dataset.py <score_summary.csv|stats_all_periods.csv|player_stats.csv> [pais] [competicion] [limite]
"""
import csv
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config
import proc
sys.path.insert(0, str(Path(__file__).resolve().parent))
import ya_importados as YI

LABELS = {"score_summary.csv": "MATCH_SUMMARY", "stats_all_periods.csv": "TEAM_STATS",
          "player_stats.csv": "PLAYER_STATS"}
PREFIXES = {"score_summary.csv": "SCORE_SUMMARY", "stats_all_periods.csv": "STATS_ALL_PERIODS",
            "player_stats.csv": "PLAYER_STATS"}


class FalloExtraccion(Exception):
    pass


def _mas_reciente(paths):
    paths = list(paths)
    return max(paths, key=lambda p: p.stat().st_mtime) if paths else None


def _run_tee(cmd, log_path):
    """Ejecuta un comando, muestra su salida y la anade al log. Devuelve el codigo."""
    with open(log_path, "a", encoding="utf-8") as log:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding="utf-8", errors="replace", bufsize=1)
        for linea in p.stdout:
            sys.stdout.write(linea)
            log.write(linea)
        p.wait()
    return p.returncode


def _tiene_filas(path):
    with open(path, encoding="utf-8-sig") as fh:
        next(fh, None)
        return bool((next(fh, "") or "").strip())


def extraer(dataset, country="europe", competition="euroleague", limit=20):
    cfg = _config.cargar()
    scraper_dir = Path(cfg["SCRAPER_DIR"])
    python = scraper_dir / ".venv" / "Scripts" / "python.exe"
    scraper = scraper_dir / "flashscore.py"
    resolver = Path(cfg["WORKSPACE"]) / "python" / "resolve_flashscore_redirect.py"
    competition_root = Path(cfg["COMPETITIONS_DIR"]) / country / competition
    log_root = Path(cfg["WORKSPACE"]) / "logs"

    for p in (python, scraper, resolver, competition_root):
        if not p.exists():
            raise FalloExtraccion(f"No se encuentra: {p}")
    log_root.mkdir(parents=True, exist_ok=True)

    results = _mas_reciente(competition_root.glob(f"RESULTS_*_{country}_{competition}.csv"))
    if not results:
        raise FalloExtraccion(f"No hay RESULTS CSV para {country}/{competition} en {competition_root}")
    label = LABELS[dataset]
    imported = set(YI.ya_importados(label))
    with open(results, encoding="utf-8-sig", newline="") as fh:
        candidates = [r for r in csv.DictReader(fh)
                      if (r.get("matchId") or r.get("match_id")) and r.get("eventDatetime")]
    if not candidates:
        raise FalloExtraccion(f"El CSV {results.name} no contiene partidos con ID y fecha.")
    no_imp = [r for r in candidates if (r.get("matchId") or r.get("match_id")) not in imported]
    print(f"Ya importados en {label} (se saltan): {len(candidates) - len(no_imp)}")
    rows = sorted(no_imp, key=lambda r: datetime.fromisoformat(r["eventDatetime"]), reverse=True)[:limit]
    if not rows:
        print(f"Todos los partidos de {results.name} ya tienen {label}. No se extrae nada.")
        return 0

    run = datetime.now().strftime("%Y%m%d%H%M%S")
    prefix = PREFIXES[dataset]
    log_path = log_root / f"{label.lower()}-extraction-{run}.log"
    print(f"RESULTS: {results}")
    print(f"Partidos a extraer: {len(rows)} (limite {limit})")
    for row in rows:
        match_id = row.get("matchId") or row.get("match_id")
        r = subprocess.run([str(python), str(resolver), match_id],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        url = r.stdout.strip()
        if r.returncode != 0 or not url:
            raise FalloExtraccion(f"Flashscore no devolvio la URL canonica para {match_id}; log: {log_path}")
        print(f"[{match_id}] {row.get('homeTeam')} - {row.get('awayTeam')}")
        completado = False
        for intento in range(1, 4):
            if completado:
                break
            print(f"[{match_id}] {label} intento {intento}/3")
            rc = _run_tee([str(python), str(scraper), "match", "bundle", url,
                           "--data-dir", str(competition_root), "--dataset", dataset], log_path)
            if rc != 0:
                raise FalloExtraccion(f"La extraccion {label} fallo para {match_id}; log: {log_path}")
            csv_f = _mas_reciente((competition_root / match_id).glob(f"{prefix}_*.csv"))
            if csv_f and _tiene_filas(csv_f):
                completado = True
            elif intento < 3:
                print(f"AVISO: [{match_id}] {label} vacio; se reintentara.")
        if not completado:
            print(f"AVISO: [{match_id}] {label} sigue vacio tras 3 intentos.")
    print(f"Extraccion {label} terminada. Log: {log_path}")
    return 0


def main():
    args = sys.argv[1:]
    if not args or args[0] not in LABELS:
        print("ERROR: dataset invalido (score_summary.csv | stats_all_periods.csv | player_stats.csv)")
        return 1
    dataset = args[0]
    country = args[1] if len(args) > 1 else "europe"
    competition = args[2] if len(args) > 2 else "euroleague"
    try:
        limit = proc.validar_limite(args[3] if len(args) > 3 else "20", 20)
    except ValueError as e:
        print(f"[ERROR] {e}")
        return 1
    label = LABELS[dataset]
    print(f"Extrayendo {label} desde el ultimo RESULTS CSV: {country}/{competition}")
    try:
        return extraer(dataset, country, competition, limit)
    except FalloExtraccion as e:
        print(f"[ERROR] Extraccion {label} fallida.")
        print(f"  {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
