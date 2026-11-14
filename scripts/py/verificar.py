# -*- coding: utf-8 -*-
r"""Verificacion ejecutable del sistema ligada al SDD (equivale a scripts\Verificar.ps1,
sin PowerShell). Requiere el stack arrancado. Codigo de salida 0 = VERDE, 1 = ROJO.

Comprobaciones:
  1. Web (8083) y API (8082) responden 200.
  2. results y fixtures sin slugs de competicion no canonicos (acb/super-league).
  3. /api/v1/matches/filters no ofrece acb ni super-league.
  4. Un partido de spain/liga-endesa une fixture + result con la misma competicion.
  5. Mongo: ningun partido con availableSections=fixture pero objeto fixture nulo.

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

    print("")
    if _fail == 0:
        print("RESULTADO: VERDE (todas las comprobaciones pasan)")
        return 0
    print(f"RESULTADO: ROJO ({_fail} comprobacion(es) fallida(s))")
    return 1


if __name__ == "__main__":
    sys.exit(main())
