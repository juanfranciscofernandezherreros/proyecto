# -*- coding: utf-8 -*-
r"""Recolector de consumo para el dashboard "Basketball - Consumo" de Grafana
(equivale a scripts\monitor\RECOLECTAR_CONSUMO.ps1, sin PowerShell).

Cada pocos segundos guarda en el esquema monitoring de PostgreSQL: CPU/RAM por
componente y por contenedor, heap de las JVM (jcmd), y cada pocos minutos el tamano
de carpetas, de la base y una purga de datos antiguos.

Uso:  python scripts\py\monitor\recolectar_consumo.py [--intervalo N] [--una-vez]
"""
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

SCRIPTS_PY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_PY))
import config as _config

try:
    import psutil
except ImportError:
    psutil = None

CFG = _config.cargar()
WORKSPACE = Path(CFG["WORKSPACE"])
POSTGRES = CFG.get("POSTGRES_CONTAINER")
JCMD = Path(CFG["JAVA_EXE"]).parent / "jcmd.exe" if CFG.get("JAVA_EXE") else None
LOG_DIR = Path(CFG["REPORTS_DIR"]) / "consumo"
LOG_FILE = LOG_DIR / "recolector-consumo.log"
SCHEMA = WORKSPACE / "sql" / "consultas" / "2026-11-03_1200_esquema-monitoring-consumo.sql"
CORES = os.cpu_count() or 1
RETENTION_DAYS = 7
SCRAPER_DIR = str(CFG.get("SCRAPER_DIR", "")).lower()

_prev_cpu = {}
_prev_at = None


def _log(msg):
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    with open(LOG_FILE, "a", encoding="utf-8") as fh:
        fh.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n")


def _psql(sql):
    p = subprocess.run(
        ["docker", "exec", "-i", POSTGRES, "psql", "-U", CFG.get("DB_USER"),
         "-d", CFG.get("DB_NAME"), "-q", "-v", "ON_ERROR_STOP=1"],
        input=sql, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise RuntimeError(f"psql fallo: {(p.stdout + p.stderr).strip()}")


def _sql(v):
    if v is None:
        return "NULL"
    if isinstance(v, str):
        return "'" + v.replace("'", "''") + "'"
    return repr(float(v))


def _componente(nombre, cmd):
    n = (nombre or "").lower()
    cmd = cmd or ""
    if n in ("java.exe", "javaw.exe"):
        if "csv-batch-launcher.jar" in cmd:
            return "launcher"
        if "fixtures-processing-audit.jar" in cmd:
            return "auditoria"
        m = re.search(r"(csv-[\w-]+-batch)\.jar", cmd)
        if m:
            return f"batch:{m.group(1)}"
        if "pronostico" in cmd:
            return "pronostico"
        return "java-otro"
    if n in ("python.exe", "pythonw.exe"):
        return "scraper" if (SCRAPER_DIR and SCRAPER_DIR in cmd.lower()) or "flashscore" in cmd else None
    if n == "msedgedriver.exe":
        return "edgedriver"
    if n == "chromedriver.exe":
        return "chromedriver"
    if n == "msedge.exe":
        return "edge-selenium" if ("scoped_dir" in cmd or "--remote-debugging" in cmd) else "edge-usuario"
    if n == "chrome.exe":
        return "chrome-selenium" if ("scoped_dir" in cmd or "--remote-debugging" in cmd) else None
    if re.match(r"^(vmmem|vmmemwsl|com\.docker\.backend|docker desktop)\.exe$", n) or n.startswith("vmmem"):
        return "docker-vm"
    if n in ("powershell.exe", "pwsh.exe", "cmd.exe"):
        return "scripts" if str(WORKSPACE).lower() in cmd.lower() else None
    return None


def _process_rows(now):
    global _prev_cpu, _prev_at
    cpu_now, info = {}, {}
    if psutil:
        for p in psutil.process_iter(["pid", "name", "cmdline", "memory_info", "num_threads"]):
            try:
                t = p.cpu_times()
                cpu_now[p.pid] = t.user + t.system
                info[p.pid] = p.info
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
    elapsed = (now - _prev_at).total_seconds() if _prev_at else None

    grupos = {}
    for pid, i in info.items():
        comp = _componente(i.get("name"), " ".join(i.get("cmdline") or []))
        if not comp:
            continue
        g = grupos.setdefault(comp, {"name": i.get("name"), "pids": [], "cpu": 0.0,
                                     "has_cpu": False, "mem": 0.0, "threads": 0})
        g["pids"].append(pid)
        g["mem"] += (i.get("memory_info").rss / 1048576) if i.get("memory_info") else 0
        g["threads"] += i.get("num_threads") or 0
        if elapsed and pid in cpu_now and pid in _prev_cpu:
            g["cpu"] += max(0, cpu_now[pid] - _prev_cpu[pid]) / elapsed / CORES * 100
            g["has_cpu"] = True
    _prev_cpu, _prev_at = cpu_now, now

    for comp, g in grupos.items():
        single = g["pids"][0] if len(g["pids"]) == 1 else None
        yield {"Component": comp, "Name": g["name"], "Pid": single,
               "Cpu": g["cpu"] if g["has_cpu"] else None, "Mem": g["mem"], "Threads": g["threads"]}


_FACTORES = {"B": 1 / 1048576, "KiB": 1 / 1024, "MiB": 1, "GiB": 1024, "TiB": 1048576,
             "kB": 1 / 1024, "MB": 1, "GB": 1024}


def _container_rows():
    p = subprocess.run(["docker", "stats", "--no-stream", "--format", "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        return
    for line in p.stdout.splitlines():
        partes = line.split("|")
        if len(partes) < 3 or not partes[2]:
            continue
        name, cpu, mem = partes[0], partes[1], partes[2]
        used = mem.split("/")[0].strip()
        m = re.match(r"^([\d.]+)\s*([KMGT]?i?B)$", used)
        if not m or m.group(2) not in _FACTORES:
            continue
        mem_mb = float(m.group(1)) * _FACTORES[m.group(2)]
        cpu_pct = float(cpu.rstrip("%")) / CORES
        yield {"Component": f"contenedor:{name}", "Name": "docker", "Pid": None,
               "Cpu": cpu_pct, "Mem": mem_mb, "Threads": None}


def _jvm_rows():
    if not JCMD or not JCMD.exists() or not psutil:
        return
    for p in psutil.process_iter(["pid", "name", "cmdline"]):
        try:
            if (p.info["name"] or "").lower() not in ("java.exe", "javaw.exe"):
                continue
            comp = _componente(p.info["name"], " ".join(p.info["cmdline"] or []))
            r = subprocess.run([str(JCMD), str(p.info["pid"]), "GC.heap_info"],
                               capture_output=True, text=True, encoding="utf-8", errors="replace")
            if r.returncode != 0:
                continue
            m = re.search(r"heap\s+total\s+(\d+)K,\s+used\s+(\d+)K", r.stdout)
            if not m:
                continue
            yield {"Component": comp, "Pid": p.info["pid"],
                   "Used": float(m.group(2)) / 1024, "Committed": float(m.group(1)) / 1024}
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue


def _tam(paths):
    total, files = 0, 0
    for base in paths:
        if not base or not os.path.exists(base):
            continue
        for root, _dirs, fs in os.walk(base):
            for f in fs:
                try:
                    total += os.path.getsize(os.path.join(root, f))
                    files += 1
                except OSError:
                    continue
    return total / 1048576, files


def _disk_rows():
    temp = os.environ.get("TEMP", "")
    scoped = [str(p) for p in Path(temp).glob("scoped_dir*")] if temp else []
    targets = []
    for p in WORKSPACE.rglob("target"):
        if p.is_dir() and not re.search(r"[\\/](node_modules|\.git|\.venv)[\\/]", str(p)) \
                and (p.parent / "pom.xml").exists():
            targets.append(str(p))
    vhdx = [str(p) for p in (Path(os.environ.get("LOCALAPPDATA", "")) / "Docker" / "wsl").rglob("*.vhdx")]
    conjunto = [
        ("temp", temp, [temp]),
        ("scoped_dir", f"{temp}\\scoped_dir*", scoped),
        ("maven-target", f"{WORKSPACE}\\**\\target", targets),
        ("reports", CFG.get("REPORTS_DIR"), [CFG.get("REPORTS_DIR")]),
        ("datos", CFG.get("DATA_DIR"), [CFG.get("DATA_DIR")]),
        ("ready", CFG.get("READY_ROOT"), [CFG.get("READY_ROOT")]),
    ]
    for label, path, paths in conjunto:
        mb, files = _tam(paths)
        yield {"Label": label, "Path": path, "Mb": mb, "Files": files}
    if vhdx:
        mb = sum(os.path.getsize(v) for v in vhdx) / 1048576
        yield {"Label": "docker-vhdx", "Path": f"{os.environ.get('LOCALAPPDATA')}\\Docker\\wsl\\*.vhdx",
               "Mb": mb, "Files": len(vhdx)}


DB_SIZE_SQL = """INSERT INTO monitoring.db_size_sample (sampled_at, schema_name, size_mb)
SELECT now(), '(total)', pg_database_size(current_database()) / 1048576.0
UNION ALL
SELECT now(), n.nspname, sum(pg_total_relation_size(c.oid)) / 1048576.0
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'm', 'p') AND n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname NOT LIKE 'pg_toast%'
GROUP BY n.nspname;"""


def _purge_sql():
    return "".join(
        f"DELETE FROM monitoring.{t} WHERE sampled_at < now() - interval '{RETENTION_DAYS} days';\n"
        for t in ("process_sample", "jvm_sample", "disk_sample", "db_size_sample"))


def main():
    args = sys.argv[1:]
    una_vez = "--una-vez" in args
    intervalo = int(args[args.index("--intervalo") + 1]) if "--intervalo" in args else 15

    _log(f"arrancando (intervalo {intervalo}s, pid {os.getpid()})")
    _psql(SCHEMA.read_text(encoding="utf-8"))
    last_disk = last_db = last_purge = datetime.min
    disk_every, db_every, purge_every = timedelta(minutes=10), timedelta(minutes=5), timedelta(hours=1)

    list(_process_rows(datetime.now()))  # primera muestra: solo deja la referencia de CPU
    time.sleep(3 if una_vez else intervalo)

    while True:
        try:
            now = datetime.now()
            ts = _sql(now.strftime("%Y-%m-%dT%H:%M:%S.%f%z") or now.isoformat())
            partes = []
            for r in list(_process_rows(now)) + list(_container_rows()):
                partes.append(f"INSERT INTO monitoring.process_sample VALUES ({ts}, {_sql(r['Component'])}, "
                              f"{_sql(r['Name'])}, {_sql(r['Pid'])}, {_sql(r['Cpu'])}, {_sql(r['Mem'])}, {_sql(r['Threads'])});")
            for j in _jvm_rows():
                partes.append(f"INSERT INTO monitoring.jvm_sample VALUES ({ts}, {_sql(j['Component'])}, "
                              f"{_sql(j['Pid'])}, {_sql(j['Used'])}, {_sql(j['Committed'])});")
            if una_vez or (now - last_disk) >= disk_every:
                for d in _disk_rows():
                    partes.append(f"INSERT INTO monitoring.disk_sample VALUES ({ts}, {_sql(d['Label'])}, "
                                  f"{_sql(d['Path'])}, {_sql(d['Mb'])}, {_sql(d['Files'])});")
                last_disk = now
            if una_vez or (now - last_db) >= db_every:
                partes.append(DB_SIZE_SQL)
                last_db = now
            if (now - last_purge) >= purge_every:
                partes.append(_purge_sql())
                last_purge = now
            _psql("\n".join(partes))
        except Exception as e:
            _log(f"ERROR {e}")
        if una_vez:
            break
        time.sleep(intervalo)
    return 0


if __name__ == "__main__":
    sys.exit(main())
