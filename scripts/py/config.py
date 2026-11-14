# -*- coding: utf-8 -*-
r"""Configuracion unica del proyecto (equivale a scripts\config.ps1, sin PowerShell).

Lee config\basketball.env y config\basketball.local.env, resuelve referencias
${CLAVE} y localiza el JDK 21. Prioridad: variable de entorno > basketball.local.env
> basketball.env. Es la pieza fundacional: el resto de modulos Python la usan.

Uso como libreria:
    from config import cargar, ruta
    cfg = cargar()            # dict con todas las claves
    data = ruta("DATA_DIR")   # una clave como Path

Uso en linea de comandos (paridad con `config.ps1 -FormatoBat`):
    python scripts\py\config.py            -> imprime CLAVE=valor, una por linea
"""
import os
import re
import sys
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parents[2]  # C:\Develop\basketball

_cache = None


def _leer_env(path):
    """Lee un fichero CLAVE=valor; ignora vacias y comentarios. Mantiene el orden."""
    valores = {}
    if not path.exists():
        return valores
    for linea in path.read_text(encoding="utf-8").splitlines():
        t = linea.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        clave, valor = t.split("=", 1)
        valores[clave.strip()] = valor.strip()
    return valores


def _buscar_jdk21():
    raices = [
        r"C:\Program Files\Eclipse Adoptium",
        r"C:\Program Files\Java",
        r"C:\Program Files\Microsoft",
        r"C:\Program Files\Zulu",
    ]
    candidatos = []
    for raiz in raices:
        p = Path(raiz)
        if not p.is_dir():
            continue
        for d in p.iterdir():
            if d.is_dir() and d.name.startswith("jdk-21") and (d / "bin" / "java.exe").exists():
                candidatos.append(d)

    def clave_version(d):
        # Normaliza 21.0.12 -> '000021.000000.000012' para ordenar como numeros.
        base = re.sub(r"^jdk-", "", d.name).split("-")[0]
        return ".".join(m.group().zfill(6) for m in re.finditer(r"\d+", base))

    if not candidatos:
        return ""
    return str(max(candidatos, key=clave_version))


def cargar():
    """Devuelve el dict de configuracion (cacheado)."""
    global _cache
    if _cache is not None:
        return _cache

    defaults = _leer_env(WORKSPACE / "config" / "basketball.env")
    local = _leer_env(WORKSPACE / "config" / "basketball.local.env")

    cfg = {"WORKSPACE": str(WORKSPACE), "SCRIPTS": str(WORKSPACE / "scripts")}
    claves = list(defaults.keys()) + [k for k in local if k not in defaults]
    for clave in claves:
        desde_env = os.environ.get(clave)
        if desde_env:
            valor = desde_env
        elif clave in local:
            valor = local[clave]
        else:
            valor = defaults[clave]
        # ${CLAVE} -> valor de una clave ya calculada (vacio si aun no existe).
        for m in re.finditer(r"\$\{([A-Z0-9_]+)\}", str(valor)):
            valor = valor.replace(m.group(0), str(cfg.get(m.group(1), "")))
        cfg[clave] = valor

    java_home = cfg.get("JAVA_HOME", "")
    if not java_home or not (Path(java_home) / "bin" / "java.exe").exists():
        cfg["JAVA_HOME"] = _buscar_jdk21()
    cfg["JAVA_EXE"] = str(Path(cfg["JAVA_HOME"]) / "bin" / "java.exe") if cfg.get("JAVA_HOME") else ""

    _cache = cfg
    return cfg


def ruta(clave):
    """Devuelve el valor de una clave como Path (o None si no existe o esta vacia)."""
    v = cargar().get(clave)
    return Path(v) if v else None


def main():
    for clave, valor in cargar().items():
        print(f"{clave}={valor}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
