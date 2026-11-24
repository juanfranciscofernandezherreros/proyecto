# -*- coding: utf-8 -*-
r"""basket - CLI unico del proyecto Basketball (sustituye los 20 .bat de 1_EJECUTAR).

Cada subcomando ejecuta su lanzador de scripts\py\lanzadores\. Sin subcomando
(o doble clic en basket.cmd) muestra un menu.

Uso:  python scripts\py\basket.py <comando> [args]
      basket.cmd <comando> [args]          (shim de Windows)
Ejemplos:  basket estado | basket resultados EUROLIGA | basket ciclo-diario
"""
import os
import subprocess
import sys
import webbrowser
from datetime import datetime
from pathlib import Path

SCRIPTS_PY = Path(__file__).resolve().parent
LANZADORES = SCRIPTS_PY / "lanzadores"
sys.path.insert(0, str(SCRIPTS_PY / "arranque"))
import config as _config

CFG = _config.cargar()

# Comandos que no levantan Grafana al empezar (rapidos, de vigilancia o que ya la abren).
SIN_OBSERVABILIDAD = {"estado", "antibloqueo", "vigilar", "monitor", "grafana", "tokens"}
DASHBOARD_LOGS = "basket-logs"

# comando coherente -> (modulo lanzador, descripcion)
COMANDOS = {
    "estado":            ("estado",                    "Estado del sistema (solo lectura)"),
    "arrancar":          ("arrancar_todo",             "Arrancar web, API, projector y launcher"),
    "verificar":         ("verificar",                 "Verificacion del SDD (verde/rojo)"),
    "antibloqueo":       ("antibloqueo",               "Mantener el PC despierto"),
    "resultados":        ("extraer_resultados",        "Extraer RESULTS [LIGA] [limite]"),
    "resultados-ayer":   ("resultados_ayer",           "Resultados de ayer: RESULTS_YESTERDAY_<fecha>.csv, Postgres y projector; si ya estan en Mongo no extrae [AAAA-MM-DD] [--solo-csv] [--forzar]"),
    "curiosidades":      ("curiosidades",              "Publicar en Mongo las curiosidades ampliadas para la web (pestana Todas)"),
    "procesar-csv":      ("procesar_csv_resultados",   "Cargar en Postgres los RESULTS ya en disco [LIGA] [todos]"),
    "orquestar":         ("ligas_orquestar",           "Orquestar ligas [LIGA] [results|datos|todo] [limite]"),
    "ligas":             ("ligas_resultados",          "Ejecutar ligas (menu o todas)"),
    "datos":             ("datos_euroliga",            "Flujo de datos por dataset [pais] [competicion] [limite]"),
    "extraer-todo":      ("extraer_csv_completo",      "Extraer el resto de CSV y procesar pendientes [LIGA] [limite]"),
    "reextraer":         ("reextraer",                 "Reextraer partidos concretos [--dataset D] [--fichero F] [--progreso P] <match_id...>"),
    "ultimos":         ("ultimos_partidos",          "Procesar los ultimos partidos de una liga"),
    "pendientes":        ("matchids_pendientes",       "Procesar los partidos pendientes hasta el projector (comprueba Mongo) [csv] [limite]"),
    "csv-faltan":        ("csv_faltan",                "CSV que faltan por generar y por que (solo lectura) [match_id]"),
    "comprobar":        ("comprobar_results_fixtures","Comprobar que RESULTS y FIXTURES estan listos"),
    "telegram":          ("telegram",                  "Aviso por Telegram de cada CSV procesado [prueba|una-vez|chat]"),
    "tokens":            ("tokens",                    "Medir la carga de tokens de CLAUDE.md, reglas y skills (para AHORRO-TOKENS.md)"),
    "auditoria":         ("auditoria_fixtures",        "Lanzar la auditoria de fixtures"),
    "auditar":           ("auditar",                   "Auditar la integridad de los datos en Postgres (solo lectura)"),
    "pronostico":        ("pronostico",                "Previa de la proxima jornada: datos [pais] [competicion] | publicar <fichero>"),
    "ids-ayer":        ("ids_partidos_ayer",         "Imprimir los match_id de ayer"),
    "datos-ayer":        ("datos_ayer",                "Extraer los datos de los partidos de ayer en fixtures [AAAA-MM-DD]"),
    "cuadrar":           ("cuadrar_dia",               "Cuadrar los partidos de un dia: Flashscore, fixtures y Mongo [AAAA-MM-DD]"),
    "monitor":           ("monitor_pendientes",       "Abrir el monitor de pendientes en vivo"),
    "grafana":           ("grafana_pendientes",        "Abrir el dashboard de pendientes en Grafana"),
    "vigilar":           ("vigilar_servicios",         "Vigilante de servicios [minutos|una-vez]"),
    "ciclo-diario":      ("ciclo_diario",              "Ciclo diario (tarea programada)"),
    "inicio-automatico": ("automatico_inicio",         "Procesamiento al iniciar sesion (tarea programada)"),
}


def fichero_log(comando, ahora=None):
    r"""Ruta del log de una ejecucion: DATA_DIR\logs\basket\<comando>_<AAAAMMDD_HHMMSS>.log."""
    ahora = ahora or datetime.now()
    base = Path(CFG.get("DATA_DIR") or r"C:\data\basketball") / "logs" / "basket"
    return base / f"{comando}_{ahora:%Y%m%d_%H%M%S}.log"


def _asegurar_observabilidad(comando, log):
    """Levanta Loki, Grafana y promtail para ver el log en vivo. Si falla, avisa y sigue."""
    if comando in SIN_OBSERVABILIDAD or os.environ.get("BASKET_SIN_GRAFANA") == "1":
        return
    rc = subprocess.run([sys.executable, str(SCRIPTS_PY / "arranque" / "asegurar.py"),
                         "grafana", "promtail"]).returncode
    if rc != 0:
        print("AVISO: Grafana o promtail no arrancaron; el comando sigue sin logs en vivo.", flush=True)
        return
    url = (CFG.get("GRAFANA_URL") or "http://localhost:8084").rstrip("/")
    # Enlace fijo pedido por el usuario: todos los comandos y ejecuciones de las últimas 3 h.
    enlace = (f"{url}/d/{DASHBOARD_LOGS}/basketball-logs-de-basket?orgId=1"
              f"&from=now-3h&to=now&timezone=browser&var-comando=$__all&var-ejecucion=$__all"
              f"&var-buscar=&refresh=5s")
    print(f"Logs en vivo: {enlace}", flush=True)
    # Pedido por el usuario (2026-11-24): una sola pestaña. El dashboard muestra todas
    # las ejecuciones y se refresca solo, así que se abre como mucho una vez cada 12 h.
    if os.environ.get("BASKET_NO_ABRIR_GRAFANA") != "1" and _toca_abrir_grafana():
        try:
            webbrowser.open(enlace)
        except Exception as e:  # sin navegador no se corta el comando
            print(f"AVISO: no se pudo abrir el navegador ({e}).", flush=True)


HORAS_ENTRE_PESTANAS = 12


def marca_grafana():
    """Fichero cuya fecha indica cuándo se abrió por última vez el dashboard."""
    return fichero_log("x").parent / ".grafana-abierta"


def _toca_abrir_grafana(ahora=None):
    """True (y renueva la marca) si no se abrió el dashboard en las últimas 12 h."""
    marca = marca_grafana()
    ahora = ahora if ahora is not None else datetime.now().timestamp()
    try:
        if ahora - marca.stat().st_mtime < HORAS_ENTRE_PESTANAS * 3600:
            return False
    except OSError:
        pass  # no existe: primera vez
    try:
        marca.parent.mkdir(parents=True, exist_ok=True)
        marca.touch()
        os.utime(marca, (ahora, ahora))
    except OSError:
        pass  # si no se puede guardar la marca, se abre igual
    return True


def _ejecutar(comando, args):
    """Lanza el comando con su salida por consola y, a la vez, en su fichero de log."""
    modulo = COMANDOS[comando][0]
    log = fichero_log(comando)
    log.parent.mkdir(parents=True, exist_ok=True)
    _asegurar_observabilidad(comando, log)
    print(f"Log: {log}", flush=True)
    env = dict(os.environ, PYTHONUNBUFFERED="1", PYTHONIOENCODING="utf-8")
    hijo = subprocess.Popen([sys.executable, "-u", str(LANZADORES / f"{modulo}.py"), *args],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
    salida = sys.stdout.buffer
    with open(log, "wb") as fh:
        while True:
            trozo = hijo.stdout.read1(4096)
            if not trozo:
                break
            salida.write(trozo)
            salida.flush()
            fh.write(trozo)
            fh.flush()
    return hijo.wait()


def _menu():
    print("\n" + "=" * 60)
    print(" BASKETBALL - comandos disponibles")
    print("=" * 60)
    claves = list(COMANDOS)
    for i, c in enumerate(claves, 1):
        print(f"  [{i:>2}] {c:<18} {COMANDOS[c][1]}")
    print("  [ 0] salir")
    sel = input("\nElige un comando (numero o nombre): ").strip()
    if sel in ("0", ""):
        return 0
    if sel.isdigit():
        n = int(sel)
        if 1 <= n <= len(claves):
            return _ejecutar(claves[n - 1], [])
        print("Seleccion no valida.")
        return 1
    if sel in COMANDOS:
        return _ejecutar(sel, [])
    print(f"Comando desconocido: {sel}")
    return 1


def main():
    args = sys.argv[1:]
    if not args:
        return _menu()
    comando = args[0].lower()
    if comando in ("-h", "--help", "ayuda", "help"):
        print(__doc__)
        print("Comandos:")
        for c, (_m, d) in COMANDOS.items():
            print(f"  {c:<18} {d}")
        return 0
    if comando not in COMANDOS:
        print(f"Comando desconocido: {comando}. Usa 'basket ayuda' para ver la lista.")
        return 1
    return _ejecutar(comando, args[1:])


if __name__ == "__main__":
    sys.exit(main())
