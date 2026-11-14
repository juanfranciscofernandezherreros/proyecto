# -*- coding: utf-8 -*-
r"""Deja un unico CSV vigente por carpeta y dataset (el mas reciente) y mueve los
anteriores a un historico fuera de las carpetas que vigila el launcher (equivale a
scripts\pendientes\ARCHIVAR_CSV_REPETIDOS.ps1 + .bat, sin PowerShell).

Uso:  python scripts\py\pendientes\archivar_csv.py            (simulacion, no toca nada)
      python scripts\py\pendientes\archivar_csv.py aplicar    (mueve de verdad)
"""
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config

MARCA = re.compile(r"_\d{14}_")


def main():
    aplicar = len(sys.argv) > 1 and sys.argv[1].lower() == "aplicar"
    cfg = _config.cargar()
    roots = [
        {"source": Path(cfg["READY_DIR"]), "target": Path(cfg["READY_ROOT"]) / "historico" / "current"},
        {"source": Path(cfg["COMPETITIONS_DIR"]), "target": Path(cfg["DATA_DIR"]) / "historico" / "competitions"},
    ]

    compose = str(Path(cfg["WORKSPACE"]) / "local-validation" / "docker-compose.yml")
    p = subprocess.run(
        ["docker", "compose", "-f", compose, "exec", "-T", "postgres", "psql",
         "-U", cfg.get("DB_USER"), "-d", cfg.get("DB_NAME"), "--no-psqlrc", "-At",
         "-c", "SELECT file_path FROM public.batch_launch_request WHERE status IN ('QUEUED','RUNNING','BLOCKED')"],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        print("No se pudo consultar la cola del launcher; no se mueve nada.")
        return 1
    busy = {l.strip().lower() for l in p.stdout.splitlines() if l.strip()}

    moved, kept = 0, 0
    for root in roots:
        source = root["source"]
        if not source.is_dir():
            continue
        grupos = defaultdict(list)
        for f in source.rglob("*.csv"):
            if MARCA.search(f.name):
                clave = str(f.parent / MARCA.sub("_*_", f.name))
                grupos[clave].append(f)
        for archivos in grupos.values():
            ordenados = sorted(archivos, key=lambda p: p.stat().st_mtime, reverse=True)
            kept += 1
            for old in ordenados[1:]:
                if str(old).lower() in busy:
                    print(f"[EN COLA] {old} se deja: el launcher aun lo tiene pendiente.")
                    continue
                rel = old.parent.relative_to(source)
                target_dir = root["target"] / rel
                companions = list(old.parent.glob(f"{old.stem}.*"))
                for file in companions:
                    if aplicar:
                        target_dir.mkdir(parents=True, exist_ok=True)
                        shutil.move(str(file), str(target_dir / file.name))
                    else:
                        print(f"[SIMULACION] {file} -> {target_dir}")
                    moved += 1

    verbo = "movidos" if aplicar else "se moverian"
    print(f"Datasets con fichero vigente: {kept}. Ficheros antiguos {verbo} al historico: {moved}.")
    if not aplicar and moved:
        print("Para moverlos de verdad: ARCHIVAR_CSV_REPETIDOS.bat aplicar")
    return 0


if __name__ == "__main__":
    sys.exit(main())
