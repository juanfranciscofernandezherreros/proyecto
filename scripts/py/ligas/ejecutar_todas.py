# -*- coding: utf-8 -*-
r"""Extrae e importa los RESULTS de todas las ligas en dos fases (equivale a
scripts\ligas\EJECUTAR_TODAS_LAS_LIGAS.ps1, sin PowerShell).

Fase 1: extrae cada liga (sin importar). Fase 2: importa los CSV generados.
Un fallo en una liga no detiene las demas. Codigo 1 si hubo algun fallo.

Uso:  python scripts\py\ligas\ejecutar_todas.py [--from AAAA-MM-DD --to AAAA-MM-DD]
"""
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalogo
import ejecutar_liga
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "importar"))
import resultados as IMP_RES
from launcher import FalloImport


def main():
    args = sys.argv[1:]
    from_date = ejecutar_liga._parse_fecha(args, "--from")
    to_date = ejecutar_liga._parse_fecha(args, "--to")
    if (from_date or to_date) and not (from_date and to_date):
        print("[ERROR] Debes indicar FromDate y ToDate juntos.")
        return 1
    if from_date and to_date and from_date > to_date:
        print("[ERROR] FromDate no puede ser posterior a ToDate.")
        return 1

    ligas = catalogo.cargar_ligas()
    extraccion_fallida, import_fallida, pendientes = [], [], []
    print(f"FASE 1/2: extrayendo {len(ligas)} ligas.")
    for lg in ligas:
        try:
            res = ejecutar_liga.ejecutar(lg["code"], skip_import=True,
                                         from_date=from_date, to_date=to_date)
            if res and res.get("AlreadyProcessed"):
                print(f"OMITIDA: {lg['code']}, ya procesada hoy.")
            elif res:
                pendientes.append(res)
                print(f"EXTRAIDA: {lg['code']} -> {res['CsvPath']}")
        except Exception as e:
            extraccion_fallida.append(lg["code"])
            print(f"ERROR DE EXTRACCION [{lg['code']}]: {e}")

    print("")
    print(f"FASE 2/2: importando {len(pendientes)} CSV generados.")
    for res in pendientes:
        try:
            IMP_RES.importar(res["CsvPath"], res["Country"], res["Competition"])
            Path(res["MarkerPath"]).write_text(json.dumps(
                {"generatedOn": res["GeneratedOn"], "csvPath": res["CsvPath"], "league": res["League"]}),
                encoding="utf-8")
            print(f"IMPORTADA: {res['League']}")
        except Exception as e:
            import_fallida.append(res["League"])
            print(f"ERROR DE IMPORTACION [{res['League']}]: {e}")

    print("")
    print(f"Resumen: extraccion fallida={len(extraccion_fallida)}; "
          f"importacion fallida={len(import_fallida)}; "
          f"importadas={len(pendientes) - len(import_fallida)}.")
    return 1 if extraccion_fallida or import_fallida else 0


if __name__ == "__main__":
    sys.exit(main())
