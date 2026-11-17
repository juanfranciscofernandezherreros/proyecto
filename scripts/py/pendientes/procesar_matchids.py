# -*- coding: utf-8 -*-
r"""Procesa los partidos pendientes segun la auditoria fresca (equivale a
scripts\pendientes\PROCESAR_MATCHIDS_PENDIENTES.ps1, sin PowerShell).

Siempre calcula el trabajo desde una auditoria nueva (POST /run). Un CSV indicado
solo limita la seleccion. Para cada partido pendiente ejecuta el pipeline por
match_id (python\process_pending_match_csvs.py) y vuelve a auditar.

Uso:  python scripts\py\pendientes\procesar_matchids.py [csv_seleccion] [limite]
"""
import csv
import json
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SCRIPTS_PY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_PY))
import config as _config
sys.path.insert(0, str(SCRIPTS_PY / "arranque"))
import asegurar

CFG = _config.cargar()
REPORT_ROOT = Path(CFG["REPORT_DIR"])
PYTHON = Path(CFG["WORKSPACE"]) / "python-pyppeter" / ".venv" / "Scripts" / "python.exe"
PIPELINE = Path(CFG["WORKSPACE"]) / "python" / "process_pending_match_csvs.py"
AUDIT_RUN = f"{CFG['AUDIT_URL']}/run"
DATASETS_VALIDOS = ("MATCH_SUMMARY", "TEAM_STATS", "PLAYER_STATS", "POINT_BY_POINT")


def _ahora_iso():
    return datetime.now().astimezone().isoformat()


def _match_key(row):
    return f"{row['country'].lower()}|{row['competition'].lower()}|{row['match_id']}"


def _rows_de_snapshot(snapshot):
    return [{"match_date": m.get("matchDate"), "country": m.get("country"),
             "competition": m.get("competition"), "match_id": m.get("matchId"),
             "home_team": m.get("homeTeam"), "away_team": m.get("awayTeam"),
             "pending_datasets": ",".join(m.get("pendingDatasets") or [])}
            for m in (snapshot.get("pendingMatches") or [])]


def _ultimos_pendientes():
    print("Consultando el modulo persistente de auditoria...")
    req = urllib.request.Request(AUDIT_RUN, method="POST")
    snapshot = json.loads(urllib.request.urlopen(req, timeout=60).read().decode("utf-8"))
    if snapshot.get("status") != "COMPLETED":
        raise RuntimeError(f"La auditoria devolvio estado {snapshot.get('status')}: {snapshot.get('error')}")
    rows = _rows_de_snapshot(snapshot)
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    pending_path = REPORT_ROOT / f"FIXTURES_PROCESSING_AUDIT_PENDING_{stamp}.csv"
    _escribir_rows(pending_path, rows)
    print(f"Auditoria actualizada {snapshot.get('refreshedAt')}; pendientes: {len(rows)}; lista: {pending_path}")
    return rows


def _escribir_rows(path, rows):
    cols = ["match_date", "country", "competition", "match_id", "home_team", "away_team", "pending_datasets"]
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)


def mensaje_inicio(n):
    """Aviso de arranque para Telegram (~1 min por partido)."""
    return f"⏳ Pendientes: {n} partidos por procesar (~{n} min)."


def avisar_inicio(n):
    """Manda el aviso de arranque al bot; si falla, avisa y sigue."""
    try:
        sys.path.insert(0, str(SCRIPTS_PY / "monitor"))
        import telegram_csv
        if telegram_csv.configurado():
            telegram_csv.enviar_texto(mensaje_inicio(n))
    except Exception as e:
        print(f"[AVISO] Telegram: no se pudo enviar el aviso de inicio: {e}")


def main():
    args = [a for a in sys.argv[1:]]
    # "" (o '') para pasar solo el limite llega a veces con las comillas literales.
    primero = args[0].strip().strip("\"'") if args else ""
    csv_path = primero if primero and not primero.isdigit() else None
    limit_arg = next((a for a in args if a.isdigit()), "0")
    limit = int(limit_arg)
    if limit < 0:
        print("[ERROR] El limite debe ser 0 (todos) o un entero positivo.")
        return 1
    if not PYTHON.exists():
        print(f"[ERROR] No existe Python: {PYTHON}")
        return 1
    if not PIPELINE.exists():
        print(f"[ERROR] No existe el pipeline por match_id: {PIPELINE}")
        return 1

    REPORT_ROOT.mkdir(parents=True, exist_ok=True)
    if asegurar.main(["antibloqueo", "postgres", "auditoria", "launcher", "navegador"]) != 0:
        print("[ERROR] No se pudieron asegurar los servicios.")
        return 1
    run_id = datetime.now().strftime("%Y%m%d%H%M%S")

    fresh = _ultimos_pendientes()
    if csv_path:
        cp = Path(csv_path)
        if not cp.is_file():
            print(f"[ERROR] No existe el CSV indicado: {csv_path}")
            return 1
        seleccion = list(csv.DictReader(open(cp, encoding="utf-8-sig", newline="")))
        if not seleccion:
            print(f"[ERROR] El CSV indicado no contiene filas: {csv_path}")
            return 1
        faltan = [c for c in ("country", "competition", "match_id") if c not in seleccion[0]]
        if faltan:
            print(f"[ERROR] Faltan columnas obligatorias en el CSV indicado: {', '.join(faltan)}")
            return 1
        claves = {_match_key(s) for s in seleccion}
        fresh = [r for r in fresh if _match_key(r) in claves]

    paises = [x.strip() for x in str(CFG.get("FILTRO_PAIS", "")).split(",") if x.strip()]
    comps = [x.strip() for x in str(CFG.get("FILTRO_COMPETICION", "")).split(",") if x.strip()]
    if paises or comps:
        fresh = [r for r in fresh if (not paises or r["country"] in paises)
                 and (not comps or r["competition"] in comps)]
        print(f"Filtro de ligas: pais={CFG.get('FILTRO_PAIS')} competicion={CFG.get('FILTRO_COMPETICION')}; "
              f"pendientes tras filtrar: {len(fresh)}")

    # Cola: validos, dedup por (country,competition,match_id), prioridad euroleague/liga-endesa.
    vistos, validos = set(), []
    for r in fresh:
        if (re.match(r"^[A-Za-z0-9]+$", r["match_id"] or "") and re.match(r"^[a-z0-9][a-z0-9-]*$", r["country"] or "")
                and re.match(r"^[a-z0-9][a-z0-9-]*$", r["competition"] or "")):
            k = (r["country"], r["competition"], r["match_id"])
            if k not in vistos:
                vistos.add(k)
                validos.append(r)
    prioridad = {"euroleague": 0, "liga-endesa": 1}
    queue = [r for _, r in sorted(enumerate(validos),
             key=lambda t: (prioridad.get(t[1]["competition"], len(prioridad)), t[0]))]
    if limit > 0:
        queue = queue[:limit]
    if not queue:
        print("La auditoria fresca no devuelve partidos que procesar. No se lanzara ninguna extraccion.")
        return 0

    print(f"Procesamiento secuencial: {len(queue)} partidos pendientes segun la auditoria fresca.")
    avisar_inicio(len(queue))
    state = []
    current_pending = {_match_key(r) for r in fresh}
    for row in queue:
        log_path = REPORT_ROOT / f"PROCESAR_MATCHIDS_{run_id}_{row['match_id']}.log"
        started = _ahora_iso()
        try:
            if _match_key(row) not in current_pending:
                state.append({**_fila_estado(run_id, row, "SKIPPED_ALREADY_PROCESSED", started,
                              "La auditoria fresca ya no marca este partido como pendiente.", log_path)})
                print(f"[{row['match_id']}] omitido: ya no figura como pendiente en la auditoria fresca.")
                continue
            print(f"[{row['country']}/{row['competition']}] {row['match_id']}: {row['home_team']} vs {row['away_team']}")
            datasets = [d for d in (row["pending_datasets"] or "").split(",") if d in DATASETS_VALIDOS]
            if not datasets:
                raise RuntimeError(f"No hay datasets detallados procesables para {row['match_id']}: {row['pending_datasets']}")
            with open(log_path, "w", encoding="utf-8") as log:
                p = subprocess.Popen([str(PYTHON), "-u", str(PIPELINE), row["match_id"],
                                      row["country"], row["competition"], *datasets],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     text=True, encoding="utf-8", errors="replace", bufsize=1)
                ultimas = []
                for linea in p.stdout:
                    sys.stdout.write(linea)
                    log.write(linea)
                    if linea.strip():
                        ultimas.append(linea.strip())
                p.wait()
            if p.returncode != 0:
                raise RuntimeError(f"process_pending_match_csvs.py termino con codigo {p.returncode}: "
                                   f"{ultimas[-1] if ultimas else ''}")
            status, message = "COMPLETED", "Solo datasets pendientes extraidos e importados mediante el launcher."
        except Exception as e:
            status, message = "ERROR", str(e)
            with open(REPORT_ROOT / f"PROCESAR_MATCHIDS_ERRORES_{run_id}.log", "a", encoding="utf-8") as fh:
                fh.write(f"[{_ahora_iso()}] ERROR match_id={row['match_id']} country={row['country']} "
                         f"competition={row['competition']} message={message}\n")
            print(f"AVISO: [{row['match_id']}] {message}")
        state.append(_fila_estado(run_id, row, status, started, message, log_path))
        try:
            current_pending = {_match_key(r) for r in _ultimos_pendientes()}
        except Exception as e:
            with open(REPORT_ROOT / f"PROCESAR_MATCHIDS_ERRORES_{run_id}.log", "a", encoding="utf-8") as fh:
                fh.write(f"[{_ahora_iso()}] ERROR auditoria_despues_match_id={row['match_id']} message={e}\n")
            print(f"AVISO: No se pudo refrescar la auditoria despues de {row['match_id']}: {e}")

    state_path = REPORT_ROOT / f"PROCESAR_MATCHIDS_{run_id}.csv"
    with open(state_path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(state[0].keys()))
        w.writeheader()
        w.writerows(state)
    print(f"Resumen de ejecucion: {state_path}")

    print("Refrescando auditoria final...")
    _ultimos_pendientes()
    errores = sum(1 for s in state if s["status"] == "ERROR")
    completados = sum(1 for s in state if s["status"] == "COMPLETED")
    omitidos = sum(1 for s in state if s["status"] == "SKIPPED_ALREADY_PROCESSED")
    print(f"Proceso terminado. Completados: {completados}; omitidos por auditoria fresca: {omitidos}; errores: {errores}.")
    return 0


def _fila_estado(run_id, row, status, started, message, log_path):
    return {"run_id": run_id, "match_date": row["match_date"], "country": row["country"],
            "competition": row["competition"], "match_id": row["match_id"], "home_team": row["home_team"],
            "away_team": row["away_team"], "requested_datasets": row["pending_datasets"], "status": status,
            "started_at": started, "finished_at": _ahora_iso(), "message": message, "log": str(log_path)}


if __name__ == "__main__":
    sys.exit(main())
