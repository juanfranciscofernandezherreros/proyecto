# -*- coding: utf-8 -*-
r"""Extrae POINT_BY_POINT siguiendo la redireccion de Flashscore (resolvedor), tomando
las primeras [limite] filas del RESULTS mas reciente que aun no esten en PostgreSQL
(equivale a scripts\extraer\EXTRAER_POINT_BY_POINT.bat, sin PowerShell).

A diferencia de play_by_play.py (URL por slugs, orden por fecha), este usa el
resolvedor para la URL canonica y recorre el RESULTS en orden de fichero.

Uso:  python scripts\py\extraer\point_by_point.py [pais] [competicion] [limite]
"""
import csv
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config
import proc
sys.path.insert(0, str(Path(__file__).resolve().parent))
import ya_importados as YI
from dataset import _mas_reciente, _run_tee, _tiene_filas


def main():
    args = sys.argv[1:]
    country = args[0] if len(args) > 0 else "europe"
    competition = args[1] if len(args) > 1 else "euroleague"
    try:
        limit = proc.validar_limite(args[2] if len(args) > 2 else "20", 20)
    except ValueError as e:
        print(f"[ERROR] {e}")
        return 1

    cfg = _config.cargar()
    python = Path(cfg["PYTHON"])
    scraper = Path(cfg["SCRAPER"])
    resolver = Path(cfg["WORKSPACE"]) / "python" / "resolve_flashscore_redirect.py"
    results_dir = Path(cfg["COMPETITIONS_DIR"]) / country / competition

    for ruta, etiqueta in ((python, "Python"), (scraper, "el scraper"),
                           (resolver, "el resolvedor"), (results_dir, "la carpeta")):
        if not ruta.exists():
            print(f"[ERROR] No se encuentra {etiqueta}: {ruta}")
            return 1

    results_csv = _mas_reciente(results_dir.glob(f"RESULTS_*_{country}_{competition}.csv"))
    if not results_csv:
        print(f"[ERROR] No hay RESULTS para {country}/{competition}.")
        return 1

    print(f"RESULTS seleccionado: {results_csv}")
    print(f"Flujo: ID > Point by Point > cuartos. Limite: {limit}")
    imported = set(YI.ya_importados("POINT_BY_POINT"))

    with open(results_csv, encoding="utf-8-sig", newline="") as fh:
        reader = csv.reader(fh)
        next(reader, None)  # cabecera
        filas = [r[0].strip() for r in reader if r and r[0].strip()]

    count, failed = 0, False
    for match_id in filas:
        if count >= limit:
            break
        if match_id in imported:
            print(f"[{match_id}] ya importado; se salta.")
            continue
        count += 1
        r = subprocess.run([str(python), str(resolver), match_id],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        url = r.stdout.strip()
        if r.returncode != 0 or not url:
            print(f"[ERROR] [{match_id}] Flashscore no devolvio la URL canonica.")
            failed = True
            continue
        print(f"\n[{count}/{limit}] ID: {match_id}")
        print(f"Redirigido a: {url}")
        output = results_dir / f"POINT_BY_POINT_{match_id}.csv"
        ok = False
        for intento in range(1, 4):
            if ok:
                break
            print(f"[{match_id}] POINT_BY_POINT intento {intento}/3")
            rc = _run_tee([str(python), str(scraper), "match", "quarters", url,
                           "--mid", match_id, "--output", str(output)], Path("nul"))
            if rc != 0:
                print(f"[WARN] [{match_id}] Extraccion POINT_BY_POINT fallida; se reintentara.")
                continue
            csv_f = _mas_reciente(list(results_dir.glob(f"POINT_BY_POINT_*{match_id}.csv")) +
                                  ([output] if output.exists() else []))
            if csv_f and _tiene_filas(csv_f):
                ok = True
            else:
                print(f"[WARN] [{match_id}] CSV vacio; se reintentara.")
        if not ok:
            print(f"[ERROR] [{match_id}] Sin POINT_BY_POINT tras 3 intentos.")
            failed = True

    if count == 0:
        print("Todos los partidos del RESULTS ya tienen POINT_BY_POINT. No se extrae nada.")
        return 0
    if failed:
        return 1
    print(f"\nOK. POINT_BY_POINT generado junto a RESULTS en: {results_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
