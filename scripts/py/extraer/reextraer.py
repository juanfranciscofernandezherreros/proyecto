# -*- coding: utf-8 -*-
r"""Reextrae de Flashscore los datasets de partidos concretos y los reimporta en
PostgreSQL, aunque ya esten importados. Los demas extractores saltan los partidos que
ya tienen filas; este no, y sirve para corregir partidos cuyos datos estan mal.

Pais y competicion se leen de results.results (o de fixtures.fixtures). Un fallo en un
partido no detiene los demas.

Uso:  python scripts\py\extraer\reextraer.py [--dataset equipo|jugadores|resumen|jugadas|todo|h2h-cuotas]
                                             [--fichero lista.txt] [--progreso progreso.txt] <match_id...>
      --dataset  por defecto: todo (equipo, jugadores, resumen y jugadas).
                 h2h-cuotas: H2H y los 4 mercados de cuotas en una sola sesión del
                 navegador; sirve también para partidos aún sin jugar. Un CSV vacío de
                 estos (p. ej. la NBA no ofrece 1X2) se anota como OK «sin datos».
      --fichero  un match_id por linea (se ignora lo que haya tras un '|')
      --progreso fichero donde se anota cada partido y dataset (OK o FALLO). Si ya
                 existe, lo anotado como OK se salta: sirve para retomar un lote largo.
"""
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "importar"))
import config as _config
import launcher as L
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import seguimiento

# nombre -> (etiqueta, dataset del scraper o None si va por 'match quarters', prefijo del CSV)
DATASETS = {
    "equipo":    ("TEAM_STATS",     "stats_all_periods.csv", "STATS_ALL_PERIODS"),
    "jugadores": ("PLAYER_STATS",   "player_stats.csv",      "PLAYER_STATS"),
    "resumen":   ("MATCH_SUMMARY",  "score_summary.csv",     "SCORE_SUMMARY"),
    "jugadas":   ("POINT_BY_POINT", None,                    "POINT_BY_POINT"),
    # H2H y cuotas: van juntos en una sola llamada al bundle (ver _extraer_juntos).
    "h2h":            ("H2H",                 "h2h.csv",                 "H2H"),
    "cuota-ganador":  ("ODDS_HOME_AWAY",      "odds_home_away.csv",      "ODDS_HOME_AWAY"),
    "cuota-1x2":      ("ODDS_1X2",            "odds_1x2.csv",            "ODDS_1X2"),
    "cuota-total":    ("ODDS_OVER_UNDER",     "odds_over_under.csv",     "ODDS_OVER_UNDER"),
    "cuota-handicap": ("ODDS_ASIAN_HANDICAP", "odds_asian_handicap.csv", "ODDS_ASIAN_HANDICAP"),
}
# Grupos de --dataset. «todo» no cambia (lo usa datos_ayer).
GRUPOS = {
    "todo": ["equipo", "jugadores", "resumen", "jugadas"],
    "h2h-cuotas": ["h2h", "cuota-ganador", "cuota-1x2", "cuota-total", "cuota-handicap"],
}
# Datasets que pueden venir vacíos sin que sea un fallo y que se extraen juntos.
OPCIONALES = set(GRUPOS["h2h-cuotas"])
ID_VALIDO = re.compile(r"^[A-Za-z0-9_-]{4,20}$")


class Fallo(Exception):
    pass


def _mas_reciente(paths):
    paths = list(paths)
    return max(paths, key=lambda p: p.stat().st_mtime) if paths else None


def _tiene_filas(path):
    with open(path, encoding="utf-8-sig") as fh:
        next(fh, None)
        return bool((next(fh, "") or "").strip())


def _ligas(cfg, match_ids):
    """Devuelve {match_id: (pais, competicion)} leyendo results y, si falta, fixtures."""
    lista = ",".join(f"'{m}'" for m in match_ids)  # ids ya validados con ID_VALIDO
    sql = (f"SELECT match_id, country, competition FROM results.results "
           f"WHERE match_id IN ({lista}) AND coalesce(country,'') <> '' AND coalesce(competition,'') <> '' "
           f"UNION ALL SELECT match_id, country, competition FROM fixtures.fixtures f "
           f"WHERE match_id IN ({lista}) AND NOT EXISTS (SELECT 1 FROM results.results r "
           f"WHERE r.match_id = f.match_id AND coalesce(r.country,'') <> '' AND coalesce(r.competition,'') <> '')")
    p = subprocess.run(
        ["docker", "compose", "-f", cfg.get("COMPOSE_FILE"), "exec", "-T", "postgres",
         "psql", "-U", cfg.get("DB_USER"), "-d", cfg.get("DB_NAME"), "--no-psqlrc", "-At", "-c", sql],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise Fallo("No se pudo leer la liga de los partidos en PostgreSQL.")
    ligas = {}
    for linea in p.stdout.splitlines():
        partes = linea.strip().split("|")
        if len(partes) == 3 and partes[1] and partes[2]:
            ligas.setdefault(partes[0], (partes[1], partes[2]))
    return ligas


def _url(python, resolver, match_id):
    r = subprocess.run([str(python), str(resolver), match_id], capture_output=True,
                       text=True, encoding="utf-8", errors="replace", timeout=120)
    url = r.stdout.strip()
    if r.returncode != 0 or not url:
        raise Fallo("Flashscore no devolvio la URL canonica")
    return url


def _extraer(cfg, env, nombre, match_id, url, raiz):
    """Extrae un dataset de un partido (hasta 3 intentos). Devuelve el CSV generado."""
    _etiqueta, dataset, prefijo = DATASETS[nombre]
    python, scraper = Path(cfg["PYTHON"]), Path(cfg["SCRAPER"])
    if dataset:
        cmd = [str(python), str(scraper), "match", "bundle", url,
               "--data-dir", str(raiz), "--dataset", dataset]
        candidatos = lambda: (raiz / match_id).glob(f"{prefijo}_*.csv")
    else:
        salida = raiz / f"POINT_BY_POINT_{match_id}.csv"
        cmd = [str(python), str(scraper), "match", "quarters", url,
               "--mid", match_id, "--output", str(salida)]
        candidatos = lambda: raiz.glob(f"POINT_BY_POINT_*{match_id}.csv")
    ultimo = ""
    for _intento in range(3):
        inicio = time.time() - 2
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=900, env=env)
        if p.returncode != 0:
            ultimo = "scraper rc=%s: %s" % (p.returncode, (p.stdout + p.stderr)[-200:].replace("\n", " "))
            continue
        csv_f = _mas_reciente(candidatos())
        if csv_f and csv_f.stat().st_mtime >= inicio and _tiene_filas(csv_f):
            return csv_f
        ultimo = "CSV vacio"
    raise Fallo(f"{ultimo} tras 3 intentos")


def _extraer_juntos(cfg, env, nombres, match_id, url, raiz):
    """Extrae varios datasets opcionales con una sola llamada al bundle (un navegador).

    Devuelve {nombre: CSV con filas o None si salió vacío}. Reintenta hasta 3 veces
    mientras falte algún CSV; lanza Fallo con los que sigan sin generarse.
    """
    python, scraper = Path(cfg["PYTHON"]), Path(cfg["SCRAPER"])
    resultado, ultimo = {}, ""
    pendientes = list(nombres)
    for _intento in range(3):
        inicio = time.time() - 2
        cmd = [str(python), str(scraper), "match", "bundle", url, "--data-dir", str(raiz)]
        for nombre in pendientes:
            cmd += ["--dataset", DATASETS[nombre][1]]
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=900, env=env)
        if p.returncode not in (0, 3):  # 3 = extracción parcial: se recoge lo que haya
            ultimo = "scraper rc=%s: %s" % (p.returncode, (p.stdout + p.stderr)[-200:].replace("\n", " "))
        for nombre in list(pendientes):
            csv_f = _mas_reciente((raiz / match_id).glob(f"{DATASETS[nombre][2]}_*.csv"))
            if csv_f and csv_f.stat().st_mtime >= inicio:
                resultado[nombre] = csv_f if _tiene_filas(csv_f) else None
                pendientes.remove(nombre)
        if not pendientes:
            return resultado
        ultimo = ultimo or "sin CSV de " + ", ".join(DATASETS[n][0] for n in pendientes)
    raise Fallo(f"{ultimo} tras 3 intentos", resultado)


def _leer_progreso(progreso):
    """Devuelve el conjunto de (match_id, etiqueta) ya anotados como OK."""
    hechos = set()
    if progreso and progreso.exists():
        for linea in progreso.read_text(encoding="utf-8").splitlines():
            partes = linea.split("|")
            if len(partes) >= 3 and partes[2] == "OK":
                hechos.add((partes[0], partes[1]))
    return hechos


def _anotar(progreso, match_id, etiqueta, estado, detalle):
    if progreso:
        with open(progreso, "a", encoding="utf-8") as fh:
            fh.write(f"{match_id}|{etiqueta}|{estado}|{detalle}\n")


def reextraer(match_ids, nombres, progreso=None):
    cfg = _config.cargar()
    python, scraper = Path(cfg["PYTHON"]), Path(cfg["SCRAPER"])
    resolver = Path(cfg["WORKSPACE"]) / "python" / "resolve_flashscore_redirect.py"
    for ruta in (python, scraper, resolver):
        if not ruta.exists():
            print(f"[ERROR] No se encuentra: {ruta}")
            return 1
    # El scraper lee el navegador y la ruta del driver del entorno.
    env = dict(os.environ)
    for clave in ("FLASHSCORE_BROWSER", "EDGEDRIVER_PATH"):
        if cfg.get(clave):
            env[clave] = str(cfg[clave])

    try:
        ligas = _ligas(cfg, match_ids)
    except Fallo as e:
        print(f"[ERROR] {e}")
        return 1

    hechos = _leer_progreso(progreso)
    if hechos:
        antes = len(match_ids)
        match_ids = [m for m in match_ids
                     if any((m, DATASETS[n][0]) not in hechos for n in nombres)]
        print(f"Progreso en {progreso}: {antes - len(match_ids)} partidos ya completos; se saltan.", flush=True)
    total = len(match_ids)
    print(f"Partidos a reextraer: {total}. Datasets: {', '.join(DATASETS[n][0] for n in nombres)}", flush=True)
    ok = fallo = 0
    run_id = "reextraer-" + time.strftime("%Y%m%d%H%M%S")
    for n, match_id in enumerate(match_ids, 1):
        if match_id not in ligas:
            print(f"[{n}/{total}] {match_id} FALLO no esta en results ni en fixtures (sin pais/competicion)", flush=True)
            for nombre in nombres:
                _anotar(progreso, match_id, DATASETS[nombre][0], "FALLO", "sin pais/competicion")
            fallo += len(nombres)
            continue
        country, competition = ligas[match_id]
        raiz = Path(cfg["COMPETITIONS_DIR"]) / country / competition
        raiz.mkdir(parents=True, exist_ok=True)
        try:
            url = _url(python, resolver, match_id)
        except (Fallo, subprocess.TimeoutExpired) as e:
            print(f"[{n}/{total}] {match_id} {country}/{competition} FALLO {e}", flush=True)
            for nombre in nombres:
                _anotar(progreso, match_id, DATASETS[nombre][0], "FALLO", str(e)[:200])
            fallo += len(nombres)
            continue
        juntos = [n for n in nombres if n in OPCIONALES and (match_id, DATASETS[n][0]) not in hechos]
        extraidos = {}
        paso_juntos, fallo_antes, resumen_juntos = None, fallo, []
        if juntos:
            # Un paso por partido en el panel del orquestador de Grafana (Procesamiento en vivo).
            paso_juntos = seguimiento.empezar(cfg, run_id, f"{country}/{competition}", country, competition,
                                              f"H2H+CUOTAS {match_id}")
            try:
                extraidos = _extraer_juntos(cfg, env, juntos, match_id, url, raiz)
            except Fallo as e:
                extraidos = e.args[1] if len(e.args) > 1 else {}
                for nombre in juntos:
                    if nombre not in extraidos:
                        etiqueta = DATASETS[nombre][0]
                        print(f"[{n}/{total}] {match_id} {country}/{competition} {etiqueta} FALLO {str(e.args[0])[:300]}", flush=True)
                        _anotar(progreso, match_id, etiqueta, "FALLO", " ".join(str(e.args[0])[:200].split()))
                        fallo += 1
            except subprocess.TimeoutExpired as e:
                for nombre in juntos:
                    _anotar(progreso, match_id, DATASETS[nombre][0], "FALLO", "tiempo agotado")
                print(f"[{n}/{total}] {match_id} {country}/{competition} FALLO tiempo agotado ({e.timeout}s)", flush=True)
                fallo += len(juntos)
        for nombre in nombres:
            etiqueta = DATASETS[nombre][0]
            if (match_id, etiqueta) in hechos:
                continue
            if nombre in OPCIONALES:
                if nombre not in extraidos:
                    continue  # ya anotado como fallo
                csv_f = extraidos[nombre]
                if csv_f is None:
                    print(f"[{n}/{total}] {match_id} {country}/{competition} {etiqueta} OK sin datos", flush=True)
                    _anotar(progreso, match_id, etiqueta, "OK", "sin datos")
                    resumen_juntos.append(f"{etiqueta} sin datos")
                    ok += 1
                    continue
                try:
                    resp = L.submit_and_wait(cfg, csv_f, timeout_min=15)
                    if resp.get("status") != "COMPLETED":
                        raise Fallo(f"launcher {resp.get('status')}")
                    print(f"[{n}/{total}] {match_id} {country}/{competition} {etiqueta} OK {csv_f.name}", flush=True)
                    _anotar(progreso, match_id, etiqueta, "OK", csv_f.name)
                    resumen_juntos.append(f"{etiqueta} OK")
                    ok += 1
                except Exception as e:  # se anota y se sigue
                    print(f"[{n}/{total}] {match_id} {country}/{competition} {etiqueta} FALLO {str(e)[:300]}", flush=True)
                    _anotar(progreso, match_id, etiqueta, "FALLO", " ".join(str(e)[:200].split()))
                    fallo += 1
                continue
            paso = seguimiento.empezar(cfg, run_id, f"{country}/{competition}", country, competition,
                                       f"{etiqueta} {match_id}")
            try:
                csv_f = _extraer(cfg, env, nombre, match_id, url, raiz)
                resp = L.submit_and_wait(cfg, csv_f, timeout_min=15)
                if resp.get("status") != "COMPLETED":
                    raise Fallo(f"launcher {resp.get('status')}")
                print(f"[{n}/{total}] {match_id} {country}/{competition} {etiqueta} OK {csv_f.name}", flush=True)
                _anotar(progreso, match_id, etiqueta, "OK", csv_f.name)
                seguimiento.terminar(cfg, paso, "COMPLETED", csv_f.name)
                ok += 1
            except Exception as e:  # se anota y se sigue con el siguiente
                print(f"[{n}/{total}] {match_id} {country}/{competition} {etiqueta} FALLO {str(e)[:300]}", flush=True)
                _anotar(progreso, match_id, etiqueta, "FALLO", " ".join(str(e)[:200].split()))
                seguimiento.terminar(cfg, paso, "FAILED", " ".join(str(e).split()))
                fallo += 1
        if paso_juntos is not None:
            fallidos = fallo - fallo_antes
            detalle = ", ".join(resumen_juntos) or "sin CSV"
            if fallidos:
                detalle = f"{fallidos} con fallo; {detalle}"
            seguimiento.terminar(cfg, paso_juntos, "FAILED" if fallidos else "COMPLETED", detalle)
    print(f"RESUMEN: {ok} OK, {fallo} con fallo", flush=True)
    return 0 if fallo == 0 else 1


def _argumentos(args):
    """Devuelve (match_ids, nombres de dataset, fichero de progreso o None) o lanza ValueError."""
    dataset, ids, progreso = "todo", [], None
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--dataset", "--fichero", "--progreso"):
            if i + 1 >= len(args):
                raise ValueError(f"Falta el valor de {a}.")
            valor = args[i + 1]
            if a == "--dataset":
                dataset = valor.lower()
            elif a == "--progreso":
                progreso = Path(valor)
            else:
                fichero = Path(valor)
                if not fichero.exists():
                    raise ValueError(f"No existe el fichero: {fichero}")
                for linea in fichero.read_text(encoding="utf-8-sig").splitlines():
                    mid = linea.split("|")[0].strip()
                    if mid:
                        ids.append(mid)
            i += 2
        else:
            ids.append(a.strip())
            i += 1
    if dataset not in GRUPOS and dataset not in DATASETS:
        raise ValueError(f"Dataset invalido: {dataset}. Usa {', '.join(DATASETS)}, {' o '.join(GRUPOS)}.")
    unicos = list(dict.fromkeys(ids))
    if not unicos:
        raise ValueError("Indica al menos un match_id (o --fichero lista.txt).")
    malos = [m for m in unicos if not ID_VALIDO.match(m)]
    if malos:
        raise ValueError(f"match_id invalido: {', '.join(malos[:5])}")
    return unicos, (list(GRUPOS[dataset]) if dataset in GRUPOS else [dataset]), progreso


def main():
    try:
        match_ids, nombres, progreso = _argumentos(sys.argv[1:])
    except ValueError as e:
        print(f"[ERROR] {e}")
        print("Uso: basket reextraer [--dataset equipo|jugadores|resumen|jugadas|todo|h2h-cuotas] [--fichero lista.txt] [--progreso progreso.txt] <match_id...>")
        return 1
    return reextraer(match_ids, nombres, progreso)


if __name__ == "__main__":
    sys.exit(main())
