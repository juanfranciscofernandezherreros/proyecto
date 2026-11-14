# -*- coding: utf-8 -*-
r"""Estado del sistema en una sola pantalla (equivale a scripts\Estado.ps1, sin
PowerShell). Solo lectura: no arranca, no para, no modifica nada.

Resume contenedores, servicios, ultimas cargas del launcher, resultados por liga y
pendientes de detalle. Codigo de salida: 0 si todo lo esencial responde, 1 si falta
algo. La salida es identica a la de ESTADO.bat (paridad verificada).

Uso:  python scripts\py\estado_sys.py
API:  recoger() -> dict estructurado (lo usa estado_lib / estado.py).
"""
import json
import subprocess
import sys
import urllib.request
import urllib.error

import config as _config

WEB_URL = "http://localhost:8083"
CARGAS = 5

ESPERADOS = [
    ("postgres", "postgres"),
    ("mongo", "mongo"),
    ("projector", "projector"),
    ("api", "match-api"),
    ("web", "match-web"),
    ("grafana", "grafana"),
]


def _http_code(url, timeout=5):
    try:
        r = urllib.request.urlopen(url, timeout=timeout)
        return r.getcode()
    except urllib.error.HTTPError as e:
        return int(e.code)
    except Exception:
        return 0


def _docker_ps():
    try:
        p = subprocess.run(["docker", "ps", "--format", "{{.Names}}"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return None
    if p.returncode != 0:
        return None
    return [l for l in p.stdout.splitlines() if l.strip()]


def _psql(cfg, query):
    """Ejecuta una consulta via `docker exec psql` (stdin). Devuelve lista de lineas
    no vacias, o None si Postgres no responde."""
    try:
        p = subprocess.run(
            ["docker", "exec", "-i", cfg.get("POSTGRES_CONTAINER", "local-validation-postgres-1"),
             "psql", "-U", cfg.get("DB_USER", "test"), "-d", cfg.get("DB_NAME", "basketball"),
             "-X", "-q", "-t", "-A", "-F", "|"],
            input=query, capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    except FileNotFoundError:
        return None
    if p.returncode != 0:
        return None
    return [l for l in p.stdout.splitlines() if l.strip()]


def _audit(cfg, timeout=20):
    try:
        r = urllib.request.urlopen(f"{cfg.get('AUDIT_URL')}/latest", timeout=timeout)
        return json.loads(r.read().decode("utf-8"))
    except Exception:
        return None


def recoger():
    """Calcula el estado y devuelve un dict con el texto exacto y los datos
    estructurados (mismas claves que estado_lib.parsear_estado)."""
    cfg = _config.cargar()
    problemas = []
    lineas = []
    datos = {"contenedores": {}, "servicios": {}, "ligas": {}, "pendientes": {},
             "resumen": [], "codigo": 0, "texto": ""}

    # 1. Contenedores
    lineas.append("== CONTENEDORES ==")
    nombres = _docker_ps()
    if nombres is None:
        lineas.append("  Docker no responde (Docker Desktop parado).")
        datos["codigo"] = 1
        datos["texto"] = "\n".join(lineas)
        datos["resumen"].append("Docker no responde")
        return datos
    partes = []
    for clave, sub in ESPERADOS:
        arriba = any(sub in n for n in nombres)
        datos["contenedores"][clave] = "OK" if arriba else "PARADO"
        if not arriba and clave != "grafana":
            problemas.append(f"contenedor {clave} parado")
        partes.append(f"{clave}={'OK' if arriba else 'PARADO'}")
    lineas.append("  " + "  ".join(partes))

    # 2. Servicios
    lineas.append("== SERVICIOS (codigo HTTP; 0 = caido) ==")
    servicios = [
        ("web", f"{WEB_URL}/"),
        ("api", f"{cfg.get('API_URL')}/actuator/health"),
        ("launcher", f"{cfg.get('LAUNCHER_URL')}/actuator/health"),
        ("auditoria", f"{cfg.get('AUDIT_URL')}/latest"),
    ]
    partes = []
    for clave, url in servicios:
        codigo = _http_code(url)
        datos["servicios"][clave] = str(codigo)
        if codigo == 0:
            problemas.append(f"servicio {clave} no responde")
        partes.append(f"{clave}={codigo}")
    lineas.append("  " + "  ".join(partes))

    # 3. Ultimas cargas del launcher
    lineas.append(f"== ULTIMAS {CARGAS} CARGAS DEL LAUNCHER ==")
    filas = _psql(cfg, "SELECT to_char(created_at, 'MM-DD HH24:MI'), batch_type, status, "
                       f"coalesce(exit_code::text, '-') FROM public.batch_launch_request "
                       f"ORDER BY created_at DESC LIMIT {CARGAS};")
    if filas is None:
        lineas.append("  Postgres no responde.")
        problemas.append("postgres no responde")
    else:
        for f in filas:
            c = f.split("|")
            lineas.append(f"  {c[0]}  {c[1]:<16} {c[2]:<10} exit={c[3]}")
        malas = _psql(cfg, "SELECT count(*) FROM (SELECT status, exit_code FROM "
                           "public.batch_launch_request ORDER BY created_at DESC LIMIT 50) u "
                           "WHERE status <> 'COMPLETED' OR coalesce(exit_code, 0) <> 0;")
        # Paridad con Estado.ps1: imprime la linea siempre que Postgres responda.
        if malas:
            lineas.append(f"  De las ultimas 50, {malas[0]} no terminaron bien.")

    # 4. Resultados por liga
    lineas.append("== RESULTADOS POR LIGA (ultimo | partidos | jugados sin resultado) ==")
    filas = _psql(cfg,
        "SELECT r.country || '/' || r.competition, to_char(max(r.event_datetime), 'YYYY-MM-DD'), count(*),\n"
        "       (SELECT count(*) FROM fixtures.fixtures f\n"
        "         WHERE f.country = r.country AND f.competition = r.competition\n"
        "           AND f.event_datetime < now() AND f.event_datetime > max(r.event_datetime))\n"
        "FROM results.results r\n"
        "WHERE r.country <> '' AND r.competition <> ''\n"
        "GROUP BY r.country, r.competition\n"
        "ORDER BY 1;")
    if filas is not None:
        for f in filas:
            c = f.split("|")
            sin = int(c[3])
            aviso = "  <-- atrasada" if sin > 0 else ""
            lineas.append(f"  {c[0]:<26} {c[1]}  {c[2]:>4}  {c[3]:>3}{aviso}")
            datos["ligas"][c[0]] = {"fecha": c[1], "partidos": int(c[2]), "sin_resultado": sin}
            if sin > 0:
                problemas.append(f"{c[0]}: {c[3]} partidos jugados sin resultado")

    # 5. Pendientes de detalle
    lineas.append("== PENDIENTES DE DETALLE (auditoria) ==")
    a = _audit(cfg)
    if a is not None:
        ref = str(a.get("refreshedAt", ""))[:16]
        lineas.append(f"  fixtures={a.get('totalFixtures')}  elegibles={a.get('eligibleFixtures')}  "
                      f"pendientes={a.get('pendingFixtures')}  (auditoria del {ref})")
        datos["pendientes"] = {
            "fixtures": a.get("totalFixtures"),
            "elegibles": a.get("eligibleFixtures"),
            "pendientes": a.get("pendingFixtures"),
        }
    else:
        lineas.append("  La auditoria no responde.")

    # Resumen
    lineas.append("== RESUMEN ==")
    if not problemas:
        lineas.append("  Todo lo esencial responde y ninguna liga va atrasada.")
        datos["codigo"] = 0
    else:
        for p in problemas:
            lineas.append(f"  - {p}")
        datos["codigo"] = 1
    datos["resumen"] = problemas
    datos["texto"] = "\n".join(lineas)
    return datos


def main():
    datos = recoger()
    print(datos["texto"])
    return datos["codigo"]


if __name__ == "__main__":
    sys.exit(main())
