# -*- coding: utf-8 -*-
r"""Instala/quita las tareas del Programador de Windows (equivale a
scripts\arranque\TAREA_DIARIA/INICIO/VIGILANCIA.ps1 + .bat, sin PowerShell; usa
schtasks con XML). Las tareas ejecutan los lanzadores de 1_EJECUTAR (shims a Python).

Uso:  python scripts\py\arranque\tareas.py <diaria|inicio|vigilancia> <instalar|quitar|estado|ejecutar> [valor]
  diaria     [HH:mm]     CICLO_DIARIO.bat cada dia (por defecto 06:00)
  inicio     [minutos]   AUTOMATICO_INICIO.bat al iniciar sesion (espera, por defecto 2)
  vigilancia [minutos]   VIGILAR_SERVICIOS.bat al iniciar sesion (por defecto 5)
"""
import getpass
import os
import subprocess
import sys
import tempfile
from pathlib import Path

try:  # la salida localizada de schtasks puede traer caracteres fuera de cp1252
    sys.stdout.reconfigure(errors="replace")
except Exception:
    pass

WORKSPACE = Path(__file__).resolve().parents[2]
EJECUTAR = WORKSPACE / "1_EJECUTAR"
USER = os.environ.get("USERNAME") or getpass.getuser()
COMSPEC = os.environ.get("ComSpec", r"C:\Windows\System32\cmd.exe")

TAREAS = {
    "diaria": {"name": "Basketball - Ciclo diario", "script": EJECUTAR / "CICLO_DIARIO.bat",
               "titulo": "Basketball ciclo diario"},
    "inicio": {"name": "Basketball - Procesamiento automatico al iniciar",
               "script": EJECUTAR / "AUTOMATICO_INICIO.bat", "titulo": "Basketball automatico"},
    "vigilancia": {"name": "Basketball - Vigilar servicios",
                   "script": EJECUTAR / "VIGILAR_SERVICIOS.bat", "titulo": "Vigilante"},
}

CABECERA = '<?xml version="1.0" encoding="UTF-16"?>\n<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">'


def _xml(clave, valor):
    t = TAREAS[clave]
    arg_min = f'/c start "{t["titulo"]}" /min "{t["script"]}"'
    if clave == "diaria":
        trigger = (f'<CalendarTrigger><StartBoundary>2026-01-01T{valor}:00</StartBoundary>'
                   f'<Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger>')
        wake = "<WakeToRun>true</WakeToRun>"
        start_when = "<StartWhenAvailable>true</StartWhenAvailable>"
    else:
        delay = f"<Delay>PT{valor}M</Delay>" if (clave == "inicio" and int(valor) > 0) else ""
        trigger = f'<LogonTrigger><Enabled>true</Enabled><UserId>{USER}</UserId>{delay}</LogonTrigger>'
        wake = ""
        start_when = "<StartWhenAvailable>true</StartWhenAvailable>" if clave == "inicio" else ""
        if clave == "vigilancia":
            arg_min = f'/c start "{t["titulo"]}" /min "{t["script"]}" {valor}'
    return (f'{CABECERA}\n<Triggers>{trigger}</Triggers>'
            f'<Principals><Principal id="Author"><UserId>{USER}</UserId>'
            f'<LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>'
            f'<Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>'
            f'<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>'
            f'<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>{wake}{start_when}'
            f'<ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Enabled>true</Enabled></Settings>'
            f'<Actions Context="Author"><Exec><Command>{COMSPEC}</Command>'
            f'<Arguments>{arg_min}</Arguments><WorkingDirectory>{t["script"].parent}</WorkingDirectory></Exec></Actions></Task>')


def _schtasks(*args):
    return subprocess.run(["schtasks", *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace")


def main():
    a = sys.argv[1:]
    if len(a) < 2 or a[0] not in TAREAS or a[1] not in ("instalar", "quitar", "estado", "ejecutar"):
        print(__doc__)
        return 1
    clave, accion = a[0], a[1]
    name = TAREAS[clave]["name"]

    if accion == "instalar":
        valor = a[2] if len(a) > 2 else ({"diaria": "06:00", "inicio": "2", "vigilancia": "5"}[clave])
        xml = _xml(clave, valor)
        tmp = Path(tempfile.gettempdir()) / f"tarea-{clave}.xml"
        tmp.write_text(xml, encoding="utf-16")
        r = _schtasks("/Create", "/TN", name, "/XML", str(tmp), "/F")
        tmp.unlink(missing_ok=True)
        if r.returncode != 0:
            print(f"ERROR al instalar: {(r.stdout + r.stderr).strip()}")
            return 1
        print(f"Tarea '{name}' instalada ({clave} {valor}).")
        if clave == "vigilancia":
            _schtasks("/Run", "/TN", name)
        return 0
    if accion == "quitar":
        r = _schtasks("/Delete", "/TN", name, "/F")
        print("Tarea quitada." if r.returncode == 0 else "La tarea no estaba instalada.")
        return 0
    if accion == "estado":
        r = _schtasks("/Query", "/TN", name, "/FO", "LIST", "/V")
        print(r.stdout.strip() if r.returncode == 0 else "Tarea no instalada.")
        return 0
    if accion == "ejecutar":
        r = _schtasks("/Run", "/TN", name)
        print(f"Tarea '{name}' lanzada ahora." if r.returncode == 0 else (r.stdout + r.stderr).strip())
        return 0 if r.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
