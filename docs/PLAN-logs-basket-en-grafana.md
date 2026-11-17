# Plan: logs de `basket` en Grafana

## Objetivo

Ver en el navegador, en vivo, la salida de cualquier comando de `basket` (por ejemplo
`basket resultados-ayer`). Hoy esa salida solo sale por consola o en un fichero suelto:
promtail solo recoge los contenedores del compose `local-validation`. Además, Grafana,
Loki y promtail tienen que estar levantados al empezar el comando, para poder ir viendo
los logs mientras corre.

## Diseño

- **Fichero de log por ejecución.** `basket.py` lanza cada comando con la salida
  duplicada: por consola, como ahora, y en
  `DATA_DIR\logs\basket\<comando>_<AAAAMMDD_HHMMSS>.log` (UTF-8). La salida del hijo se
  lee sin buffer (`PYTHONUNBUFFERED=1`).
- **Grafana al inicio.** Antes de lanzar el comando, `basket.py` asegura `grafana`
  (Loki, Prometheus y Grafana) y promtail, e imprime el enlace al dashboard. Si falla,
  avisa y sigue: la observabilidad no bloquea el comando. No se hace para `ayuda` ni
  para el menú vacío.
- **promtail.** Se monta `DATA_DIR\logs` de solo lectura en `/var/log/basketball`. Nuevo
  job `basket` en `promtail.yml` para `/var/log/basketball/basket/*.log`, con las
  etiquetas `job=basket`, `comando` y `ejecucion` (sacadas del nombre del fichero).
  `asegurar.py` arranca también `basketball-promtail` y lo recrea si le falta el
  montaje; `Start-BasketballLocal.ps1` lo crea con el montaje.
- **Dashboard** `basket-logs` (datasource `loki-local`): variables `comando` y
  `ejecucion`, panel de logs en vivo, líneas por minuto y errores (`FALLO`, `ERROR`,
  `FAILED`, `NO ESTA EN MONGO`). `asegurar.py` lo importa con los demás.

## Backlog

- [x] 1. Este plan.
- [x] 2. `basket.py`: salida duplicada a `DATA_DIR\logs\basket\<comando>_<ts>.log`.
- [x] 3. `promtail.yml`: job `basket` con sus etiquetas.
- [x] 4. promtail con el montaje de `DATA_DIR\logs`, en `asegurar.py` y en `Start-BasketballLocal.ps1`.
- [x] 5. `basket.py`: asegura Grafana y promtail al inicio e imprime el enlace.
- [x] 6. Dashboard `basket-logs-dashboard.json`, importado por `asegurar.py`.
- [x] 7. Tests y gate `verificar.py` en verde. Tests: 42 OK (3 nuevos, `BasketLogsTests`). Gate: ROJO por web, API y Mongo parados (ajeno a este cambio); repetido con el runtime levantado: VERDE.
- [x] 7b. `resultados_ayer.py` asegura también `runtime` (Mongo, projector, API y web): la ejecución del 17/11 cargó en Postgres pero falló al consultar Mongo, que estaba parado.
- [x] 7c. Loki (192 MB) y promtail (96 MB) se quedaban sin memoria al leer también los logs de basket: Loki no contestaba (`context deadline exceeded`) y el dashboard se cortaba. Subidos a 768 MB y 256 MB en `Start-BasketballLocal.ps1`, `asegurar.py` y en caliente con `docker update`. Comprobado: 53 de 56 líneas en Loki al momento, sin errores de envío del job basket.
- [x] 8. Prueba real con la skill `/resultados-ayer` (pedido por el usuario): al lanzarla arrancan Grafana, Loki y promtail, y sus líneas se ven en el dashboard mientras corre. Visto el 17/11 10:01 en `basket-logs` (ejecución `resultados-ayer_20261117_095959`). Arreglado de paso: `Log:` y `Logs en vivo:` no salían por buffer (`flush=True`). Ejecución completa `resultados-ayer_20261117_101025`: código 0, 8 de 8 en Mongo, enlace `Logs en vivo:` impreso y salida visible en vivo en el dashboard.
- [x] 9. Evidencia en `docs\VERIFICACION-SDD.md`, `docs\SDD.md` (logs) y commit + push.
- [x] 10. Abrir por defecto el dashboard de logs (pedido el 17/11): `basket.py` abre el enlace `Logs en vivo:` en el navegador al lanzar cada comando; no lo abre en las tareas programadas (`ciclo-diario`, `inicio-automatico`) ni con `BASKET_NO_ABRIR_GRAFANA=1`. Tests: 61 OK (2 nuevos en `BasketLogsTests`). Gate VERDE el 17/11.
