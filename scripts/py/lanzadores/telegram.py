# -*- coding: utf-8 -*-
r"""Lanzador: aviso por Telegram de cada CSV procesado.

Uso: basket telegram [prueba|una-vez|chat]
  (sin opcion)  arranca el vigilante en segundo plano si no lo estaba.
  prueba        envia un mensaje de prueba al bot.
  una-vez       envia ahora lo terminado desde la ultima vez y termina.
  chat          muestra los chat_id que han escrito al bot (para TELEGRAM_CHAT_ID).
"""
import json
import subprocess
import sys

from _base import ensure, run_mod, CFG


def chats():
    token = (CFG.get("TELEGRAM_BOT_TOKEN") or "").strip()
    if not token:
        print("Falta TELEGRAM_BOT_TOKEN en config\\basketball.local.env.")
        return 1
    p = subprocess.run(["curl.exe", "-s", "-m", "30", f"https://api.telegram.org/bot{token}/getUpdates"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    try:
        datos = json.loads(p.stdout)
    except ValueError:
        print("Telegram no respondio.")
        return 1
    vistos = {}
    for u in datos.get("result", []):
        chat = (u.get("message") or u.get("my_chat_member") or {}).get("chat") or {}
        if chat.get("id") is not None:
            vistos[chat["id"]] = chat.get("username") or chat.get("title") or chat.get("first_name") or ""
    if not vistos:
        print("Nadie ha escrito todavia al bot: abrelo en Telegram y pulsa Iniciar (/start).")
        return 1
    for cid, nombre in vistos.items():
        print(f"chat_id {cid}  {nombre}")
    return 0


if __name__ == "__main__":
    opcion = (sys.argv[1] if len(sys.argv) > 1 else "").lower()
    if opcion == "chat":
        sys.exit(chats())
    if opcion in ("prueba", "una-vez"):
        sys.exit(run_mod("monitor/telegram_csv.py", f"--{opcion}"))
    if opcion:
        print(__doc__)
        sys.exit(1)
    sys.exit(ensure("telegram"))
