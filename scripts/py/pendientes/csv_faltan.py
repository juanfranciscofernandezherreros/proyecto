# -*- coding: utf-8 -*-
r"""CSV que faltan por generar: por cada partido pendiente de la auditoria, que datasets
faltan, que CSV hay en disco y por que no se generaron (ultimo PROCESAR_MATCHIDS).

Uso:  python scripts\py\pendientes\csv_faltan.py [match_id]
Solo lectura, salvo refrescar la auditoria (POST /run). Deja CSV_FALTAN_<stamp>.csv.
"""
import csv
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import procesar_matchids as PM

CFG = PM.CFG
# Dataset de la auditoria -> prefijos de los CSV que lo forman.
PREFIJOS = {"MATCH_SUMMARY": ("SCORE_SUMMARY_", "MATCH_DETAILS_"),
            "TEAM_STATS": ("STATS_ALL_PERIODS_",),
            "PLAYER_STATS": ("PLAYER_STATS_",),
            "POINT_BY_POINT": ("POINT_BY_POINT_",)}


def csv_en_disco(match_id, country, competition):
    """Nombres de los CSV del partido en competitions y en READY_DIR."""
    dirs = [Path(CFG["COMPETITIONS_DIR"]) / country / competition / match_id,
            Path(CFG["READY_DIR"]) / match_id]
    return sorted({p.name for d in dirs if d.is_dir() for p in d.glob(f"*_{match_id}.csv")})


def datasets_con_csv(ficheros):
    return {ds for ds, prefs in PREFIJOS.items() if any(f.startswith(prefs) for f in ficheros)}


def ultimos_intentos(report_dir):
    """match_id -> (run_id, status, message) del intento mas reciente."""
    res = {}
    for f in sorted(Path(report_dir).glob("PROCESAR_MATCHIDS_[0-9]*.csv")):
        if not f.stem.split("_")[-1].isdigit():
            continue
        with open(f, encoding="utf-8-sig", newline="") as fh:
            for r in csv.DictReader(fh):
                msg = r.get("message") or ""
                log = Path(r.get("log") or "")
                if r.get("status") == "ERROR" and "(No symbol)" in msg and log.is_file():
                    msg = PM.motivo_error(log.read_text(encoding="utf-8", errors="replace").splitlines())
                res[r.get("match_id")] = (r.get("run_id"), r.get("status"), msg.strip())
    return res


def motivo(intento):
    if not intento:
        return "nunca se ha intentado con basket pendientes"
    run_id, status, msg = intento
    if status == "COMPLETED":
        return f"{run_id} COMPLETED pero sigue pendiente (Flashscore no lo publica o no se cargo)"
    return f"{run_id} {status}: {msg[:160]}"


def filas(pendientes, intentos):
    out = []
    for r in pendientes:
        fich = csv_en_disco(r["match_id"], r["country"], r["competition"])
        con = datasets_con_csv(fich)
        faltan = [d for d in (r["pending_datasets"] or "").split(",") if d]
        out.append({**r, "sin_csv": ",".join(d for d in faltan if d not in con),
                    "con_csv_sin_cargar": ",".join(d for d in faltan if d in con),
                    "csv_en_disco": len(fich), "motivo": motivo(intentos.get(r["match_id"]))})
    return out


def main(argv):
    solo = argv[0] if argv else None
    pendientes = [r for r in PM._ultimos_pendientes() if not solo or r["match_id"] == solo]
    res = filas(pendientes, ultimos_intentos(CFG["REPORT_DIR"]))
    if solo and not res:
        print(f"{solo}: la auditoria no lo marca como pendiente (no le falta ningun CSV).")
        return 0
    for f in res:
        print(f"{f['match_id']} {f['match_date']} {f['country']}/{f['competition']} "
              f"{f['home_team']} - {f['away_team']}\n   sin CSV: {f['sin_csv'] or '-'} · "
              f"CSV sin cargar: {f['con_csv_sin_cargar'] or '-'} · motivo: {f['motivo']}")
    if res:
        salida = Path(CFG["REPORT_DIR"]) / f"CSV_FALTAN_{datetime.now():%Y%m%d%H%M%S}.csv"
        with open(salida, "w", encoding="utf-8-sig", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(res[0].keys()))
            w.writeheader()
            w.writerows(res)
        print(f"Informe: {salida}")
    nunca = sum(1 for f in res if f["motivo"].startswith("nunca"))
    err = sum(1 for f in res if " ERROR:" in f["motivo"])
    print(f"RESUMEN: {len(res)} partidos con CSV por generar · {err} fallaron en el ultimo intento"
          f" · {nunca} nunca intentados")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
