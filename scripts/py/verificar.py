# -*- coding: utf-8 -*-
r"""Verificacion ejecutable del sistema ligada al SDD (equivale a scripts\Verificar.ps1,
sin PowerShell). Requiere el stack arrancado. Codigo de salida 0 = VERDE, 1 = ROJO.

Comprobaciones:
  1. Web (8083) y API (8082) responden 200.
  2. results y fixtures sin slugs de competicion no canonicos (acb/super-league).
  3. /api/v1/matches/filters no ofrece acb ni super-league.
  4. Un partido de spain/liga-endesa une fixture + result con la misma competicion.
  5. Mongo: ningun partido con availableSections=fixture pero objeto fixture nulo.
  6. Vistas de Grafana (v_csv_procesados, v_csv_generados) presentes en Postgres.
  7. Telegram (si esta configurado): un vigilante en marcha y ningun CSV terminado
     sin avisar (mas de 2 min).

Uso:  python scripts\py\verificar.py
"""
import json
import subprocess
import sys
import urllib.request
import urllib.error

WEB_URL = "http://localhost:8083"
API_URL = "http://localhost:8082"
POSTGRES_CONTAINER = "local-validation-postgres-1"
MONGO_CONTAINER = "local-validation-mongo-1"

_fail = 0


def ok(m):
    print(f"  OK   {m}")


def bad(m):
    global _fail
    print(f"  FAIL {m}")
    _fail += 1


def psql(sql):
    try:
        p = subprocess.run(
            ["docker", "exec", "-i", POSTGRES_CONTAINER, "psql", "-U", "test",
             "-d", "basketball", "-tAc", sql],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        return (p.stdout + p.stderr).strip()
    except FileNotFoundError:
        return ""


def mongo(js):
    try:
        p = subprocess.run(
            ["docker", "exec", "-i", MONGO_CONTAINER, "mongosh", "--quiet",
             "basketball", "--eval", js],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        salida = (p.stdout + p.stderr).strip().splitlines()
        return salida[-1].strip() if salida else ""
    except FileNotFoundError:
        return ""


def http_code(url):
    try:
        return urllib.request.urlopen(url, timeout=5).getcode()
    except urllib.error.HTTPError as e:
        return int(e.code)
    except Exception:
        return 0


def _rest(url):
    r = urllib.request.urlopen(url, timeout=5)
    return json.loads(r.read().decode("utf-8"))


def _verificar_telegram():
    """Si Telegram esta configurado: un unico vigilante (monitor/telegram_csv.py) en
    marcha y su marca de agua a menos de 2 min del ultimo CSV terminado. Sin
    configurar, se omite (no es un fallo)."""
    from datetime import datetime
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import config as _config
    cfg = _config.cargar()
    if not ((cfg.get("TELEGRAM_BOT_TOKEN") or "").strip() and (cfg.get("TELEGRAM_CHAT_ID") or "").strip()):
        ok("Telegram: no configurado (se omite)")
        return
    try:
        import psutil
        vivos = [p for p in psutil.process_iter(["name", "cmdline"])
                 if (p.info["name"] or "").lower().startswith("python")
                 and any(str(c).endswith("telegram_csv.py") for c in (p.info["cmdline"] or []))]
    except Exception as e:
        bad(f"Telegram: no se pudo listar procesos: {e}")
        return
    if len(vivos) == 1:
        ok("Telegram: un vigilante en marcha")
    else:
        bad(f"Telegram: {len(vivos)} vigilantes en marcha (debe haber 1)")
    try:
        estado = Path(cfg.get("DATA_DIR") or "C:/data/basketball") / "state" / "telegram_csv.json"
        desde = datetime.fromisoformat(json.loads(estado.read_text(encoding="utf-8"))["desde"].replace("Z", "+00:00"))
    except Exception:
        bad("Telegram: sin marca de agua (state/telegram_csv.json)")
        return
    ultimo = psql("SELECT to_char(max(finished_at) AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"+00:00\"') "
                  "FROM public.batch_launch_request WHERE status IN ('COMPLETED','FAILED');")
    try:
        retraso = (datetime.fromisoformat(ultimo) - desde).total_seconds()
    except ValueError:
        bad(f"Telegram: no se pudo leer el ultimo CSV terminado ({ultimo})")
        return
    ok("Telegram: todos los CSV terminados avisados") if retraso <= 120 else \
        bad(f"Telegram: CSV terminados sin avisar desde hace {int(retraso)} s")


def main():
    print("== Verificacion del sistema (SDD) ==")

    # 1. Web y API
    ok("Web responde 200") if http_code(f"{WEB_URL}/") == 200 else bad("Web no responde 200")
    ok("API responde 200") if http_code(f"{API_URL}/actuator/health") == 200 else bad("API no responde 200")

    # 2. Sin slugs no canonicos en PG
    nf = psql("SELECT count(*) FROM fixtures.fixtures WHERE competition IN ('acb','super-league');")
    nr = psql("SELECT count(*) FROM results.results  WHERE competition IN ('acb','super-league');")
    ok("fixtures sin slug no canonico") if nf == "0" else bad(f"fixtures con slug no canonico: {nf}")
    ok("results sin slug no canonico") if nr == "0" else bad(f"results con slug no canonico: {nr}")

    # 3. Filtros de la API sin acb/super-league
    try:
        filters = _rest(f"{API_URL}/api/v1/matches/filters")
        comps = list(filters.get("competitions") or [])
        if "acb" not in comps and "super-league" not in comps:
            ok("/filters sin acb/super-league")
        else:
            malas = ",".join(c for c in comps if c in ("acb", "super-league"))
            bad(f"/filters aun ofrece: {malas}")
    except Exception as e:
        bad(f"no se pudo leer /filters: {e}")

    # 4. Join fixture+result en spain/liga-endesa
    try:
        r = _rest(f"{API_URL}/api/v1/matches?page=0&size=1&country=spain&competition=liga-endesa&status=finished")
        content = list(r.get("content") or [])
        m = content[0] if content else None
        if (m and (m.get("fixture") or {}).get("competition") == "liga-endesa"
                and (m.get("result") or {}).get("competition") == "liga-endesa"):
            ok(f"partido spain une fixture+result ({m.get('matchId')})")
        else:
            bad("no hay partido spain/liga-endesa consistente")
    except Exception as e:
        bad(f"no se pudo verificar el join: {e}")

    # 5. Projector: no hay documentos con seccion fixture pero sin objeto fixture
    rotos = mongo("print(db.matches.countDocuments({availableSections:/^fixture$/, fixture:null}))")
    ok("Mongo: ningun partido con fixture nula") if rotos == "0" else \
        bad(f"Mongo: {rotos} partidos con availableSections=fixture pero objeto fixture nulo")

    # 6. Vistas de Grafana (las aplica asegurar.py con Postgres ya arrancado)
    nv = psql("SELECT count(*) FROM pg_views WHERE schemaname='public' "
              "AND viewname IN ('v_csv_procesados','v_csv_generados');")
    ok("Grafana: vistas v_csv_procesados y v_csv_generados en Postgres") if nv == "2" else \
        bad(f"Grafana: faltan vistas en Postgres ({nv} de 2)")

    # 7. Aviso por Telegram: un vigilante y ningun CSV terminado sin avisar
    _verificar_telegram()

    print("")
    if _fail == 0:
        print("RESULTADO: VERDE (todas las comprobaciones pasan)")
        return 0
    print(f"RESULTADO: ROJO ({_fail} comprobacion(es) fallida(s))")
    return 1


if __name__ == "__main__":
    sys.exit(main())
