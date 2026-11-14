# -*- coding: utf-8 -*-
r"""Extrae de Flashscore el POINT_BY_POINT (jugada a jugada) de los partidos de la
ultima RESULTS que aun no estan en PostgreSQL, construyendo la URL con los slugs de
los equipos (equivale a scripts\extraer\EXTRAER_PLAY_BY_PLAY_PENDIENTE.ps1, sin
PowerShell).

Uso:  python scripts\py\extraer\play_by_play.py [pais] [competicion] [limite]
"""
import csv
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config
import proc
sys.path.insert(0, str(Path(__file__).resolve().parent))
import ya_importados as YI
from dataset import FalloExtraccion, _mas_reciente, _run_tee


def _slug(texto):
    return re.sub(r"[^a-z0-9]+", "-", (texto or "").lower()).strip("-")


def extraer(country="europe", competition="euroleague", limit=20):
    cfg = _config.cargar()
    scraper_dir = Path(cfg["SCRAPER_DIR"])
    python = scraper_dir / ".venv" / "Scripts" / "python.exe"
    scraper = scraper_dir / "flashscore.py"
    competition_root = Path(cfg["COMPETITIONS_DIR"]) / country / competition
    log_root = Path(cfg["WORKSPACE"]) / "logs"

    for p in (python, scraper, competition_root):
        if not p.exists():
            raise FalloExtraccion(f"No se encuentra: {p}")
    log_root.mkdir(parents=True, exist_ok=True)

    results = _mas_reciente(competition_root.glob(f"RESULTS_*_{country}_{competition}.csv"))
    if not results:
        raise FalloExtraccion(f"No hay RESULTS CSV para {country}/{competition} en {competition_root}")
    imported = set(YI.ya_importados("POINT_BY_POINT"))
    with open(results, encoding="utf-8-sig", newline="") as fh:
        candidates = [r for r in csv.DictReader(fh)
                      if (r.get("matchId") or r.get("match_id")) and r.get("eventDatetime")]
    if not candidates:
        raise FalloExtraccion(f"El CSV {results.name} no contiene partidos con ID y fecha.")
    no_imp = [r for r in candidates if (r.get("matchId") or r.get("match_id")) not in imported]
    print(f"Ya importados en POINT_BY_POINT (se saltan): {len(candidates) - len(no_imp)}")
    rows = sorted(no_imp, key=lambda r: datetime.fromisoformat(r["eventDatetime"]), reverse=True)[:limit]
    if not rows:
        print(f"Todos los partidos de {results.name} ya tienen POINT_BY_POINT. No se extrae nada.")
        return 0

    run = datetime.now().strftime("%Y%m%d%H%M%S")
    log_path = log_root / f"play-by-play-extraction-{run}.log"
    print(f"RESULTS: {results}")
    print(f"Partidos a extraer: {len(rows)} (limite {limit})")
    for row in rows:
        match_id = row.get("matchId") or row.get("match_id")
        output = competition_root / f"POINT_BY_POINT_{match_id}.csv"
        url = f"https://www.flashscore.com/match/basketball/{_slug(row.get('homeTeam'))}/{_slug(row.get('awayTeam'))}/?mid={match_id}"
        print(f"[{match_id}] {row.get('homeTeam')} - {row.get('awayTeam')}")
        rc = _run_tee([str(python), str(scraper), "match", "quarters", url,
                       "--mid", match_id, "--output", str(output)], log_path)
        if rc != 0:
            raise FalloExtraccion(f"Pyppeter fallo para {match_id}; log: {log_path}")
        if not output.exists() or output.stat().st_size == 0:
            print(f"AVISO: [{match_id}] No se genero CSV POINT_BY_POINT (puede no estar disponible).")
        else:
            print(f"[{match_id}] CSV creado: {output}")
    print(f"Extraccion terminada. Log: {log_path}")
    return 0


def main():
    args = sys.argv[1:]
    country = args[0] if len(args) > 0 else "europe"
    competition = args[1] if len(args) > 1 else "euroleague"
    try:
        limit = proc.validar_limite(args[2] if len(args) > 2 else "20", 20)
    except ValueError as e:
        print(f"[ERROR] {e}")
        return 1
    try:
        return extraer(country, competition, limit)
    except FalloExtraccion as e:
        print(f"[ERROR] {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
