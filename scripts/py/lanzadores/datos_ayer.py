# -*- coding: utf-8 -*-
r"""Lanzador: extraer e importar los datos de los partidos de ayer que hay en fixtures.

Uso: datos_ayer.py [AAAA-MM-DD]     (por defecto, ayer en Europe/Madrid)

Lee de fixtures.fixtures los match_id de ese dia, los guarda en un fichero y llama a
reextraer (resumen, estadisticas de equipo y jugadores, jugada a jugada) con un
fichero de progreso: si se repite el comando se reanuda y se saltan los partidos OK.
Para forzar de nuevo, borrar el fichero de progreso.
"""
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from _base import CFG, ensure, run_mod

FECHA = re.compile(r"^\d{4}-\d{2}-\d{2}$")
HOY_MENOS_1 = "((now() AT TIME ZONE 'Europe/Madrid')::date - 1)"


def consulta(fecha=None):
    """SQL de los match_id de fixtures de una fecha local (o de ayer si es None)."""
    if fecha is not None:
        if not FECHA.match(fecha):
            raise ValueError(f"Fecha no valida: {fecha!r} (esperado AAAA-MM-DD)")
        datetime.strptime(fecha, "%Y-%m-%d")
        dia = f"DATE '{fecha}'"
    else:
        dia = HOY_MENOS_1
    return ("SELECT f.match_id FROM fixtures.fixtures f "
            f"WHERE (f.event_datetime AT TIME ZONE 'Europe/Madrid')::date = {dia} "
            "ORDER BY f.match_id;")


def activo(env, cfg):
    """True si el paso previo 'datos de ayer' debe ejecutarse antes de los pendientes.
    Se desactiva con SKIP_DATOS_AYER=1 (entorno) o DATOS_AYER=0 (config\\basketball.env)."""
    return env.get("SKIP_DATOS_AYER") != "1" and str(cfg.get("DATOS_AYER", "1")) != "0"


def ids_de_fixtures(fecha=None):
    p = subprocess.run(
        ["docker", "compose", "-f", CFG.get("COMPOSE_FILE"), "exec", "-T", "postgres",
         "psql", "-U", CFG.get("DB_USER"), "-d", CFG.get("DB_NAME"), "--no-psqlrc", "-At",
         "-c", consulta(fecha)],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise RuntimeError("No se pudieron consultar los partidos en fixtures.")
    return [l.strip() for l in p.stdout.splitlines() if l.strip()]


def main(argv):
    fecha = argv[0] if argv else None
    if len(argv) > 1:
        print("Uso: basket datos-ayer [AAAA-MM-DD]")
        return 1
    if ensure("antibloqueo", "postgres", "launcher", "navegador"):
        return 1
    try:
        ids = ids_de_fixtures(fecha)
    except (ValueError, RuntimeError) as e:
        print(f"ERROR: {e}")
        return 1
    etiqueta = fecha or datetime.now().strftime("ayer-%Y%m%d")
    print(f"Partidos de {fecha or 'ayer'} en fixtures: {len(ids)}")
    if not ids:
        print("No hay partidos en fixtures para esa fecha; nada que extraer.")
        return 0
    carpeta = Path(CFG["REPORTS_DIR"]) / "datos-ayer"
    carpeta.mkdir(parents=True, exist_ok=True)
    lista = carpeta / f"ids-{etiqueta}.txt"
    progreso = carpeta / f"progreso-{etiqueta}.txt"
    lista.write_text("\n".join(ids) + "\n", encoding="utf-8")
    print(f"IDs: {lista}\nProgreso (reanudable): {progreso}")
    rc = run_mod("extraer/reextraer.py", "--fichero", lista, "--progreso", progreso)
    print(f"\nTerminado con codigo {rc}. Detalle de cada partido en {progreso}.")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
