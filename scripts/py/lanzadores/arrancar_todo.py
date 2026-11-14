# -*- coding: utf-8 -*-
r"""Lanzador: arrancar todo (ARRANCAR_TODO.bat). Web + servicios + launcher y verifica."""
import subprocess
import sys
import urllib.request
import urllib.error
from _base import ensure, CFG, WORKSPACE


def _http(url):
    try:
        return urllib.request.urlopen(url, timeout=5).getcode()
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


if __name__ == "__main__":
    print("\n=== 1) Web y servicios (docker compose) ===")
    lv = WORKSPACE / "local-validation"
    if not lv.is_dir():
        print(f"ERROR: no existe {lv}")
        sys.exit(1)
    rc = subprocess.run(["docker", "compose", "up", "-d", "--build", "mongo",
                         "basketball-match-projector", "basketball-match-api",
                         "basketball-match-web"], cwd=str(lv)).returncode
    if rc != 0:
        print(f"ERROR: fallo el docker compose (codigo {rc}).")
        sys.exit(rc)
    print("\n=== 2) Procesamiento de CSV (launcher) ===")
    if ensure("launcher"):
        sys.exit(1)
    print("\n=== Verificacion ===")
    print(f"  web 8083 -> {_http('http://localhost:8083/')}")
    print(f"  api 8082 -> {_http('http://localhost:8082/actuator/health')}")
    print(f"\nWeb:      http://localhost:8083")
    print(f"API:      http://localhost:8082")
    print(f"Launcher: {CFG['LAUNCHER_URL']}")
    print(f"Grafana:  {CFG['GRAFANA_URL']}")
    print("\nListo. La web tarda ~1 min en reflejar CSV nuevos (Postgres -> projector -> Mongo).")
    sys.exit(0)
