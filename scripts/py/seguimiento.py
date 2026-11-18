# -*- coding: utf-8 -*-
r"""Seguimiento en vivo en public.pipeline_step (lo leen los dashboards de Grafana).

Best-effort: si Postgres no responde, avisa una vez y el resto de llamadas no hacen nada.
"""
import subprocess

_activo = True


def texto(v):
    if v is None or v == "":
        return "NULL"
    return "'" + str(v).replace("'", "''") + "'"


def _sql(cfg, sql):
    global _activo
    if not _activo:
        return None
    try:
        p = subprocess.run(
            ["docker", "exec", "-i", cfg.get("POSTGRES_CONTAINER") or "local-validation-postgres-1",
             "psql", "-U", cfg.get("DB_USER") or "test", "-d", cfg.get("DB_NAME") or "basketball",
             "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1"],
            input=sql, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        p = None
        err = str(e)
    if p is None or p.returncode != 0:
        print(f"[AVISO] Sin seguimiento en Grafana: {err if p is None else (p.stdout + p.stderr).strip()}")
        _activo = False
        return None
    lineas = [l.strip() for l in p.stdout.splitlines() if l.strip()]
    return lineas[-1] if lineas else ""


def sql_empezar(run_id, liga, pais, competicion, paso):
    return ("INSERT INTO public.pipeline_step (run_id, liga, pais, competicion, paso, estado) "
            f"VALUES ({texto(run_id)}, {texto(liga)}, {texto(pais)}, {texto(competicion)}, "
            f"{texto(paso)}, 'RUNNING') RETURNING id;")


def sql_terminar(paso_id, estado, detalle):
    return (f"UPDATE public.pipeline_step SET estado = {texto(estado)}, intentos = intentos + 1, "
            f"finished_at = now(), detalle = {texto(detalle)} WHERE id = {int(paso_id)};")


def empezar(cfg, run_id, liga, pais, competicion, paso):
    """Fila RUNNING; devuelve su id o None."""
    return _sql(cfg, sql_empezar(run_id, liga, pais, competicion, paso)) or None


def terminar(cfg, paso_id, estado, detalle=""):
    if paso_id:
        _sql(cfg, sql_terminar(paso_id, estado, (detalle or "")[:300]))
