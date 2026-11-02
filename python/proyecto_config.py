"""Configuracion unica del proyecto (config/basketball.env), igual que scripts/config.ps1.

Uso:  from proyecto_config import CONFIG, path
      CONFIG["DB_URL"]            -> texto
      path("COMPETITIONS_DIR")    -> pathlib.Path

Prioridad: variable de entorno > config/basketball.local.env > config/basketball.env.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parents[1]
_REFERENCE = re.compile(r"\$\{([A-Z0-9_]+)\}")
_JDK_ROOTS = (r"C:\Program Files\Eclipse Adoptium", r"C:\Program Files\Java",
              r"C:\Program Files\Microsoft", r"C:\Program Files\Zulu")


def _read_env_file(file: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not file.is_file():
        return values
    for line in file.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def _version_key(folder: Path) -> tuple[int, ...]:
    numbers = re.findall(r"\d+", folder.name.removeprefix("jdk-").split("-")[0])
    return tuple(int(n) for n in numbers)


def _find_jdk21() -> str:
    candidates = [jdk for root in _JDK_ROOTS if Path(root).is_dir()
                  for jdk in Path(root).glob("jdk-21*") if (jdk / "bin" / "java.exe").is_file()]
    return str(max(candidates, key=_version_key)) if candidates else ""


def _load() -> dict[str, str]:
    defaults = _read_env_file(WORKSPACE / "config" / "basketball.env")
    local = _read_env_file(WORKSPACE / "config" / "basketball.local.env")
    config: dict[str, str] = {"WORKSPACE": str(WORKSPACE), "SCRIPTS": str(WORKSPACE / "scripts")}
    for key in list(defaults) + [k for k in local if k not in defaults]:
        value = os.environ.get(key) or local.get(key, defaults.get(key, ""))
        config[key] = _REFERENCE.sub(lambda m: config.get(m.group(1), ""), value)
    java_home = config.get("JAVA_HOME", "")
    if not java_home or not (Path(java_home) / "bin" / "java.exe").is_file():
        config["JAVA_HOME"] = _find_jdk21()
    config["JAVA_EXE"] = str(Path(config["JAVA_HOME"]) / "bin" / "java.exe") if config["JAVA_HOME"] else ""
    return config


CONFIG = _load()


def path(key: str) -> Path:
    """Valor de configuracion como ruta."""
    return Path(CONFIG[key])
