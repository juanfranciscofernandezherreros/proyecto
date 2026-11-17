# -*- coding: utf-8 -*-
r"""Vigilante: envia al bot de Telegram cada CSV que termina de procesar el launcher.

Todos los caminos de carga (resultados-ayer, pendientes, run_all_csv_batches,
reextraer...) acaban en el launcher, que deja una fila por CSV en
public.batch_launch_request. Este vigilante lee esa tabla cada TELEGRAM_INTERVALO
segundos y manda los datos de cada CSV terminado (COMPLETED o FAILED) como texto
(no el fichero), con su estado, tipo de batch y, si fallo, el error. Si no caben en
un mensaje se parten en varios (TELEGRAM_MAX_MENSAJES, 5 por defecto).

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
EMOJI = {"COMPLETED": "\u2705", "FAILED": "\u274c"}

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


def pie(fila):
    """Texto que acompana al CSV en Telegram (maximo 1024 caracteres)."""
    ruta = Path(fila.get("file_path") or "")
    estado = fila.get("status") or "?"
    hora = (fila.get("finished_at") or "")[:19].replace("T", " ")
    lineas = [f"{EMOJI.get(estado, '')} {estado} \u00b7 {fila.get('batch_type') or '?'}".strip(),
              ruta.name or "(sin fichero)",
              f"\U0001F4C1 {ruta.parent.name}" if ruta.parent.name else "",
              f"\U0001F552 {hora} UTC" if hora else ""]
    if estado != "COMPLETED":
        if fila.get("exit_code") is not None:
            lineas.append(f"exit_code {fila['exit_code']}")
        if fila.get("error"):
            lineas.append("Error: " + fila["error"])
    return "\n".join(l for l in lineas if l)[:1024]


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


LIMITE_MENSAJE = 4096  # caracteres por mensaje de Telegram


def mensajes(fila, lineas, max_mensajes=5):
    """Textos HTML a enviar para un CSV: el pie y los datos (no el fichero), en un
    bloque <pre> por mensaje. La cabecera de columnas se repite en cada bloque. Si no
    caben en `max_mensajes`, el ultimo avisa de cuantas filas quedan sin enviar."""
    from html import escape
    cab_texto = escape(pie(fila)[:900])
    if not lineas:
        return [cab_texto + "\n(fichero no encontrado o vacio)"]
    columnas, datos = escape(lineas[0]), [escape(l) for l in lineas[1:]]
    cab_texto += f"\n{len(datos)} filas"
    salida, i = [], 0
    while i < len(datos) or not salida:
        prefijo = cab_texto + "\n" if not salida else ""
        cuerpo, usado = [columnas], len(prefijo) + len("<pre></pre>") + len(columnas) + 60
        while i < len(datos) and usado + len(datos[i]) + 1 <= LIMITE_MENSAJE:
            cuerpo.append(datos[i])
            usado += len(datos[i]) + 1
            i += 1
        if len(cuerpo) == 1 and i < len(datos):  # una fila sola mas larga que el mensaje
            cuerpo.append(datos[i][:LIMITE_MENSAJE - usado - 2] + "…")
            i += 1
        texto = prefijo + "<pre>" + "\n".join(cuerpo) + "</pre>"
        if len(salida) == max_mensajes - 1 and i < len(datos):
            texto += f"\n… {len(datos) - i} filas más sin enviar"
            salida.append(texto)
            break
        salida.append(texto)
    return salida


def leer_lineas(ruta):
    """Lineas no vacias del CSV (sin BOM). Vacio si no existe."""
    try:
        with open(ruta, encoding="utf-8-sig", errors="replace") as fh:
            return [l.rstrip("\r\n") for l in fh if l.strip()]
    except OSError:
        return []


def enviar(fila):
    """Envia los datos del CSV como texto (no el fichero) en uno o varios mensajes."""
    chat = CFG["TELEGRAM_CHAT_ID"].strip()
    ruta = Path(fila.get("file_path") or "")
    maximo = int(CFG.get("TELEGRAM_MAX_MENSAJES") or 5)
    for texto in mensajes(fila, leer_lineas(ruta) if ruta.is_file() else [], maximo):
        _curl("sendMessage", {"chat_id": chat, "text": texto, "parse_mode": "HTML"})


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
