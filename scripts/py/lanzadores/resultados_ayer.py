# -*- coding: utf-8 -*-
r"""Lanzador: resultados de ayer de todas las ligas en un solo fichero.

Uso: resultados_ayer.py [AAAA-MM-DD] [--solo-csv] [--forzar]   (por defecto, ayer en Europe/Madrid)

Antes de extraer hace el cuadre previo (fixtures / Mongo, como cuadrar_dia): si todos
los partidos del dia ya estan en Mongo con su marcador, termina sin extraer; si no,
extrae solo las ligas con pendientes. --forzar se lo salta y extrae todas.

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
import os
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


def ligas_pendientes(fixtures, flashscore, mongo):
    """Cuadre previo (logica de cuadrar_dia.cuadrar). Devuelve (pendientes, total):
    las ligas ("pais/competicion") con algun partido que no esta en Mongo, no tiene
    marcador o lo tiene distinto al de Flashscore, y cuantos partidos se cuadraron.
    Las secciones (jugadas, estadisticas) no cuentan: son de los pendientes."""
    pendientes = set()
    filas = C.cuadrar(flashscore, fixtures, mongo)
    for f in filas:
        marcador = f["marcador_mongo"]
        if (f["match_id"] not in mongo or not marcador or None in marcador
                or "marcador distinto en Mongo" in f["problemas"]):
            pendientes.add(f["liga"])
    return pendientes, len(filas)


def leer_results_yesterday(salida, dia):
    """Partidos de un RESULTS_YESTERDAY ya generado, en el formato de cuadrar_dia
    ({id: {liga, local, visitante, marcador}}). Vacio si no existe."""
    if not salida.exists():
        return {}
    with open(salida, encoding="utf-8-sig", newline="") as fh:
        filas = list(csv.DictReader(fh))
    datos = C.filas_del_dia(filas, dia)
    ligas = {f.get("matchId"): f"{f.get('country')}/{f.get('competition')}" for f in filas}
    for mid, d in datos.items():
        d["liga"] = ligas.get(mid)
    return datos


def cuadre_previo(dia, salida):
    """Devuelve el conjunto de ligas que hay que extraer, o None si hay que extraer
    todas (fixtures vacio o el cuadre no se pudo hacer)."""
    try:
        fx = C.leer_fixtures(dia)
        fs = leer_results_yesterday(salida, dia)
        mg = C.leer_mongo(set(fx) | set(fs))
    except RuntimeError as e:
        print(f"AVISO: no se pudo hacer el cuadre previo ({e}); se extraen todas las ligas.")
        return None
    if not fx:
        print(f"Cuadre previo: fixtures no tiene partidos el {dia.isoformat()}; "
              "se extraen todas las ligas.")
        return None
    pendientes, total = ligas_pendientes(fx, fs, mg)
    _R["total"] = total
    print(f"Cuadre previo (fixtures / Mongo): {total} partidos el "
          f"{dia.isoformat()}; ligas con pendientes: {', '.join(sorted(pendientes)) or 'ninguna'}")
    return pendientes


# Resumen de la ejecucion, que rellenan las distintas salidas y se imprime al final
# en una sola linea RESUMEN (y se manda al bot de Telegram).
_R = {}


def linea_resumen(r):
    """Una linea con como acabo: ya estaban, n de m en Mongo, ligas con fallo o error."""
    dia = r.get("dia")
    cab = "Resultados de ayer" + (f" {dia:%d/%m}" if dia else "")
    if r.get("error"):
        return f"❌ {cab} · ERROR: {r['error']}"
    if r.get("ya"):
        return f"✅ {cab} · ya estaban los {r.get('total', 0)} en Mongo"
    partes, mal = [], bool(r.get("ligas_fallo"))
    if "en_mongo" in r:
        partes.append(f"{r['en_mongo']} de {r['cargados']} en Mongo")
        mal = mal or r["en_mongo"] < r["cargados"] or bool(r.get("cargas_fallo"))
        if r.get("cargas_fallo"):
            partes.append(f"{r['cargas_fallo']} carga(s) fallida(s)")
    elif r.get("extraidos"):
        partes.append(f"{r['extraidos']} partidos en el CSV (sin cargar)")
    else:
        partes.append("ningún partido")
    if r.get("ligas_fallo"):
        partes.append(f"{r['ligas_fallo']} liga(s) con fallo")
    return f"{'❌' if mal else '✅'} {cab} · " + " · ".join(partes)


def _avisar(linea):
    """Imprime la linea RESUMEN y la manda al bot (si esta configurado; si falla, avisa)."""
    print(f"RESUMEN: {linea}")
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "monitor"))
        import telegram_csv
        if telegram_csv.configurado():
            telegram_csv.enviar_texto(linea)
    except Exception as e:
        print(f"[AVISO] Telegram: no se pudo enviar el resumen: {e}")


def main(argv):
    _R.clear()
    try:
        rc = _ejecutar(argv)
    except Exception as e:  # cualquier fallo inesperado tambien se resume y avisa
        _R["error"] = str(e)[:200]
        rc = 1
    if rc and not _R.get("error") and not ({"en_mongo", "ya", "extraidos"} & set(_R)):
        _R["error"] = _R.get("motivo") or "ver el log"
    _avisar(linea_resumen(_R))
    if encadenar_pendientes(argv, os.environ):
        # Flujo diario sin Claude: tras los resultados, los pendientes hasta el projector.
        print("Siguiente paso: pendientes (basket pendientes)...", flush=True)
        os.environ["SKIP_CSV_WATCHER"] = "1"
        import matchids_pendientes
        rc = max(rc, matchids_pendientes.main([]))
    return rc


def encadenar_pendientes(argv, env):
    """Se encadenan los pendientes salvo con --solo-csv o RESULTADOS_AYER_PENDIENTES=0."""
    return "--solo-csv" not in argv and env.get("RESULTADOS_AYER_PENDIENTES") != "0"


def _ejecutar(argv):
    procesar = "--solo-csv" not in argv
    forzar = "--forzar" in argv
    argv = [a for a in argv if a not in ("--solo-csv", "--procesar", "--forzar")]
    if len(argv) > 1:
        print("Uso: basket resultados-ayer [AAAA-MM-DD] [--solo-csv] [--forzar]")
        _R["motivo"] = "uso incorrecto"
        return 1
    try:
        dia = C.validar_fecha(argv[0] if argv else None)
    except ValueError as e:
        print(f"ERROR: {e}")
        _R["motivo"] = str(e)
        return 1
    _R["dia"] = dia

    if ensure("antibloqueo", "postgres", "launcher", "runtime", "navegador"):
        print("ERROR: no se pudieron arrancar los servicios.")
        _R["motivo"] = "no se pudieron arrancar los servicios"
        return 1
    salida = Path(CFG.get("REPORTS_DIR")) / "resultados-ayer" / nombre_fichero(dia)
    ligas = catalogo.cargar_ligas()
    if not forzar:
        pendientes = cuadre_previo(dia, salida)
        if pendientes is not None:
            if not pendientes:
                print(f"Ya estan todos los partidos del {dia.isoformat()} en Mongo con su "
                      "marcador; no se extrae nada (--forzar para extraer igualmente).")
                _R["ya"] = True
                return 0
            ligas = [l for l in ligas if f"{l['country']}/{l['competition']}" in pendientes]

    # Las ligas que no se extraen conservan sus filas del RESULTS_YESTERDAY anterior.
    extraidas = {(l["country"], l["competition"]) for l in ligas}
    previas, cabecera_previa = [], []
    if salida.exists():
        with open(salida, encoding="utf-8-sig", newline="") as fh:
            lector = csv.DictReader(fh)
            cabecera_previa = list(lector.fieldnames or [])
            previas = [f for f in lector if (f.get("country"), f.get("competition")) not in extraidas]

    extraccion = Path(CFG.get("REPORTS_DIR")) / "resultados-ayer" / f"{dia:%Y%m%d}" / "extraccion"
    filas, cabecera, resumen = [], ["country", "competition"], []
    for col in cabecera_previa:
        if col not in cabecera:
            cabecera.append(col)
    for liga in ligas:
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

    salida.parent.mkdir(parents=True, exist_ok=True)
    with open(salida, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cabecera, extrasaction="ignore")
        w.writeheader()
        w.writerows(previas + filas)

    print(f"== RESULTADOS DEL {dia.isoformat()} ==")
    for code, n, origen in resumen:
        print(f"  {code:<9} {n:>3}  ({origen})")
    print(f"Total: {len(filas)} partidos extraidos"
          + (f" (+{len(previas)} que ya estaban)" if previas else "") + f" -> {salida}")
    _R["ligas_fallo"] = sum(1 for _, _, origen in resumen if str(origen).startswith("FALLO"))
    _R["extraidos"] = len(filas)
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
    _R.update(cargados=len(filas), en_mongo=len(filas) - mal, cargas_fallo=fallos)
    return 1 if (fallos or mal) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
