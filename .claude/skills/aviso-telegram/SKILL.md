---
name: aviso-telegram
description: Aviso por Telegram de cada CSV procesado en el proyecto Basketball — arranca, comprueba, prueba y arregla el vigilante que envía al bot @MiGrafanaDashboardOutOfHome_bot una línea por CSV que termina en el launcher (estado COMPLETADO/FALLIDO, nombre del CSV y hora de Madrid; nunca el fichero ni su contenido). Usar cuando el usuario pida el aviso de Telegram, que le lleguen los CSV al móvil, pregunte si el bot funciona, por qué no le llegan los avisos, o quiera arrancarlo, pararlo o cambiar el token o el chat.
---

# Aviso por Telegram de cada CSV procesado

Cada CSV que procesa el launcher deja una fila en `public.batch_launch_request`. Un
vigilante (`scripts\py\monitor\telegram_csv.py`) lee esa tabla cada 10 s y, por cada
CSV terminado, manda al bot **una sola línea**:

```
✅ COMPLETADO · POINT_BY_POINT_20261117125350_8ArlEYR6.csv · 17/11 12:54:49
```

(`❌ FALLIDO` si falló). **Nunca** el fichero ni su contenido: solo estado, nombre y
hora de Madrid. No reenvía el histórico; si un envío falla, lo reintenta en la
siguiente pasada sin perder ninguno.

## 1. Arrancar

Sin preguntar nada. Lo levanta solo cualquier comando que use el launcher
(`resultados-ayer`, `pendientes`…); a mano:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd telegram"
```

Imprime `[telegram] iniciando` o `ya estaba en ejecucion`. Si dice `desactivado`,
falta el token o el chat (paso 4).

## 2. Comprobar que funciona

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'python*' -and $_.CommandLine -like '*monitor*telegram_csv.py*' } | Select-Object ProcessId, CreationDate
Get-Content C:\data\basketball\logs\telegram_csv.log -Tail 10
```

- Debe haber **un** proceso. Dos a la vez mandan cada aviso dos veces: parar el más
  antiguo (paso 5).
- En el log, una línea `enviado <csv> (COMPLETED)` por CSV procesado. `AVISO:` = no
  se pudo enviar (se reintenta).
- Marca de agua (último CSV enviado, UTC): `C:\data\basketball\state\telegram_csv.json`.

Qué debería haber recibido el bot desde hace una hora:

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_1240_csv-terminados-para-telegram.sql
```

## 3. Probar

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd telegram prueba"
```

Manda un mensaje de prueba al móvil. `basket telegram una-vez` envía ya lo que haya
pendiente y termina.

## 4. Configuración (token y chat)

Solo en `config\basketball.local.env`, que git ignora. **Nunca** en
`config\basketball.env` ni en un commit (lo vigila el test
`test_token_no_esta_en_la_configuracion_versionada`).

```
TELEGRAM_BOT_TOKEN=<token de BotFather>
TELEGRAM_CHAT_ID=<id del chat>
```

- `chat_id`: el usuario abre t.me/MiGrafanaDashboardOutOfHome_bot y le escribe
  cualquier cosa; luego `basket telegram chat` lo muestra.
- Token nuevo (tras `/revoke` en BotFather): cambiarlo en ese fichero y reiniciar el
  vigilante (paso 5).
- `TELEGRAM_INTERVALO` (10 s) en `config\basketball.env`.

## 5. Reiniciar o parar

Parar **solo** procesos python (filtrar por texto mata también la shell que lanza el
filtro):

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'python*' -and $_.CommandLine -like '*monitor*telegram_csv.py*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -Confirm:$false }
```

Después, paso 1 para arrancarlo con el código o la configuración nuevos.

## Qué decir al terminar

Si el vigilante está en marcha (PID y hora de arranque), los últimos CSV enviados
según el log y, si se probó, que llegó el mensaje de prueba.

| Sale | Qué hacer |
|---|---|
| `desactivado (sin token o chat_id ...)` | Completar el paso 4 |
| `Nadie ha escrito todavia al bot` | Que el usuario escriba al bot y repetir `basket telegram chat` |
| `AVISO: ... Telegram no respondio` | Red caída o Telegram lento: se reintenta solo; probar `curl.exe -s https://api.telegram.org` |
| `AVISO: ... Telegram: Unauthorized` | Token revocado o mal copiado: paso 4 y reiniciar |
| `AVISO: ... chat not found` | `TELEGRAM_CHAT_ID` mal: `basket telegram chat` y paso 4 |
| `AVISO: psql: ...` | Postgres parado: `basket telegram` lo levanta |
| Avisos repetidos | Dos vigilantes: paso 5 y arrancar uno |
| Llega contenido o fichero | Vigilante con código viejo: paso 5 y arrancar |

El envío usa `curl.exe`: urllib de Python se quedaba colgado contra api.telegram.org
en esta máquina.

## Relacionado

- Lógica: `scripts\py\monitor\telegram_csv.py`, `scripts\py\lanzadores\telegram.py`,
  servicio `telegram` en `scripts\py\arranque\asegurar.py` (el launcher depende de él).
- Plan: `docs\PLAN-telegram-csv-procesados.md`. Evidencia: `docs\VERIFICACION-SDD.md` §20.
