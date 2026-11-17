# -*- coding: utf-8 -*-
r"""Lanzador: resultados de ayer de todas las ligas en un solo fichero.

Uso: resultados_ayer.py [AAAA-MM-DD] [--solo-csv]   (por defecto, ayer en Europe/Madrid)

Sin opciones lo hace todo: extrae de Flashscore los resultados de cada liga (en una
carpeta temporal, sin tocar competitions\), se queda con los partidos de ese dia y
los junta en un unico CSV; lo carga en Postgres, espera al projector y comprueba en
Mongo que cada partido esta con su marcador. Con --solo-csv solo genera el CSV.

El CSV unico es
   REPORTS_DIR\resultados-ayer\RESULTS_YESTERDAY_<AAAAMMDD>.csv
   (columnas del RESULTS con country y competition delante).

El fichero va fuera de competitions\ para que la importacion de RESULTS no lo recoja.
"""
import csv
import sys
from datetime import datetime
from pathlib import Path

from _base import CFG, ensure
import cuadrar_dia as C

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ligas import catalogo


def filas_de_liga(filas, dia, country, competition):
    """Filas (dict) de un RESULTS cuyo eventDatetime cae en `dia` (Madrid), con la liga delante."""
    out = []
    for f in filas:
        texto = (f.get("eventDatetime") or "").strip()
        try:
            dt = datetime.fromisoformat(texto)
        except ValueError:
            continue
        if (dt.astimezone(C.MADRID) if dt.tzinfo else dt).date() == dia:
            out.append({"country": country, "competition": competition, **f})
    return out


def extraer_liga(liga, carpeta):
    """Extrae de Flashscore los resultados de una liga en `carpeta` (fuera de
    competitions\\, para no tocar los RESULTS de la liga). Devuelve el CSV generado."""
    import subprocess
    import time
    carpeta.mkdir(parents=True, exist_ok=True)
    inicio = time.time()
    rc = subprocess.run([CFG.get("PYTHON"), CFG.get("SCRAPER"), "competition", "results",
                         liga["resultsUrl"], "--output", str(carpeta / "RESULTS.csv")]).returncode
    if rc != 0:
        raise RuntimeError(f"el scraper termino con codigo {rc}")
    cands = [p for p in carpeta.glob("RESULTS_*.csv") if p.stat().st_mtime >= inicio]
    if not cands:
        raise RuntimeError("el scraper no genero el CSV")
    return max(cands, key=lambda p: p.stat().st_mtime)


def nombre_fichero(dia):
    return f"RESULTS_YESTERDAY_{dia:%Y%m%d}.csv"


def main(argv):
    procesar = "--solo-csv" not in argv
    argv = [a for a in argv if a not in ("--solo-csv", "--procesar")]
    if len(argv) > 1:
        print("Uso: basket resultados-ayer [AAAA-MM-DD] [--solo-csv]")
        return 1
    try:
        dia = C.validar_fecha(argv[0] if argv else None)
    except ValueError as e:
        print(f"ERROR: {e}")
        return 1

    if ensure("antibloqueo", "postgres", "launcher", "runtime", "navegador"):
        print("ERROR: no se pudieron arrancar los servicios.")
        return 1
    extraccion = Path(CFG.get("REPORTS_DIR")) / "resultados-ayer" / f"{dia:%Y%m%d}" / "extraccion"
    filas, cabecera, resumen = [], ["country", "competition"], []
    for liga in catalogo.cargar_ligas():
        print(f"Extrayendo de Flashscore [{liga['code']}]...")
        try:
            fichero = extraer_liga(liga, extraccion / liga["code"])
        except RuntimeError as e:
            print(f"[FALLO] [{liga['code']}] {e}")
            resumen.append((liga["code"], 0, f"FALLO: {e}"))
            continue
        with open(fichero, encoding="utf-8-sig", newline="") as fh:
            lector = csv.DictReader(fh)
            for col in lector.fieldnames or []:
                if col not in cabecera:
                    cabecera.append(col)
            de_liga = filas_de_liga(lector, dia, liga["country"], liga["competition"])
        filas.extend(de_liga)
        resumen.append((liga["code"], len(de_liga), fichero.name))

    salida = Path(CFG.get("REPORTS_DIR")) / "resultados-ayer" / nombre_fichero(dia)
    salida.parent.mkdir(parents=True, exist_ok=True)
    with open(salida, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cabecera, extrasaction="ignore")
        w.writeheader()
        w.writerows(filas)

    print(f"== RESULTADOS DEL {dia.isoformat()} ==")
    for code, n, origen in resumen:
        print(f"  {code:<9} {n:>3}  ({origen})")
    print(f"Total: {len(filas)} partidos -> {salida}")
    if procesar:
        return procesar_en_postgres(salida, cabecera, filas, dia)
    return 0


def procesar_en_postgres(salida, cabecera, filas, dia):
    """Carga RESULTS_YESTERDAY en Postgres: el launcher importa RESULTS por liga, asi
    que se parte en un RESULTS_<ts>_<pais>_<competicion>.csv por liga (junto al
    RESULTS_YESTERDAY, no en competitions\\) y se envia cada uno."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "importar"))
    import launcher as L
    if not filas:
        print("No hay partidos que procesar.")
        return 0
    cfg = dict(CFG)
    L.asegurar_servicios("postgres", "launcher")
    carpeta = salida.parent / f"{dia:%Y%m%d}"
    carpeta.mkdir(parents=True, exist_ok=True)
    columnas = [c for c in cabecera if c not in ("country", "competition")]
    ts = datetime.now().strftime("%Y%m%d%H%M%S")
    fallos = 0
    for (country, comp) in sorted({(f["country"], f["competition"]) for f in filas}):
        de_liga = [f for f in filas if (f["country"], f["competition"]) == (country, comp)]
        parte = carpeta / f"RESULTS_{ts}_{country}_{comp}.csv"
        with open(parte, "w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=columnas, extrasaction="ignore")
            w.writeheader()
            w.writerows(de_liga)
        try:
            r = L.submit_and_wait(cfg, parte, timeout_min=3)
            estado = r.get("status")
        except Exception as e:
            estado = f"FALLO ({e})"
        if estado != "COMPLETED":
            fallos += 1
        print(f"  PROCESAR {country}/{comp}: {len(de_liga)} partidos -> {estado}")
    print("Procesado en Postgres: " + ("OK" if not fallos else f"{fallos} liga(s) con fallo"))

    # Hasta el projector: el projector pasa Postgres -> Mongo cada ~60 s.
    import time
    espera = int(CFG.get("CICLO_ESPERA_CUADRE") or 90)
    print(f"Esperando {espera} s a que el projector lo lleve a Mongo...")
    time.sleep(espera)
    mongo = C.leer_mongo({f["matchId"] for f in filas})
    mal = 0
    for f in filas:
        esperado = (C._entero(f.get("homeScore")), C._entero(f.get("awayScore")))
        m = mongo.get(f["matchId"])
        if m is None:
            estado = "NO ESTA EN MONGO"
        elif m["marcador"] != esperado:
            estado = f"MARCADOR DISTINTO EN MONGO ({C._m(m['marcador'])})"
        else:
            estado = "OK"
        mal += estado != "OK"
        print(f"  {estado:<5} {f['matchId']}  {f['country']}/{f['competition']}  "
              f"{f.get('homeTeam')} - {f.get('awayTeam')}  {C._m(esperado)}")
    print(f"En Mongo (projector): {len(filas) - mal} de {len(filas)} con su marcador.")
    return 1 if (fallos or mal) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
