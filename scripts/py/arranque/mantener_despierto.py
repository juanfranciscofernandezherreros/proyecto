# -*- coding: utf-8 -*-
r"""Antibloqueo: impide que Windows suspenda el equipo, apague o bloquee la pantalla
mientras este proceso viva (equivale a scripts\arranque\MANTENER_DESPIERTO.ps1, sin
PowerShell; usa ctypes sobre las mismas APIs de Windows).

1. SetThreadExecutionState: funcion oficial de Windows para no suspender ni apagar la
   pantalla (la que usan los reproductores de video).
2. SendInput con un movimiento de raton de 0 pixeles cada 50 s: el cursor no se mueve
   y no se pulsa ninguna tecla, pero Windows lo cuenta como actividad y reinicia su
   contador de inactividad (el que dispara el bloqueo de pantalla). SetThreadExecution-
   State por si solo no lo evita.

Al cerrar la ventana/proceso, Windows recupera su comportamiento normal.
"""
import ctypes
import sys
import time
from ctypes import wintypes

ES_CONTINUOUS = 0x80000000
ES_SYSTEM_REQUIRED = 0x00000001
ES_DISPLAY_REQUIRED = 0x00000002
_FLAGS = ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED

INPUT_MOUSE = 0
MOUSEEVENTF_MOVE = 0x0001


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG),
                ("mouseData", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG))]


class _INPUTunion(ctypes.Union):
    _fields_ = [("mi", MOUSEINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("u", _INPUTunion)]


def _actividad():
    """Movimiento relativo de 0 pixeles: reinicia el contador de inactividad sin mover
    el cursor."""
    inp = INPUT(type=INPUT_MOUSE)
    inp.u.mi = MOUSEINPUT(0, 0, 0, MOUSEEVENTF_MOVE, 0, None)
    enviados = ctypes.windll.user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))
    return enviados == 1


def main():
    # Titulo de ventana que INICIAR_ANTIBLOQUEO busca para no duplicar (no cambiar).
    try:
        ctypes.windll.kernel32.SetConsoleTitleW("Mantener PC Activo")
    except Exception:
        pass
    print("Antibloqueo activo: Windows no suspendera el equipo, ni apagara ni bloqueara la pantalla.")
    print("Cierra esta ventana para detenerlo.", flush=True)
    while True:
        if ctypes.windll.kernel32.SetThreadExecutionState(_FLAGS) == 0:
            print("AVISO: Windows rechazo la peticion de mantener el equipo despierto.", flush=True)
        if not _actividad():
            print("AVISO: Windows rechazo la senal de actividad (contador de inactividad).", flush=True)
        time.sleep(50)


if __name__ == "__main__":
    sys.exit(main())
