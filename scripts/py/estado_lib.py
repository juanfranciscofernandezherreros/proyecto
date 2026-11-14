# -*- coding: utf-8 -*-
"""Utilidades compartidas para los orquestadores en Python.

Ejecuta ESTADO.bat (solo lectura) y parsea su salida para poder comparar el
estado antes y despues de una carga, sin gastar tokens. Lo usan estado.py,
resultados_todas.py y procesar_csv_resultados.py.
"""
import subprocess
import sys
import re
from pathlib import Path

import config as _config

RAIZ = Path(__file__).resolve().parents[2]  # C:\Develop\basketball
EJECUTAR = RAIZ / "1_EJECUTAR"
ESTADO_BAT = EJECUTAR / "ESTADO.bat"


def leer_config():
    """Devuelve el dict de configuracion del proyecto (via config.py)."""
    return _config.cargar()


def report_dir():
    d = leer_config().get("REPORT_DIR")
    return Path(d) if d else Path(r"C:\data\basketball\reports\orchestrator")


def _run_capturando(cmd, titulo=None, eco=False):
    """Lanza un comando, devuelve (codigo, texto). Si eco=True, va imprimiendo
    las lineas segun llegan (para las cargas largas)."""
    if titulo:
        print(titulo, flush=True)
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace", bufsize=1,
    )
    lineas = []
    for linea in proc.stdout:
        lineas.append(linea.rstrip("\n"))
        if eco:
            print(linea, end="", flush=True)
    proc.wait()
    return proc.returncode, "\n".join(lineas)


def leer_estado():
    """Devuelve el estado del sistema como dict, calculado en Python puro
    (estado_sys.recoger), sin invocar ESTADO.bat ni PowerShell."""
    import estado_sys
    return estado_sys.recoger()


def leer_estado_bat():
    """Variante que ejecuta ESTADO.bat (Estado.ps1) y parsea su texto. Solo se usa
    para comparar la paridad del Python nuevo con el original."""
    codigo, texto = _run_capturando(["cmd", "/c", str(ESTADO_BAT)])
    return parsear_estado(texto, codigo)


def parsear_estado(texto, codigo=None):
    datos = {
        "codigo": codigo,
        "contenedores": {},
        "servicios": {},
        "ligas": {},      # nombre -> {"fecha":..., "partidos":int, "sin_resultado":int}
        "pendientes": {},
        "resumen": [],
        "texto": texto,
    }
    seccion = None
    for linea in texto.splitlines():
        s = linea.strip()
        if s.startswith("== "):
            seccion = s.strip("= ").upper()
            continue
        if not s:
            continue
        if seccion and seccion.startswith("CONTENEDORES"):
            for k, v in re.findall(r"(\w+)=(\S+)", s):
                datos["contenedores"][k] = v
        elif seccion and seccion.startswith("SERVICIOS"):
            for k, v in re.findall(r"(\w+)=(\S+)", s):
                datos["servicios"][k] = v
        elif seccion and seccion.startswith("RESULTADOS POR LIGA"):
            m = re.match(r"(\S+)\s+(\d{4}-\d{2}-\d{2})\s+(\d+)\s+(\d+)", s)
            if m:
                datos["ligas"][m.group(1)] = {
                    "fecha": m.group(2),
                    "partidos": int(m.group(3)),
                    "sin_resultado": int(m.group(4)),
                }
        elif seccion and seccion.startswith("PENDIENTES"):
            for k, v in re.findall(r"(\w+)=(\d+)", s):
                datos["pendientes"][k] = int(v)
        elif seccion and seccion.startswith("RESUMEN"):
            if s.startswith("-"):
                datos["resumen"].append(s.lstrip("- ").strip())
    return datos


def imprimir_tabla_ligas(antes, despues):
    """Imprime, liga a liga, los partidos nuevos (delta) y los que siguen sin
    resultado. Devuelve el total de partidos nuevos."""
    nombres = sorted(set(antes["ligas"]) | set(despues["ligas"]))
    total_nuevos = 0
    print()
    print(f"  {'LIGA':<28}{'ANTES':>7}{'DESPUES':>9}{'NUEVOS':>8}{'SIN RES.':>10}")
    print("  " + "-" * 62)
    for n in nombres:
        a = antes["ligas"].get(n, {})
        d = despues["ligas"].get(n, {})
        pa = a.get("partidos", 0)
        pd = d.get("partidos", 0)
        nuevos = pd - pa
        total_nuevos += max(nuevos, 0)
        sin = d.get("sin_resultado", 0)
        marca = ""
        if nuevos > 0:
            marca = "  <-- +%d" % nuevos
        elif sin > 0:
            marca = "  (sin resultado)"
        print(f"  {n:<28}{pa:>7}{pd:>9}{nuevos:>8}{sin:>10}{marca}")
    print("  " + "-" * 62)
    print(f"  TOTAL partidos nuevos: {total_nuevos}")
    return total_nuevos
