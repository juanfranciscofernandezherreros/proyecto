# -*- coding: utf-8 -*-
r"""Orquesta la extraccion e importacion de una o todas las ligas (equivale a
scripts\ligas\ORQUESTAR_LIGAS.ps1, sin PowerShell).

Un fallo en una liga o dataset no detiene el resto: se registra y se sigue. Deja en
REPORT_DIR el resumen y, si hubo fallos, la lista de pendientes. Codigo 1 si algo fallo.
Seguimiento en vivo en public.pipeline_step (best-effort).

Uso:  python scripts\py\ligas\orquestar.py [ALL|CODE] [results|datos|todo] [limite] [reintentos]
"""
import csv
import json
import re
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

SCRIPTS_PY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_PY))
import config as _config
import proc
sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalogo

PY = sys.executable
CFG = _config.cargar()

DATASETS = [
    {"name": "POINT_BY_POINT", "extract": ["extraer/point_by_point.py"], "import": ["importar/point_by_point.py"]},
    {"name": "TEAM_STATS", "extract": ["extraer/dataset.py", "stats_all_periods.csv"], "import": ["importar/team_stats.py"]},
    {"name": "PLAYER_STATS", "extract": ["extraer/dataset.py", "player_stats.csv"], "import": ["importar/player_stats.py"]},
]

_tracking_on = True
_run_id = datetime.now().strftime("%Y%m%d-%H%M%S")


# ---------- seguimiento en vivo (pipeline_step) ----------
def _track_sql(sql):
    global _tracking_on
    if not _tracking_on:
        return None
    p = subprocess.run(
        ["docker", "exec", "-i", CFG.get("POSTGRES_CONTAINER"),
         "psql", "-U", CFG.get("DB_USER"), "-d", CFG.get("DB_NAME"),
         "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1"],
        input=sql, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        print(f"[AVISO] Sin seguimiento en vivo en Grafana: {(p.stdout + p.stderr).strip()}")
        _tracking_on = False
        return None
    lineas = [l for l in p.stdout.splitlines() if l.strip()]
    return lineas[-1].strip() if lineas else ""


def _sql_text(v):
    if v is None or v == "":
        return "NULL"
    return "'" + str(v).replace("'", "''") + "'"


def _start_track(selected, code, step):
    lg = next((x for x in selected if x.get("code") == code), {})
    return _track_sql(
        "INSERT INTO public.pipeline_step (run_id, liga, pais, competicion, paso, estado) "
        f"VALUES ({_sql_text(_run_id)}, {_sql_text(code)}, {_sql_text(lg.get('country'))}, "
        f"{_sql_text(lg.get('competition'))}, {_sql_text(step)}, 'RUNNING') RETURNING id;")


def _stop_track(track_id, state, attempts, detail):
    if not track_id:
        return
    _track_sql(
        f"UPDATE public.pipeline_step SET estado = {_sql_text(state)}, intentos = {attempts}, "
        f"finished_at = now(), detalle = {_sql_text(detail)} WHERE id = {int(track_id)};")


# ---------- invocar un modulo Python como paso ----------
def _invoke(rel_args):
    cmd = [PY, str(SCRIPTS_PY / rel_args[0]), *rel_args[1:]]
    p = subprocess.run(cmd)
    if p.returncode != 0:
        raise RuntimeError(f"{rel_args[0]} termino con codigo {p.returncode}")


def main():
    args = sys.argv[1:]
    league = args[0] if len(args) > 0 else "ALL"
    mode = args[1] if len(args) > 1 else "todo"
    try:
        limit = proc.validar_limite(args[2] if len(args) > 2 else "10", 10)
    except ValueError as e:
        print(f"[ERROR] {e}")
        return 1
    reintentos = int(args[3]) if len(args) > 3 else 0

    try:
        selected = catalogo.seleccionar(league)
    except ValueError as e:
        print(f"[ERROR] {e}")
        return 1

    summary = []

    def invoke_step(code, step, action, retries=0):
        inicio = time.time()
        track_id = _start_track(selected, code, step)
        message = ""
        for intento in range(1, retries + 2):
            try:
                action()
                summary.append({"Liga": code, "Paso": step, "Estado": "OK", "Intentos": intento,
                                "Segundos": int(time.time() - inicio), "Detalle": ""})
                _stop_track(track_id, "OK", intento, "")
                return True
            except Exception as e:
                message = str(e)
                if intento <= retries:
                    print(f"[REINTENTO] [{code}] {step} fallo ({message}); nuevo intento en 15 s.")
                    time.sleep(15)
        print(f"[FALLO] [{code}] {step}: {message}")
        summary.append({"Liga": code, "Paso": step, "Estado": "FALLO", "Intentos": retries + 1,
                        "Segundos": int(time.time() - inicio), "Detalle": message})
        _stop_track(track_id, "FALLO", retries + 1, message)
        return False

    def add_skipped(code, step, reason):
        print(f"[OMITIDO] [{code}] {step}: {reason}")
        summary.append({"Liga": code, "Paso": step, "Estado": "OMITIDO", "Intentos": 0,
                        "Segundos": 0, "Detalle": reason})
        _stop_track(_start_track(selected, code, step), "OMITIDO", 0, reason)

    # Esquema de seguimiento (best-effort).
    esquema = Path(CFG["WORKSPACE"]) / "sql" / "consultas" / "2026-11-03_1625_esquema-pipeline-step.sql"
    if esquema.exists():
        _track_sql(esquema.read_text(encoding="utf-8"))

    if mode in ("results", "todo"):
        for item in selected:
            print(f"RESULTS [{item['code']}]")
            root = Path(CFG["COMPETITIONS_DIR"]) / item["country"] / item["competition"]
            ref = {}

            def extraer_results(it=item, rt=root, rf=ref):
                rt.mkdir(parents=True, exist_ok=True)
                inicio = time.time()
                rc = subprocess.run([CFG["PYTHON"], CFG["SCRAPER"], "competition", "results",
                                     it["resultsUrl"], "--output", str(rt / "RESULTS.csv")]).returncode
                if rc != 0:
                    raise RuntimeError(f"el scraper termino con codigo {rc}")
                cands = [p for p in rt.glob(f"RESULTS_*_{it['country']}_{it['competition']}.csv")
                         if p.stat().st_mtime >= inicio]
                if not cands:
                    raise RuntimeError("no se genero el CSV de RESULTS")
                rf["file"] = max(cands, key=lambda p: p.stat().st_mtime)

            if invoke_step(item["code"], "RESULTS extraer", extraer_results, reintentos):
                invoke_step(item["code"], "RESULTS importar",
                            lambda it=item, rf=ref: _invoke(["importar/resultados.py",
                                                             str(rf["file"]), it["country"], it["competition"]]))
            else:
                add_skipped(item["code"], "RESULTS importar", "la extraccion fallo")

    if mode in ("datos", "todo"):
        invoke_step("GENERAL", "antibloqueo y monitor CSV",
                    lambda: _invoke(["arranque/asegurar.py", "antibloqueo", "watcher"]))
        for item in selected:
            print(f"DATOS [{item['code']}]")
            extract_args = [item["country"], item["competition"], str(limit)]
            for ds in DATASETS:
                extracted = invoke_step(
                    item["code"], f"{ds['name']} extraer",
                    lambda ds=ds, it=item: _invoke(ds["extract"] + [it["country"], it["competition"], str(limit)]),
                    reintentos)
                if extracted:
                    invoke_step(item["code"], f"{ds['name']} importar",
                                lambda ds=ds, it=item: _invoke(ds["import"] + [it["country"], it["competition"]]))
                else:
                    add_skipped(item["code"], f"{ds['name']} importar", "la extraccion fallo")

    # ---------- resumen ----------
    failed = [s for s in summary if s["Estado"] == "FALLO"]
    report_dir = Path(CFG["REPORT_DIR"])
    report_dir.mkdir(parents=True, exist_ok=True)
    report_file = report_dir / f"ligas-orquestar-resumen-{datetime.now():%Y%m%d-%H%M%S}.csv"
    with open(report_file, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["Liga", "Paso", "Estado", "Intentos", "Segundos", "Detalle"])
        w.writeheader()
        w.writerows(summary)

    print("")
    print("==================== RESUMEN ====================")
    _imprimir_tabla(summary)
    ok = sum(1 for s in summary if s["Estado"] == "OK")
    skipped = sum(1 for s in summary if s["Estado"] == "OMITIDO")
    print(f"Pasos: {ok} OK, {len(failed)} con fallo, {skipped} omitidos. Detalle: {report_file}")
    if not failed:
        return 0

    print("Fallos:")
    for s in failed:
        print(f"  [{s['Liga']}] {s['Paso']}: {s['Detalle']}")

    _pendientes(selected, failed, report_file)
    return 1


def _imprimir_tabla(summary):
    cols = ["Liga", "Paso", "Estado", "Intentos", "Segundos"]
    anchos = {c: max(len(c), *(len(str(s.get(c, ""))) for s in summary)) if summary else len(c) for c in cols}
    print("  ".join(c.ljust(anchos[c]) for c in cols))
    print("  ".join("-" * anchos[c] for c in cols))
    for s in summary:
        print("  ".join(str(s.get(c, "")).ljust(anchos[c]) for c in cols))


def _pendientes(selected, failed, report_file):
    try:
        codes = {s["Liga"] for s in failed}
        failed_leagues = [lg for lg in selected if lg.get("code") in codes]
        keys = {f"{lg['country']}|{lg['competition']}" for lg in failed_leagues}
        req = urllib.request.Request(f"{CFG['AUDIT_URL']}/run", method="POST")
        audit = json.loads(urllib.request.urlopen(req, timeout=120).read().decode("utf-8"))
        rows = [{"match_date": m.get("matchDate"), "country": m.get("country"),
                 "competition": m.get("competition"), "match_id": m.get("matchId"),
                 "home_team": m.get("homeTeam"), "away_team": m.get("awayTeam"),
                 "pending_datasets": ",".join(m.get("pendingDatasets") or [])}
                for m in (audit.get("pendingMatches") or [])
                if f"{m.get('country')}|{m.get('competition')}" in keys]
        pending_file = Path(str(report_file).replace("resumen", "pendientes"))
        with open(pending_file, "w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=["match_date", "country", "competition", "match_id",
                                               "home_team", "away_team", "pending_datasets"])
            w.writeheader()
            w.writerows(rows)
        print("")
        print(f"{len(rows)} partidos pendientes en las ligas con fallos: {pending_file}")
        print(f'Para recuperarlos: 1_EJECUTAR\\MATCHIDS_PENDIENTES.bat "{pending_file}"')
    except Exception as e:
        print(f"No se pudo generar la lista de pendientes ({e}).")
        print("Se pueden recuperar igualmente con 1_EJECUTAR\\MATCHIDS_PENDIENTES.bat (procesa todos los pendientes).")


if __name__ == "__main__":
    sys.exit(main())
