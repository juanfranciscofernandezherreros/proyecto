# -*- coding: utf-8 -*-
r"""Lanzador: cuadrar los partidos de un dia entre Flashscore, fixtures y Mongo.

Uso: cuadrar_dia.py [AAAA-MM-DD]     (por defecto, ayer en Europe/Madrid)

- Flashscore: ultimo RESULTS_*.csv de cada liga del catalogo (lo que publica
  Flashscore en el momento de la extraccion).
- fixtures:   fixtures.fixtures en Postgres (fecha local Europe/Madrid).
- Mongo:      basketball.matches (lo que ensena la web): marcador y secciones.

Devuelve 0 si todo cuadra y 1 si hay algun problema (o falta algun dato).
Solo lectura.
"""
import csv
import json
import re
import subprocess
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from _base import CFG

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ligas import catalogo

MADRID = ZoneInfo("Europe/Madrid")
FECHA = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SECCIONES = ("fixture", "result", "summary", "players", "teamStats", "pointByPoint")


# ---------------------------------------------------------------- logica pura

def validar_fecha(texto):
    if texto is None:
        return datetime.now(MADRID).date() - timedelta(days=1)
    if not FECHA.match(texto):
        raise ValueError(f"Fecha no valida: {texto!r} (esperado AAAA-MM-DD)")
    return datetime.strptime(texto, "%Y-%m-%d").date()


def _entero(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def filas_del_dia(filas, dia):
    """Filas de un RESULTS CSV cuyo eventDatetime (con offset) cae en `dia` en Madrid."""
    out = {}
    for f in filas:
        texto = (f.get("eventDatetime") or "").strip()
        if not texto:
            continue
        try:
            dt = datetime.fromisoformat(texto)
        except ValueError:
            continue
        local = dt.astimezone(MADRID) if dt.tzinfo else dt
        if local.date() == dia:
            out[f["matchId"]] = {
                "local": f.get("homeTeam"), "visitante": f.get("awayTeam"),
                "marcador": (_entero(f.get("homeScore")), _entero(f.get("awayScore"))),
            }
    return out


def cuadrar(flashscore, fixtures, mongo):
    """Compara las tres fuentes. Devuelve una lista ordenada de dicts por partido:
    {match_id, liga, local, visitante, marcador_fs, marcador_mongo, problemas[]}.

    flashscore: {id: {liga, local, visitante, marcador}}
    fixtures:   {id: {liga, local, visitante}}
    mongo:      {id: {marcador, secciones}}
    """
    out = []
    for mid in sorted(set(flashscore) | set(fixtures)):
        fs, fx, mg = flashscore.get(mid), fixtures.get(mid), mongo.get(mid)
        base = fs or fx
        problemas = []
        if fs is None:
            problemas.append("no esta en Flashscore")
        if fx is None:
            problemas.append("no esta en fixtures")
        if mg is None:
            problemas.append("no esta en Mongo")
        else:
            if fs is not None and mg.get("marcador") != fs.get("marcador"):
                problemas.append("marcador distinto en Mongo")
            faltan = [s for s in SECCIONES if s not in (mg.get("secciones") or [])]
            if faltan:
                problemas.append("faltan secciones: " + ", ".join(faltan))
        out.append({
            "match_id": mid, "liga": base.get("liga"),
            "local": base.get("local"), "visitante": base.get("visitante"),
            "marcador_fs": fs.get("marcador") if fs else None,
            "marcador_mongo": mg.get("marcador") if mg else None,
            "problemas": problemas,
        })
    return out


# ---------------------------------------------------------------- lectura

def ultimo_results(liga):
    carpeta = Path(CFG.get("COMPETITIONS_DIR")) / liga["country"] / liga["competition"]
    csvs = sorted(carpeta.glob("RESULTS_*.csv"), key=lambda p: p.stat().st_mtime)
    return csvs[-1] if csvs else None


def leer_flashscore(dia, avisos):
    datos = {}
    fin_dia = datetime.combine(dia + timedelta(days=1), datetime.min.time(), MADRID)
    for liga in catalogo.cargar_ligas():
        nombre = f"{liga['country']}/{liga['competition']}"
        fichero = ultimo_results(liga)
        if fichero is None:
            avisos.append(f"{nombre}: no hay RESULTS_*.csv")
            continue
        generado = datetime.fromtimestamp(fichero.stat().st_mtime, MADRID)
        if generado < fin_dia:
            avisos.append(f"{nombre}: el ultimo RESULTS es de {generado:%Y-%m-%d %H:%M}, "
                          "anterior al final del dia (extraer con basket resultados ALL)")
        with open(fichero, encoding="utf-8-sig", newline="") as fh:
            for mid, d in filas_del_dia(csv.DictReader(fh), dia).items():
                d["liga"] = nombre
                datos[mid] = d
    return datos


def leer_fixtures(dia):
    sql = ("SELECT match_id, country || '/' || competition, home_team, away_team "
           "FROM fixtures.fixtures "
           f"WHERE (event_datetime AT TIME ZONE 'Europe/Madrid')::date = DATE '{dia.isoformat()}' "
           "ORDER BY match_id;")
    p = subprocess.run(
        ["docker", "exec", "-i", CFG.get("POSTGRES_CONTAINER"), "psql", "-U", CFG.get("DB_USER"),
         "-d", CFG.get("DB_NAME"), "--no-psqlrc", "-At", "-F", "\t", "-c", sql],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise RuntimeError("No se pudo consultar fixtures: " + p.stderr.strip())
    datos = {}
    for linea in p.stdout.splitlines():
        partes = linea.split("\t")
        if len(partes) == 4:
            datos[partes[0]] = {"liga": partes[1], "local": partes[2], "visitante": partes[3]}
    return datos


def leer_mongo(ids):
    if not ids:
        return {}
    js = ("const ids=" + json.dumps(sorted(ids)) + ";"
          "db.matches.find({_id:{$in:ids}},{result:1,availableSections:1}).forEach(m=>"
          "print(JSON.stringify({id:m._id,h:m.result?m.result.homeScore:null,"
          "a:m.result?m.result.awayScore:null,s:m.availableSections||[]})))")
    contenedor = CFG.get("MONGO_CONTAINER") or "local-validation-mongo-1"
    p = subprocess.run(["docker", "exec", "-i", contenedor, "mongosh", "basketball", "--quiet",
                        "--eval", js],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise RuntimeError("No se pudo consultar Mongo: " + p.stderr.strip())
    datos = {}
    for linea in p.stdout.splitlines():
        if linea.startswith("{"):
            d = json.loads(linea)
            datos[d["id"]] = {"marcador": (_entero(d["h"]), _entero(d["a"])), "secciones": d["s"]}
    return datos


# ---------------------------------------------------------------- salida

def _m(par):
    return "-" if not par or None in par else f"{par[0]}-{par[1]}"


def main(argv):
    if len(argv) > 1:
        print("Uso: basket cuadrar [AAAA-MM-DD]")
        return 1
    try:
        dia = validar_fecha(argv[0] if argv else None)
        avisos = []
        fs = leer_flashscore(dia, avisos)
        fx = leer_fixtures(dia)
        mg = leer_mongo(set(fs) | set(fx))
    except (ValueError, RuntimeError) as e:
        print(f"ERROR: {e}")
        return 1

    filas = cuadrar(fs, fx, mg)
    print(f"== CUADRE DEL {dia.isoformat()} (Flashscore / fixtures / Mongo) ==")
    for f in filas:
        estado = "OK   " if not f["problemas"] else "FALLO"
        print(f"  {estado} {f['match_id']}  {f['liga']:<22} {f['local']} - {f['visitante']}  "
              f"FS {_m(f['marcador_fs'])}  Mongo {_m(f['marcador_mongo'])}"
              + ("" if not f["problemas"] else "  -> " + "; ".join(f["problemas"])))
    if avisos:
        print("== AVISOS ==")
        for a in avisos:
            print("  " + a)
    malos = sum(1 for f in filas if f["problemas"])
    print(f"== RESUMEN == Flashscore {len(fs)}, fixtures {len(fx)}, Mongo {len(mg)}; "
          f"{len(filas) - malos} cuadran, {malos} con problemas.")
    if malos == 0:
        print("TODO CUADRA" + (" (revisar los avisos)" if avisos else ""))
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
