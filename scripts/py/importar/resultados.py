# -*- coding: utf-8 -*-
r"""Importa un CSV de RESULTS en PostgreSQL via launcher y verifica el resultado
(equivale a scripts\importar\IMPORTAR_RESULTADOS_EUROLIGA_A_POSTGRESQL.ps1 +
IMPORTAR_RESULTADOS.bat, sin PowerShell).

Uso:  python scripts\py\importar\resultados.py <csv> <pais> <competicion>
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

CUARTOS = ["home_score1", "home_score2", "home_score3", "home_score4",
           "away_score1", "away_score2", "away_score3", "away_score4"]
ORDEN = ["RESULTS", "FIXTURES", "SCORE_SUMMARY", "STATS_ALL_PERIODS", "PLAYER_STATS", "POINT_BY_POINT"]


def tipo_csv(nombre):
    if re.match(r"^RESULTS_", nombre):
        return "RESULTS"
    if re.match(r"^FIXTURES_", nombre):
        return "FIXTURES"
    if re.match(r"^(SCORE_SUMMARY|MATCH_SUMMARY)_", nombre):
        return "SCORE_SUMMARY"
    if re.match(r"^STATS_ALL_PERIODS_", nombre):
        return "STATS_ALL_PERIODS"
    if re.match(r"^PLAYER_STATS_", nombre):
        return "PLAYER_STATS"
    if re.match(r"^POINT_BY_POINT_", nombre):
        return "POINT_BY_POINT"
    return None


def _leer_filas(path):
    with open(path, encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh))


def importar(csv_path, country="europe", competition="euroleague"):
    cfg = _config.cargar()
    root = Path(cfg["WORKSPACE"])
    python = root / "python-pyppeter" / ".venv" / "Scripts" / "python.exe"
    compose = cfg.get("COMPOSE_FILE")
    competition_root = Path(cfg["COMPETITIONS_DIR"]) / country / competition
    report_root = Path(cfg["REPORTS_DIR"]) / country / competition
    run = L.run_id()

    for p in (python, compose):
        if not os.path.exists(p):
            raise FalloImport(f"Falta un archivo necesario: {p}")
    if not competition_root.is_dir():
        raise FalloImport(f"No existe la carpeta canonica: {competition_root}")
    csv_path = Path(csv_path)
    if not csv_path.is_file():
        raise FalloImport(f"No existe el CSV indicado: {csv_path}")
    patron = rf"^RESULTS_\d{{14}}_{re.escape(country)}_{re.escape(competition)}\.csv$"
    if str(csv_path.parent) != str(competition_root) or not re.match(patron, csv_path.name):
        raise FalloImport(f"El fichero indicado no es un RESULTS de {country}/{competition} "
                          f"dentro de la ruta canonica: {csv_path}")

    filas = _leer_filas(csv_path)
    if not filas:
        raise FalloImport(f"El CSV no contiene resultados: {csv_path}")
    incompletos = [f for f in filas
                   if not f.get("homeScore") or not f.get("awayScore")
                   or any(not (f.get(c) or "").strip() for c in CUARTOS)]
    if incompletos:
        raise FalloImport(f"El CSV tiene {len(incompletos)} partidos sin marcador o sin los "
                          "cuatro parciales reglamentarios.")

    report_root.mkdir(parents=True, exist_ok=True)
    print(f"CSV de Euroliga seleccionado: {csv_path}")

    L.asegurar_servicios("postgres", "launcher")

    tipo = tipo_csv(csv_path.name)
    if not tipo:
        raise FalloImport(f"CSV no reconocido: {csv_path}")

    print(f"Enviando {tipo}: {csv_path.name}")
    resultado = L.submit_and_wait(cfg, csv_path, timeout_min=30)
    report = [{"File": csv_path.name, "Type": tipo,
               "Status": resultado.get("status"), "RequestId": resultado.get("requestId")}]

    batch_report = report_root / f"postgresql-import-{run}.csv"
    _escribir_csv(batch_report, report, ["File", "Type", "Status", "RequestId"])
    print(L.tabla(report, ["File", "Type", "Status", "RequestId"]))
    if any(r["Status"] != "COMPLETED" for r in report):
        raise FalloImport(f"Una o mas importaciones no terminaron en COMPLETED. Informe: {batch_report}")

    match_ids = []
    for f in filas:
        mid = f.get("match_id") or f.get("matchId")
        if mid and re.match(r"^[A-Za-z0-9_-]+$", mid) and mid not in match_ids:
            match_ids.append(mid)
    if not match_ids:
        raise FalloImport("No se pudieron leer match IDs para verificar la importacion.")
    sql_ids = ",".join(f"'{m}'" for m in match_ids)
    query = (f"SELECT COUNT(DISTINCT match_id) FROM results.results WHERE country = '{country}' "
             f"AND competition = '{competition}' AND match_id IN ({sql_ids});")
    db_count = int(L.psql_valor(cfg, query))
    print(f"Verificacion PostgreSQL: {db_count} de {len(match_ids)} partidos del CSV encontrados "
          f"en results.results para {country}/{competition}.")
    if db_count != len(match_ids):
        raise FalloImport("La consulta de PostgreSQL no encontro todos los partidos del CSV.")

    count_report = report_root / f"postgresql-count-{run}.csv"
    _escribir_csv(count_report, [{"Csv": str(csv_path), "ExpectedMatchCount": len(match_ids),
                                  "DatabaseMatchCount": db_count, "Query": query}],
                  ["Csv", "ExpectedMatchCount", "DatabaseMatchCount", "Query"])
    print(f"Importacion completa en PostgreSQL. Informe: {batch_report}; conteo: {count_report}")


def _escribir_csv(path, filas, columnas):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=columnas)
        w.writeheader()
        w.writerows(filas)


def main():
    args = sys.argv[1:]
    if not args:
        print("ERROR: Falta la ruta del CSV de resultados.")
        return 1
    if len(args) < 2:
        print("ERROR: Falta el pais de la competicion.")
        return 1
    if len(args) < 3:
        print("ERROR: Falta la competicion.")
        return 1
    try:
        importar(args[0], args[1], args[2])
        return 0
    except FalloImport as e:
        print(f"[ERROR] {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
