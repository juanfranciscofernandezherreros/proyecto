# -*- coding: utf-8 -*-
r"""Vigilante: envia al bot de Telegram cada CSV que termina de procesar el launcher.

Todos los caminos de carga (resultados-ayer, pendientes, run_all_csv_batches,
reextraer...) acaban en el launcher, que deja una fila por CSV en
public.batch_launch_request. Este vigilante lee esa tabla cada TELEGRAM_INTERVALO
segundos y, por cada CSV terminado, manda un mensaje con solo tres cosas: el estado
(COMPLETADO / FALLIDO), el nombre del CSV y la hora (Madrid) en que se proceso.

Uso:  python scripts\py\monitor\telegram_csv.py [--prueba | --una-vez]
  --prueba   envia un mensaje de prueba y termina.
  --una-vez  una sola pasada y termina.

Configuracion: TELEGRAM_BOT_TOKEN y TELEGRAM_CHAT_ID (solo en
config\basketball.local.env). Estado en DATA_DIR\state\telegram_csv.json: la primera
vez empieza en "ahora" y no reenvia el historico.

El envio usa curl.exe: urllib de Python se quedaba colgado contra api.telegram.org
en esta maquina.
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SCRIPTS_PY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_PY))
import config as _config

CFG = _config.cargar()

# Misma consulta que sql\consultas\2026-11-17_1240_csv-terminados-para-telegram.sql,
# con la marca de agua del vigilante en lugar de "hace una hora".
SQL = """
SELECT COALESCE(json_agg(to_jsonb(t) ORDER BY t.finished_at), '[]'::json)::text
FROM (
    SELECT request_id, batch_type, status, exit_code, file_path,
           to_char(finished_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS finished_at,
           left(error, 300) AS error
    FROM public.batch_launch_request
    WHERE status IN ('COMPLETED', 'FAILED')
      AND finished_at > '{desde}'::timestamptz
    ORDER BY finished_at
    LIMIT 50
) t;
"""


def configurado(cfg=CFG):
    return bool((cfg.get("TELEGRAM_BOT_TOKEN") or "").strip() and (cfg.get("TELEGRAM_CHAT_ID") or "").strip())


def fichero_estado():
    return Path(CFG.get("DATA_DIR") or r"C:\data\basketball") / "state" / "telegram_csv.json"


def leer_marca():
    """Ultimo finished_at enviado (ISO UTC). Si no hay estado, "ahora"."""
    try:
        return json.loads(fichero_estado().read_text(encoding="utf-8"))["desde"]
    except Exception:
        marca = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        guardar_marca(marca)
        return marca


def guardar_marca(marca):
    f = fichero_estado()
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps({"desde": marca}), encoding="utf-8")


def terminados_desde(desde):
    """Filas de batch_launch_request terminadas despues de `desde`, en orden."""
    if "'" in desde:
        raise ValueError("marca de agua no valida")
    p = subprocess.run(
        ["docker", "exec", "-i", CFG.get("POSTGRES_CONTAINER"), "psql", "-U", CFG.get("DB_USER"),
         "-d", CFG.get("DB_NAME"), "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1"],
        input=SQL.format(desde=desde), capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise RuntimeError("psql: " + (p.stderr.strip() or p.stdout.strip()))
    texto = p.stdout.strip()
    return json.loads(texto) if texto else []


ESTADO = {"COMPLETED": "✅ COMPLETADO", "FAILED": "❌ FALLIDO"}


def hora_local(finished_at):
    """finished_at (ISO UTC) a hora de Madrid, "dd/mm HH:MM:SS". Vacio si no se entiende."""
    try:
        from zoneinfo import ZoneInfo
        dt = datetime.fromisoformat((finished_at or "").replace("Z", "+00:00"))
        return dt.astimezone(ZoneInfo("Europe/Madrid")).strftime("%d/%m %H:%M:%S")
    except Exception:
        return ""


def aviso(fila):
    """El aviso de un CSV: solo el estado, el nombre del CSV y la hora en que se proceso."""
    estado = ESTADO.get(fila.get("status"), fila.get("status") or "?")
    nombre = Path(fila.get("file_path") or "").name or "(sin fichero)"
    return " · ".join(x for x in (estado, nombre, hora_local(fila.get("finished_at"))) if x)


def _curl(metodo, campos, fichero=None):
    """POST multipart a la API de Telegram con curl.exe. Devuelve el JSON de respuesta.
    Los textos van con --form-string (curl no interpreta ';', '@' ni '<'); el
    fichero, si lo hay, como adjunto del campo `document`."""
    url = f"https://api.telegram.org/bot{CFG['TELEGRAM_BOT_TOKEN'].strip()}/{metodo}"
    args = ["curl.exe", "-s", "-m", "120", "-X", "POST", url]
    for clave, valor in campos.items():
        args += ["--form-string", f"{clave}={valor}"]
    if fichero:
        args += ["-F", f"document=@{fichero}"]
    p = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    try:
        r = json.loads(p.stdout)
    except ValueError:
        raise RuntimeError(f"Telegram no respondio (curl {p.returncode})")
    if not r.get("ok"):
        raise RuntimeError(f"Telegram: {r.get('description')}")
    return r


def enviar(fila):
    """Un mensaje por CSV: estado, nombre y hora (ni el fichero ni sus datos)."""
    _curl("sendMessage", {"chat_id": CFG["TELEGRAM_CHAT_ID"].strip(), "text": aviso(fila)})


def pasada():
    """Envia lo terminado desde la marca de agua. Devuelve cuantos se enviaron."""
    desde = leer_marca()
    enviados = 0
    for fila in terminados_desde(desde):
        try:
            enviar(fila)
            enviados += 1
            print(f"[telegram] enviado {Path(fila.get('file_path') or '').name} ({fila.get('status')})", flush=True)
        except Exception as e:
            # Sin avanzar la marca: se reintenta en la siguiente pasada.
            print(f"[telegram] AVISO: no se pudo enviar {fila.get('file_path')}: {e}", flush=True)
            return enviados
        guardar_marca(fila["finished_at"])
    return enviados


def main(argv):
    if not configurado():
        print("Telegram desactivado: faltan TELEGRAM_BOT_TOKEN o TELEGRAM_CHAT_ID en config\\basketball.local.env.")
        return 1
    if "--prueba" in argv:
        _curl("sendMessage", {"chat_id": CFG["TELEGRAM_CHAT_ID"].strip(),
                              "text": "\U0001F3C0 Basketball: prueba del aviso de CSV procesados."})
        print("Mensaje de prueba enviado.")
        return 0
    if "--una-vez" in argv:
        print(f"Enviados: {pasada()}")
        return 0
    intervalo = int(CFG.get("TELEGRAM_INTERVALO") or 10)
    print(f"[telegram] vigilando public.batch_launch_request cada {intervalo} s", flush=True)
    while True:
        try:
            pasada()
        except Exception as e:
            print(f"[telegram] AVISO: {e}", flush=True)
        time.sleep(intervalo)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
