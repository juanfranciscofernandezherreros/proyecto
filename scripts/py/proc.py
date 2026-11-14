# -*- coding: utf-8 -*-
r"""Helpers para lanzar procesos desde los orquestadores Python.

Reemplaza el patron `%PS% -File ...` / `call ...bat` de los .bat/.ps1: ejecuta un
comando, captura su salida (con eco opcional para procesos largos) y propaga el
codigo de salida. No contiene logica de negocio.
"""
import subprocess


def ejecutar(cmd, titulo=None, eco=False, cwd=None, env=None):
    """Lanza `cmd` (lista de argumentos). Devuelve (codigo, texto).

    eco=True imprime la salida segun llega (para cargas largas); eco=False la
    captura en silencio. stderr se mezcla con stdout.
    """
    if titulo:
        print(titulo, flush=True)
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace", bufsize=1,
        cwd=cwd, env=env,
    )
    lineas = []
    for linea in proc.stdout:
        lineas.append(linea.rstrip("\n"))
        if eco:
            print(linea, end="", flush=True)
    proc.wait()
    return proc.returncode, "\n".join(lineas)


def validar_limite(valor, por_defecto=10):
    """Valida un limite de partidos (entero >= 1). Equivale a validar_limite.bat.

    Devuelve el entero valido, o lanza ValueError con un mensaje en espanol.
    """
    if valor is None or str(valor).strip() == "":
        return por_defecto
    try:
        n = int(str(valor).strip())
    except ValueError:
        raise ValueError(f"Limite invalido: '{valor}' no es un numero entero.")
    if n < 0:
        raise ValueError(f"Limite invalido: {n} debe ser mayor o igual que 0.")
    return n
