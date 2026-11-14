# -*- coding: utf-8 -*-
r"""Nucleo comun de los importadores de estadisticas por partido (TEAM_STATS,
PLAYER_STATS, POINT_BY_POINT): localizan los CSV de cada match de la ultima RESULTS
y los envian al launcher. Equivale a la parte compartida de los PROCESAR_*_A_
POSTGRESQL.ps1, sin PowerShell.
"""
import csv
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config
import launcher as L
from launcher import FalloImport


def _match_ids_de_results(results_path):
    ids = []
    with open(results_path, encoding="utf-8-sig", newline="") as fh:
        for fila in csv.DictReader(fh):
            mid = fila.get("matchId")
            if mid and re.match(r"^[A-Za-z0-9_-]+$", mid) and mid not in ids:
                ids.append(mid)
    return ids


def _mas_reciente(paths):
    paths = list(paths)
    if not paths:
        return None
    return max(paths, key=lambda p: p.stat().st_mtime)


def results_mas_reciente(competition_root, country, competition):
    ficheros = list(competition_root.glob(f"RESULTS_*_{country}_{competition}.csv"))
    return _mas_reciente(ficheros)


def procesar(country, competition, label, report_prefix, detectados_msg, buscar):
    """buscar(competition_root, match_ids) -> lista de (Path, matchId); imprime sus
    propios avisos. Devuelve el codigo de salida (0/1) y lanza FalloImport en error."""
    cfg = _config.cargar()
    root = Path(cfg["WORKSPACE"])
    compose = cfg.get("COMPOSE_FILE")
    java = cfg.get("JAVA_EXE")
    launcher_jar = root / "csv-extra-batch" / "launcher" / "target" / "csv-batch-launcher.jar"
    competition_root = Path(cfg["COMPETITIONS_DIR"]) / country / competition
    report_root = Path(cfg["REPORTS_DIR"]) / country / competition

    for p in (competition_root, compose, java, launcher_jar):
        if not os.path.exists(p):
            raise FalloImport(f"Falta el recurso requerido: {p}")
    report_root.mkdir(parents=True, exist_ok=True)

    results = results_mas_reciente(competition_root, country, competition)
    if not results:
        raise FalloImport(f"No se encontro RESULTS para {country}/{competition}.")
    match_ids = _match_ids_de_results(results)
    if not match_ids:
        raise FalloImport(f"No hay partidos validos en {results.name}.")

    entries = buscar(competition_root, match_ids)
    if not entries:
        raise FalloImport(f"No hay {label} para los partidos de {results.name}.")

    print(detectados_msg.format(n=len(match_ids), m=len(entries)))
    L.asegurar_servicios("postgres", "launcher")

    report = []
    for path, match_id in entries:
        print(f"Enviando: {path.name}")
        resp = L.submit_and_wait(cfg, path, timeout_min=15)
        report.append({"File": path.name, "MatchId": match_id,
                       "RequestId": resp.get("requestId"), "Status": resp.get("status"),
                       "Batch": resp.get("batch")})

    report_path = report_root / f"{report_prefix}-{L.run_id()}.csv"
    with open(report_path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["File", "MatchId", "RequestId", "Status", "Batch"])
        w.writeheader()
        w.writerows(report)
    print(L.tabla(report, ["File", "MatchId", "RequestId", "Status", "Batch"]))
    if any(r["Status"] != "COMPLETED" for r in report):
        raise FalloImport(f"Una o mas importaciones fallaron. Informe: {report_path}")
    print(f"Importacion secuencial completada. Informe: {report_path}")


def cli(funcion):
    """CLI comun de los PROCESAR_* (pais y competicion opcionales, por defecto
    europe/euroleague), con el [OK]/[ERROR] de los .bat."""
    args = sys.argv[1:]
    country = args[0] if len(args) > 0 else "europe"
    competition = args[1] if len(args) > 1 else "euroleague"
    try:
        funcion(country, competition)
        return 0
    except FalloImport as e:
        print(f"[ERROR] {e}")
        return 1
