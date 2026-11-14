# -*- coding: utf-8 -*-
r"""Unico punto de comprobacion y arranque de servicios (equivale a
scripts\arranque\ASEGURAR_SERVICIOS.ps1 + ASEGURAR.bat, sin PowerShell).

Para cada servicio pedido: comprueba si esta listo; si no, lo arranca y espera. Las
dependencias se resuelven solas (launcher -> postgres -> docker).

Uso:  python scripts\py\arranque\asegurar.py <servicio> [servicio...] [--reiniciar-launcher] [--actualizar-dashboard]
Servicios: antibloqueo watcher docker postgres runtime auditoria launcher grafana navegador consumo
SKIP_CSV_WATCHER=1 ignora "watcher".  ASEGURAR_LOG=<fichero> anade cada linea a un log.
"""
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config
import edgedriver
import mantener_despierto  # noqa: F401 (se lanza como script aparte)

try:
    import psutil
except ImportError:
    psutil = None

CREATE_NO_WINDOW = 0x08000000
DETACHED_PROCESS = 0x00000008
CREATE_NEW_PROCESS_GROUP = 0x00000200

CFG = _config.cargar()
AQUI = Path(__file__).resolve().parent
WORKSPACE = Path(CFG["WORKSPACE"])
BATCH_ROOT = CFG.get("BATCH_ROOT", "")
REPORT_DIR = CFG.get("REPORT_DIR", "")
JAVA_EXE = CFG.get("JAVA_EXE", "")
DOCKER_DESKTOP = CFG.get("DOCKER_DESKTOP", "")
COMPOSE_FILE = CFG.get("COMPOSE_FILE", "")
AUDIT_URL = CFG.get("AUDIT_URL", "")
LAUNCHER_URL = CFG.get("LAUNCHER_URL", "").rstrip("/") + "/"
READY_DIR = CFG.get("READY_DIR", "")
LAUNCHER_ALLOWED_ROOT = CFG.get("LAUNCHER_CSV_ALLOWED_ROOT", "")
LAUNCHER_MARKER = "-Dbasketball.launcher.config=comun-v1"
GRAFANA_URL = CFG.get("GRAFANA_URL", "").rstrip("/")
GRAFANA_CONTAINER = "basketball-grafana"
PENDING_DASHBOARD_UID = "fixtures-audit-live"

GRAFANA_DASHBOARDS = {
    "fixtures-audit-live": os.path.join(BATCH_ROOT, "observability", "fixtures-pending-dashboard.json"),
    "processing-live": os.path.join(BATCH_ROOT, "observability", "processing-live-dashboard.json"),
    "csv-procesados": os.path.join(BATCH_ROOT, "observability", "csv-procesados-dashboard.json"),
    "consumo-recursos": os.path.join(BATCH_ROOT, "observability", "consumo-recursos-dashboard.json"),
}
GRAFANA_VIEWS = [
    os.path.join(str(WORKSPACE), "sql", "consultas", "2026-11-03_1055_vista-csv-procesados.sql"),
    os.path.join(str(WORKSPACE), "sql", "consultas", "2026-11-03_1635_vista-csv-generados.sql"),
]

DEPENDENCIES = {
    "grafana": ["docker"],
    "watcher": ["postgres"],
    "postgres": ["docker"],
    "runtime": ["postgres"],
    "auditoria": ["postgres"],
    "launcher": ["postgres"],
    "consumo": ["postgres"],
}

_done = set()


class FalloArranque(Exception):
    pass


def estado(service, mensaje):
    linea = f"[{service:<11}] {mensaje}"
    print(linea, flush=True)
    log = os.environ.get("ASEGURAR_LOG")
    if log:
        try:
            with open(log, "a", encoding="utf-8") as fh:
                fh.write(linea + "\n")
        except OSError:
            pass


def esperar_hasta(service, segundos, test):
    limite = time.time() + segundos
    while time.time() < limite:
        if test():
            return
        time.sleep(2)
    raise FalloArranque(f"{service} no quedo listo tras {segundos} segundos.")


# ---------- docker ----------
def _docker(args, visible=False):
    """Ejecuta docker; devuelve (codigo, stdout). stderr se descarta salvo visible."""
    try:
        p = subprocess.run(["docker", *args], capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return 1, ""
    if visible:
        for linea in (p.stdout + p.stderr).splitlines():
            print(f"  {linea}", flush=True)
    return p.returncode, p.stdout.strip()


def _test_docker():
    rc, _ = _docker(["info"])
    return rc == 0


def _container_health(compose_service):
    rc, cid = _docker(["compose", "-f", COMPOSE_FILE, "ps", "-q", compose_service])
    if not cid:
        return "missing"
    rc, estado_cont = _docker(["inspect", "--format",
        "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}", cid])
    status, _, health = estado_cont.partition("|")
    if status != "running":
        return status
    return "healthy" if health == "none" else health


def _ensure_containers(service, compose_services, segundos):
    pendientes = [s for s in compose_services if _container_health(s) != "healthy"]
    if not pendientes:
        estado(service, "ya estaba listo")
        return
    estado(service, "arrancando: " + ", ".join(pendientes))
    rc, _ = _docker(["compose", "-f", COMPOSE_FILE, "up", "-d", *compose_services], visible=True)
    if rc != 0:
        raise FalloArranque(f"docker compose no pudo levantar {', '.join(compose_services)}.")
    esperar_hasta(service, segundos,
                  lambda: not [s for s in compose_services if _container_health(s) != "healthy"])
    estado(service, "listo")


def _ensure_docker():
    if _test_docker():
        estado("docker", "ya estaba listo")
        return
    if not os.path.exists(DOCKER_DESKTOP):
        raise FalloArranque(f"Docker Desktop no esta instalado en {DOCKER_DESKTOP}")
    estado("docker", "arrancando Docker Desktop")
    _start_detached(DOCKER_DESKTOP, [], os.path.dirname(DOCKER_DESKTOP), show=1)
    esperar_hasta("docker", 180, _test_docker)
    estado("docker", "listo")


# ---------- procesos ----------
def _start_detached(filepath, args=None, cwd=None, show=0, env=None):
    """Arranca un proceso de larga duracion, desligado del actual. show: 0=oculto,
    7=minimizado, 1=normal."""
    args = args or []
    si = subprocess.STARTUPINFO()
    if show == 0:
        flags = CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP
    else:
        flags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        si.wShowWindow = 2 if show == 7 else 1  # SW_SHOWMINIMIZED / SW_SHOWNORMAL
    subprocess.Popen([filepath, *args], cwd=cwd or None, env=env,
                     creationflags=flags, startupinfo=si, close_fds=True)


def _procesos_cmdline(contiene, nombre=None):
    """Lista de procesos cuya linea de comandos contiene `contiene`."""
    if psutil is None:
        return []
    out = []
    for p in psutil.process_iter(["name", "cmdline"]):
        try:
            if nombre and (p.info["name"] or "").lower() != nombre.lower():
                continue
            cl = " ".join(p.info["cmdline"] or [])
            if contiene in cl:
                out.append(p)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return out


def _get_json(url, timeout=3):
    try:
        r = urllib.request.urlopen(url, timeout=timeout)
        return json.loads(r.read().decode("utf-8"))
    except Exception:
        return None


# ---------- antibloqueo / watcher ----------
def _ensure_antibloqueo():
    if _procesos_cmdline("mantener_despierto.py"):
        estado("antibloqueo", "ya estaba en ejecucion")
        return
    estado("antibloqueo", "iniciando")
    _start_detached(sys.executable, [str(AQUI / "mantener_despierto.py")], str(AQUI), show=7)


def _ensure_watcher():
    watcher_py = AQUI.parent / "monitor" / "watch_csv.py"
    if _procesos_cmdline("watch_csv.py"):
        estado("watcher", "ya estaba en ejecucion")
        return
    if not watcher_py.exists():
        raise FalloArranque(f"No se encontro {watcher_py}.")
    estado("watcher", "iniciando")
    # Ventana propia: el monitor refresca la pantalla y necesita consola.
    subprocess.Popen([sys.executable, str(watcher_py)],
                     creationflags=0x00000010 | CREATE_NEW_PROCESS_GROUP)  # CREATE_NEW_CONSOLE


# ---------- launcher ----------
def _launcher_procesos():
    return _procesos_cmdline("csv-batch-launcher.jar", nombre="java.exe")


def _start_launcher():
    jar = os.path.join(BATCH_ROOT, "launcher", "target", "csv-batch-launcher.jar")
    if not os.path.exists(JAVA_EXE):
        raise FalloArranque(f"No se encontro Java 21: {JAVA_EXE}")
    if not os.path.exists(jar):
        raise FalloArranque(f"No se encontro {jar}. Compila desde csv-extra-batch con: "
                            "mvn.cmd -B -DskipTests package")
    os.makedirs(REPORT_DIR, exist_ok=True)
    env = os.environ.copy()
    env["LAUNCHER_PORT"] = str(urllib.parse.urlsplit(LAUNCHER_URL).port)
    env["WATCH_DIRECTORY"] = READY_DIR
    env["CSV_ALLOWED_ROOT"] = LAUNCHER_ALLOWED_ROOT
    env["LAUNCHER_DIRECTORY_SCAN_ENABLED"] = "false"
    env["JAVA_COMMAND"] = JAVA_EXE
    env["RESULTS_BATCH_JAR"] = os.path.join(BATCH_ROOT, "results", "target", "csv-results-batch.jar")
    env["FIXTURES_BATCH_JAR"] = os.path.join(BATCH_ROOT, "fixtures", "target", "csv-fixtures-batch.jar")
    env["TEAM_STATS_BATCH_JAR"] = os.path.join(BATCH_ROOT, "team-stats", "target", "csv-team-stats-batch.jar")
    env["MATCH_STATS_BATCH_JAR"] = os.path.join(BATCH_ROOT, "match-summary", "target", "csv-stats-match-batch.jar")
    env["PLAYER_STATS_BATCH_JAR"] = os.path.join(BATCH_ROOT, "stats-player", "target", "csv-stats-player-batch.jar")
    env["POINT_BY_POINT_BATCH_JAR"] = os.path.join(BATCH_ROOT, "point-by-point", "target", "csv-point-by-point-batch.jar")
    _start_detached(JAVA_EXE, [LAUNCHER_MARKER, "-jar", jar,
        f"--logging.file.name={REPORT_DIR}\\csv-batch-launcher.log"], os.path.dirname(jar), show=0, env=env)


def _ensure_launcher(reiniciar):
    procesos = _launcher_procesos()
    ajenos = [p for p in procesos if LAUNCHER_MARKER not in " ".join(p.cmdline())]
    up = (_get_json(LAUNCHER_URL) or {}).get("status") == "UP"

    if up and not reiniciar and not ajenos:
        estado("launcher", "ya estaba listo")
        return
    if reiniciar or ajenos:
        razon = "reinicio pedido" if reiniciar else "estaba arrancado con otra configuracion"
        estado("launcher", f"reiniciando ({razon})")
        for p in procesos:
            try:
                p.kill()
            except Exception:
                pass
        esperar_hasta("launcher (parada)", 30, lambda: not _launcher_procesos())
        procesos = []
    if procesos:
        estado("launcher", "arrancando ya; esperando a que responda UP")
    else:
        estado("launcher", "arrancando")
        _start_launcher()
    esperar_hasta("launcher", 120, lambda: (_get_json(LAUNCHER_URL) or {}).get("status") == "UP")
    estado("launcher", f"listo en {LAUNCHER_URL}")


# ---------- auditoria ----------
def _auditoria_fresca():
    latest = _get_json(f"{AUDIT_URL}/latest")
    if not latest or not latest.get("refreshedAt"):
        return False
    import re
    from datetime import datetime
    stamp = re.sub(r"(\.\d{6})\d+", r"\1", latest["refreshedAt"])
    try:
        dt = datetime.fromisoformat(stamp)
        edad = datetime.now(dt.tzinfo) - dt
    except Exception:
        return False
    return edad.total_seconds() < 120


def _auditoria_procesos():
    return _procesos_cmdline("fixtures-processing-audit.jar", nombre="java.exe")


def _ensure_auditoria():
    if _auditoria_fresca():
        estado("auditoria", "ya estaba lista")
        return
    running = _auditoria_procesos()
    if running and _get_json(f"{AUDIT_URL}/latest"):
        estado("auditoria", "responde pero lleva mas de 2 minutos sin refrescar; reiniciando")
        for p in running:
            try:
                p.kill()
            except Exception:
                pass
        esperar_hasta("auditoria (parada)", 30, lambda: not _auditoria_procesos())
        running = []
    if running:
        estado("auditoria", "arrancando ya; esperando a que responda")
    else:
        jar = os.path.join(BATCH_ROOT, "fixtures-processing-audit", "target", "fixtures-processing-audit.jar")
        if not os.path.exists(JAVA_EXE):
            raise FalloArranque(f"No se encontro Java 21: {JAVA_EXE}")
        if not os.path.exists(jar):
            raise FalloArranque(f"No se encontro {jar}. Compila desde csv-extra-batch con: "
                                "mvn.cmd -B -pl fixtures-processing-audit -am package -DskipTests")
        os.makedirs(REPORT_DIR, exist_ok=True)
        estado("auditoria", "arrancando")
        env = os.environ.copy()
        env["FIXTURES_PROCESSING_AUDIT_LEAGUE_CATALOG"] = CFG.get("LEAGUE_CATALOG", "")
        _start_detached(JAVA_EXE, ["-jar", jar, "--app.audit.run-once=false",
            "--logging.pattern.console=", f"--logging.file.name={REPORT_DIR}\\fixtures-processing-audit-service.log"],
            os.path.dirname(jar), show=0, env=env)
    esperar_hasta("auditoria", 120, lambda: (_get_json(f"{AUDIT_URL}/latest") or {}).get("status") == "COMPLETED")
    estado("auditoria", f"lista en {AUDIT_URL}")


# ---------- grafana ----------
def _grafana(metodo, path, body=None):
    url = f"{GRAFANA_URL}{path}"
    data = body.encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, method=metodo)
    if body:
        req.add_header("Content-Type", "application/json; charset=utf-8")
    r = urllib.request.urlopen(req, timeout=15)
    txt = r.read().decode("utf-8")
    return json.loads(txt) if txt else None


def _grafana_existe(path):
    try:
        _grafana("GET", path)
        return True
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return False
        raise


def _ensure_grafana():
    for source in ("basketball-prometheus", "basketball-loki"):
        rc, st = _docker(["inspect", "--format", "{{.State.Status}}", source])
        if not st:
            estado("grafana", f"no existe el contenedor {source}")
            continue
        if st != "running":
            estado("grafana", f"{source} {st}; arrancando")
            rc, _ = _docker(["start", source], visible=True)
            if rc != 0:
                estado("grafana", f"docker start {source} fallo")
    rc, st = _docker(["inspect", "--format", "{{.State.Status}}", GRAFANA_CONTAINER])
    if not st:
        raise FalloArranque(f"No existe el contenedor {GRAFANA_CONTAINER}. Crealo una vez con: "
                            "powershell -File local-validation\\scripts\\Start-BasketballLocal.ps1")
    if st != "running":
        estado("grafana", f"contenedor {st}; arrancando")
        rc, _ = _docker(["start", GRAFANA_CONTAINER], visible=True)
        if rc != 0:
            raise FalloArranque(f"docker start {GRAFANA_CONTAINER} fallo.")

    def sano():
        d = _get_json(f"{GRAFANA_URL}/api/health")
        return d is not None and d.get("database") == "ok"

    if st == "running":
        try:
            esperar_hasta("grafana", 20, sano)
        except FalloArranque:
            estado("grafana", "en marcha pero no responde; reiniciando")
            _docker(["restart", GRAFANA_CONTAINER], visible=True)
    esperar_hasta("grafana", 120, sano)

    if not _grafana_existe("/api/datasources/uid/fixtures-audit-http"):
        estado("grafana", "creando datasource fixtures-audit-http")
        ds = {"name": "Fixtures Audit HTTP", "uid": "fixtures-audit-http",
              "type": "yesoreyeram-infinity-datasource", "access": "proxy",
              "url": "http://host.docker.internal:8090", "basicAuth": False,
              "isDefault": False, "jsonData": {}}
        _grafana("POST", "/api/datasources", json.dumps(ds))

    for view in GRAFANA_VIEWS:
        leaf = os.path.basename(view)
        try:
            sql = Path(view).read_text(encoding="utf-8")
            p = subprocess.run(["docker", "exec", "-i", CFG.get("POSTGRES_CONTAINER"),
                "psql", "-U", CFG.get("DB_USER"), "-d", CFG.get("DB_NAME"),
                "-X", "-q", "-v", "ON_ERROR_STOP=1"],
                input=sql, capture_output=True, text=True, encoding="utf-8", errors="replace")
            if p.returncode == 0:
                estado("grafana", f"vista aplicada: {leaf}")
            else:
                ultimo = (p.stdout + p.stderr).strip().splitlines()
                estado("grafana", f"no se pudo aplicar {leaf}: {ultimo[-1] if ultimo else ''}")
        except OSError as e:
            estado("grafana", f"no se pudo aplicar {leaf}: {e}")

    for uid, fichero in GRAFANA_DASHBOARDS.items():
        if not os.path.exists(fichero):
            raise FalloArranque(f"No se encontro {fichero}")
        estado("grafana", f"importando dashboard {uid}")
        _grafana("POST", "/api/dashboards/db", Path(fichero).read_text(encoding="utf-8"))
    estado("grafana", f"listo en {GRAFANA_URL}/d/{PENDING_DASHBOARD_UID}")


# ---------- consumo ----------
def _ensure_consumo():
    if _procesos_cmdline("recolectar_consumo.py"):
        estado("consumo", "ya estaba en marcha")
        return
    estado("consumo", "arrancando recolector")
    script = AQUI.parent / "monitor" / "recolectar_consumo.py"
    _start_detached(sys.executable, [str(script)], str(WORKSPACE), show=0)
    esperar_hasta("consumo", 30, lambda: bool(_procesos_cmdline("recolectar_consumo.py")))
    estado("consumo", "en marcha (log en reports\\consumo\\recolector-consumo.log)")


# ---------- navegador ----------
def _ensure_navegador():
    if CFG.get("FLASHSCORE_BROWSER") != "edge":
        estado("navegador", f"usa {CFG.get('FLASHSCORE_BROWSER')}; nada que comprobar")
        return
    code = edgedriver.main()
    estado("navegador", "driver de Edge listo" if code == 0 else "fallo al preparar el driver de Edge")
    if code:
        raise FalloArranque("el driver de Edge no esta disponible.")


# ---------- orquestacion ----------
def _ensure_service(service, reiniciar_launcher):
    if service in _done:
        return
    for dep in DEPENDENCIES.get(service, []):
        _ensure_service(dep, reiniciar_launcher)
    if service == "antibloqueo":
        _ensure_antibloqueo()
    elif service == "watcher":
        _ensure_watcher()
    elif service == "docker":
        _ensure_docker()
    elif service == "postgres":
        _ensure_containers("postgres", ["postgres"], 120)
    elif service == "runtime":
        _ensure_containers("runtime", ["postgres", "mongo", "basketball-match-projector",
                                       "basketball-match-api", "basketball-match-web"], 300)
    elif service == "auditoria":
        _ensure_auditoria()
    elif service == "launcher":
        _ensure_launcher(reiniciar_launcher)
    elif service == "grafana":
        _ensure_grafana()
    elif service == "navegador":
        _ensure_navegador()
    elif service == "consumo":
        _ensure_consumo()
    else:
        raise FalloArranque(f"Servicio desconocido: {service}. Validos: antibloqueo, watcher, "
                            "docker, postgres, runtime, auditoria, launcher, grafana, navegador, consumo")
    _done.add(service)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    servicios, reiniciar_launcher = [], False
    skip_watcher = os.environ.get("SKIP_CSV_WATCHER") == "1"
    for a in argv:
        al = a.lower()
        if al == "--reiniciar-launcher":
            reiniciar_launcher = True
        elif al == "--actualizar-dashboard":
            pass  # compatibilidad: los dashboards se reimportan siempre al asegurar grafana
        elif al == "watcher":
            if not skip_watcher:
                servicios.append("watcher")
        else:
            servicios.append(al)
    if not argv:
        print("ERROR: indica al menos un servicio: antibloqueo watcher docker postgres "
              "runtime auditoria launcher grafana navegador consumo")
        return 1
    if not servicios:
        return 0
    # Admite "postgres,launcher" y "postgres launcher".
    pedidos = [s for parte in servicios for s in parte.replace(",", " ").split() if s]
    try:
        for s in pedidos:
            _ensure_service(s, reiniciar_launcher)
    except FalloArranque as e:
        estado("ERROR", str(e))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
