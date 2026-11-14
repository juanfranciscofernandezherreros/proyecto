# -*- coding: utf-8 -*-
r"""Procesa la ultima jornada de una liga de principio a fin: extrae el bundle
completo de cada partido y lo importa en el orden que exige el launcher (equivale a
scripts\ligas\PROCESAR_ULTIMOS_PARTIDOS_COMPLETO.ps1, sin PowerShell).

Uso:  python scripts\py\ligas\ultimos_partidos.py [CODE]
"""
import csv
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config
sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalogo
import ejecutar_liga
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "importar"))
import launcher as L

PREFIXES = ["MATCH_DETAILS_", "SCORE_SUMMARY_", "STATS_ALL_PERIODS_", "PLAYER_STATS_", "POINT_BY_POINT_"]
TIPOS = {"MATCH_DETAILS_": "MATCH_DETAILS", "SCORE_SUMMARY_": "SCORE_SUMMARY",
         "STATS_ALL_PERIODS_": "STATS_ALL_PERIODS", "PLAYER_STATS_": "PLAYER_STATS",
         "POINT_BY_POINT_": "POINT_BY_POINT"}


def _mas_reciente(paths):
    paths = list(paths)
    return max(paths, key=lambda p: p.stat().st_mtime) if paths else None


def main():
    args = sys.argv[1:]
    cfg = _config.cargar()
    ligas = catalogo.cargar_ligas()
    if not args:
        for i, lg in enumerate(ligas, 1):
            print(f"[{i}] {lg['name']} ({lg['code']})")
        n = input("Selecciona liga: ").strip()
        if not n.isdigit() or not (1 <= int(n) <= len(ligas)):
            print("[ERROR] Seleccion no valida.")
            return 1
        lg = ligas[int(n) - 1]
    else:
        lg = catalogo.por_code(args[0])
        if not lg:
            print(f"[ERROR] Liga desconocida: {args[0]}")
            return 1

    try:
        res = ejecutar_liga.ejecutar(lg["code"], skip_import=True)
        csv_path = Path(res["CsvPath"])
        with open(csv_path, encoding="utf-8-sig", newline="") as fh:
            match_ids = []
            for r in csv.DictReader(fh):
                mid = r.get("matchId") or r.get("match_id")
                if mid and re.match(r"^[A-Za-z0-9_-]+$", mid) and mid not in match_ids:
                    match_ids.append(mid)
        if not match_ids:
            print(f"[ERROR] No hay partidos validos en {csv_path}")
            return 1

        python = Path(cfg["PYTHON"])
        scraper = Path(cfg["SCRAPER"])
        competition_root = Path(cfg["COMPETITIONS_DIR"]) / lg["country"] / lg["competition"]
        report_root = Path(cfg["REPORTS_DIR"]) / lg["country"] / lg["competition"]
        if not python.exists() or not scraper.exists():
            print("[ERROR] No se encuentra el scraper Python.")
            return 1
        report_root.mkdir(parents=True, exist_ok=True)
        run_log = report_root / f"last-matches-{datetime.now():%Y%m%d%H%M%S}.log"
        for mid in match_ids:
            print(f"Extrayendo bundle completo: {mid}")
            rc = ejecutar_liga._tee([str(python), str(scraper), "match", "bundle",
                                     "--mid", mid, "--data-dir", str(competition_root)], run_log)
            if rc != 0:
                print(f"[ERROR] Fallo la extraccion del partido {mid} (codigo {rc}).")
                return 1

        L.asegurar_servicios("postgres", "launcher")

        report = []
        for mid in match_ids:
            d = competition_root / mid
            for prefix in PREFIXES:
                f = _mas_reciente(d.glob(f"{prefix}*.csv")) if d.is_dir() else None
                if not f:
                    if prefix == "POINT_BY_POINT_":
                        print(f"AVISO: Sin PBP para {mid}")
                        continue
                    print(f"[ERROR] Falta {prefix} para {mid}")
                    return 1
                req = L.submit_and_wait(cfg, f, timeout_min=30)
                report.append({"MatchId": mid, "Type": TIPOS[prefix], "File": f.name,
                               "Status": req.get("status")})
                if req.get("status") != "COMPLETED":
                    print(f"[ERROR] Fallo {f.name}: {req.get('status')}")
                    return 1
        rep = report_root / f"full-flow-{datetime.now():%Y%m%d%H%M%S}.csv"
        with open(rep, "w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=["MatchId", "Type", "File", "Status"])
            w.writeheader()
            w.writerows(report)
        print(f"Flujo terminado para {len(match_ids)} partidos; incluido PLAY_BY_PLAY cuando el scraper lo proporciona.")
        return 0
    except Exception as e:
        print(f"[ERROR] {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
