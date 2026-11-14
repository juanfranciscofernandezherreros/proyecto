# -*- coding: utf-8 -*-
r"""Helpers comunes de los lanzadores de 1_EJECUTAR (ahora en Python)."""
import subprocess
import sys
from pathlib import Path

SCRIPTS_PY = Path(__file__).resolve().parents[1]
WORKSPACE = SCRIPTS_PY.parents[1]
sys.path.insert(0, str(SCRIPTS_PY))
sys.path.insert(0, str(SCRIPTS_PY / "arranque"))
import config as _config

CFG = _config.cargar()
PY = sys.executable


def ensure(*servicios, extra=None):
    """Asegura los servicios pedidos (asegurar.py). Devuelve el codigo (0 = ok)."""
    import asegurar
    args = list(servicios) + (list(extra) if extra else [])
    return asegurar.main(args)


def run_mod(rel, *args):
    """Ejecuta un modulo Python de scripts\\py como subproceso. Devuelve su codigo."""
    return subprocess.run([PY, str(SCRIPTS_PY / rel), *[str(a) for a in args]]).returncode


def psql(sql_args, sql_input=None, compose=False):
    """Ejecuta psql (via docker exec o docker compose exec). Devuelve el codigo.
    sql_input puede ser bytes (se pasan crudos, como `psql < fichero`) o str."""
    base = (["docker", "compose", "-f", CFG.get("COMPOSE_FILE"), "exec", "-T", "postgres"]
            if compose else ["docker", "exec", "-i", CFG.get("POSTGRES_CONTAINER")])
    cmd = base + ["psql", "-U", CFG.get("DB_USER"), "-d", CFG.get("DB_NAME")] + sql_args
    es_bytes = isinstance(sql_input, (bytes, bytearray))
    return subprocess.run(cmd, input=sql_input, text=not es_bytes).returncode
