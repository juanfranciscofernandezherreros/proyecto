# -*- coding: utf-8 -*-
r"""Extrae los RESULTS de una liga y conserva la ultima jornada (equivale a
scripts\ligas\EJECUTAR_LIGA_BASKET.ps1, sin PowerShell).

Reutiliza el RESULTS de hoy si ya existe; si no, lanza el scraper. Con SkipImport
devuelve los datos del CSV sin importar; si no, importa con importar/resultados.py.

Uso:  python scripts\py\ligas\ejecutar_liga.py [CODE] [--skip-import] [--from AAAA-MM-DD --to AAAA-MM-DD]
"""
import csv
import re
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config
sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalogo
import matchday
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "importar"))
import resultados as IMP_RES

PATRON = re.compile(r"^RESULTS_\d{14}_.+\.csv$")


def _tee(cmd, log_path):
    with open(log_path, "a", encoding="utf-8") as log:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding="utf-8", errors="replace", bufsize=1)
        for linea in p.stdout:
            sys.stdout.write(linea)
            log.write(linea)
        p.wait()
    return p.returncode


def _leer(path):
    with open(path, encoding="utf-8-sig", newline="") as fh:
        r = csv.DictReader(fh)
        return list(r), r.fieldnames


def _escribir(path, filas, fieldnames):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(filas)


def _mas_reciente(paths):
    paths = list(paths)
    return max(paths, key=lambda p: p.stat().st_mtime) if paths else None


def _tiene_resultados(path):
    filas, _ = _leer(path)
    return any((f.get("eventDatetime") or "").strip() for f in filas)


def ejecutar(code, skip_import=False, from_date=None, to_date=None):
    cfg = _config.cargar()
    lg = catalogo.por_code(code)
    if not lg:
        raise ValueError(f"Liga no configurada: {code}")
    country, competition = lg["country"], lg["competition"]

    python = Path(cfg["PYTHON"])
    scraper = Path(cfg["SCRAPER"])
    competition_root = Path(cfg["COMPETITIONS_DIR"]) / country / competition
    output = competition_root / "RESULTS.csv"
    log_dir = Path(cfg["WORKSPACE"]) / "logs"
    log_path = log_dir / f"extraccion_{lg['code']}_{datetime.now():%Y%m%d_%H%M%S}.log"
    if not python.exists():
        raise ValueError(f"No se encuentra Python: {python}")
    if not scraper.exists():
        raise ValueError(f"No se encuentra el scraper: {scraper}")
    competition_root.mkdir(parents=True, exist_ok=True)
    log_dir.mkdir(parents=True, exist_ok=True)

    existentes = [p for p in competition_root.glob("*.csv")
                  if PATRON.match(p.name) and p.stat().st_size > 0]
    existing = _mas_reciente(existentes)
    existing_tiene = bool(existing) and _tiene_resultados(existing)

    marker = competition_root / "LATEST_RESULTS.json"
    hoy = date.today().strftime("%Y-%m-%d")
    if not from_date and marker.exists():
        import json
        m = json.loads(marker.read_text(encoding="utf-8"))
        if m.get("generatedOn") == hoy and Path(m.get("csvPath", "")).exists():
            print(f"RESULTS de hoy ya procesado: {m['csvPath']}")
            if skip_import:
                return {"League": lg["code"], "Country": country, "Competition": competition,
                        "CsvPath": m["csvPath"], "AlreadyProcessed": True}
            return None

    if existing and existing_tiene and \
            datetime.fromtimestamp(existing.stat().st_mtime).date() == date.today():
        csv_file = existing
        print(f"Usando RESULTS generado hoy: {csv_file}")
    else:
        print(f"Extrayendo resultados de {lg['name']}...")
        print(f"Log de extraccion: {log_path}")
        inicio = datetime.now().timestamp()
        rc = _tee([str(python), str(scraper), "competition", "results",
                   lg["resultsUrl"], "--output", str(output)], log_path)
        if rc != 0:
            raise ValueError(f"El scraper termino con codigo {rc}.")
        csv_file = _mas_reciente(p for p in competition_root.glob("*.csv")
                                 if PATRON.match(p.name) and p.stat().st_mtime >= inicio)
        if not csv_file:
            raise ValueError(f"No se encontro el RESULTS generado para {lg['code']}.")

    print(f"CSV generado: {csv_file}")
    filas, fieldnames = _leer(csv_file)
    ts = datetime.now().strftime("%Y%m%d%H%M%S")
    nuevo = competition_root / f"RESULTS_{ts}_{country}_{competition}.csv"
    if from_date or to_date:
        if not from_date or not to_date:
            raise ValueError("Debes indicar FromDate y ToDate juntos para filtrar una jornada.")
        if from_date > to_date:
            raise ValueError("FromDate no puede ser posterior a ToDate.")
        sel = [f for f in filas if (f.get("eventDatetime") or "").strip()
               and from_date <= datetime.fromisoformat(f["eventDatetime"]).date() <= to_date]
        if not sel:
            raise ValueError(f"No se encontraron resultados entre {from_date} y {to_date}.")
        _escribir(nuevo, sel, fieldnames)
        print(f"CSV filtrado: {nuevo} ({len(sel)} partidos)")
    else:
        sel = matchday.ultima_jornada(filas)
        _escribir(nuevo, sel, fieldnames)
        print(f"Ultima jornada preparada: {nuevo} ({len(sel)} partidos)")
    csv_file = nuevo

    if skip_import:
        return {"League": lg["code"], "Country": country, "Competition": competition,
                "CsvPath": str(csv_file), "MarkerPath": str(marker),
                "GeneratedOn": hoy, "AlreadyProcessed": False}

    IMP_RES.importar(str(csv_file), country, competition)
    if not from_date:
        import json
        marker.write_text(json.dumps({"generatedOn": hoy, "csvPath": str(csv_file),
                                      "league": lg["code"]}), encoding="utf-8")
    print(f"Completado: {lg['name']}")
    return None


def _parse_fecha(args, flag):
    if flag in args:
        return datetime.strptime(args[args.index(flag) + 1], "%Y-%m-%d").date()
    return None


def main():
    args = sys.argv[1:]
    code = None
    i = 0
    posicionales = []
    while i < len(args):
        if args[i] in ("--from", "--to"):
            i += 2
            continue
        if args[i] == "--skip-import":
            i += 1
            continue
        posicionales.append(args[i])
        i += 1
    code = posicionales[0] if posicionales else None
    if not code:
        ligas = catalogo.cargar_ligas()
        print("\nLigas disponibles:")
        for i, lg in enumerate(ligas, 1):
            print(f"  {i}. {lg['name']} [{lg['code']}]")
        sel = input("Elige una liga por numero: ").strip()
        if not sel.isdigit() or not (1 <= int(sel) <= len(ligas)):
            print("[ERROR] Seleccion de liga no valida.")
            return 1
        code = ligas[int(sel) - 1]["code"]
    try:
        ejecutar(code, skip_import="--skip-import" in args,
                 from_date=_parse_fecha(args, "--from"), to_date=_parse_fecha(args, "--to"))
        return 0
    except ValueError as e:
        print(f"[ERROR] {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
