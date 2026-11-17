# Plan: jugadores con el mismo nombre abreviado en PLAYER_STATS

Pedido el 2026-11-17 tras el fallo de `basket pendientes` en `h81tlrkd`.

## Problema

En los Thunder (OKC) juegan Jalen y Jaylin Williams; Flashscore escribe los dos como
«Williams J.». El batch `stats-player` usa la clave `(match_id, name, team)`
(`uk_stats_player_match_player_team` + `ON CONFLICT`), así que las dos filas chocan:
Postgres responde `ON CONFLICT DO UPDATE command cannot affect row a second time` y
rechaza el lote entero. Las estadísticas de jugadores del partido no entran nunca
(32 intentos desde el 10/11). Afecta a 3 partidos: `h81tlrkd`, `l40Wzzzi`, `zFyE2s4k`.

Además, ni `batch_launch_request.error` ni el launcher guardan el motivo: la salida del
batch va a la consola oculta del launcher (`inheritIO`).

## Solución

`MATCH_DETAILS` ya trae el enlace de cada jugador en la vista `MATCH / PLAYER STATS`
(`record_type=link`, `label` = nombre abreviado, p. ej.
`/player/williams-jalen/4G5tbqUi/`). Su último segmento es un id estable de Flashscore.

## Backlog

- [ ] 1. Scraper (`python-pyppeter`): columna nueva `player_url` al final de
  `PLAYER_STATS_FIELDS`. `player_rows` empareja cada fila con el enlace de su `label`
  en orden de aparición (dos «Williams J.» → primer y segundo enlace). La cabecera
  visible se sigue buscando con las 23 columnas de Flashscore. Test con el caso OKC.
- [ ] 2. Batch `stats-player` (`csv-extra-batch`): `ResultRow` acepta 24 columnas
  (CSV antiguos) o 25 (con `player_url`) y saca `player_id` del enlace. Migración V2:
  columnas `player_id` y `player_key` (generada: `player_id` o, si falta, `name`),
  índice único `(match_id, team, player_key)` en lugar del de `(match_id, name, team)`.
  El writer usa ese `ON CONFLICT` y, si el CSV trae ids, borra antes las filas antiguas
  sin id de ese partido (si no, quedarían duplicadas). Tests del parser y del writer.
- [ ] 3. Launcher (`csv-extra-batch`): la salida del batch va a
  `REPORT_DIR\batch-logs\<request_id>.log` y, si falla, `batch_launch_request.error`
  guarda las últimas líneas útiles (`Caused by` / `ERROR`). Test del recorte.
- [ ] 4. Recompilar los JAR y reiniciar el launcher; `basket reextraer` de los 3 partidos
  de OKC; comprobar en Postgres (dos «Williams J.» con distinto `player_id`) y en Mongo.
- [ ] 5. Tests, `basket verificar` en VERDE, evidencia en `docs/VERIFICACION-SDD.md`,
  commit + push en cada submódulo y en el repo principal.

Fuera de alcance: las páginas de jugador de la web/API siguen identificando por nombre;
dos jugadores con el mismo nombre abreviado en un partido se ven como dos filas en la
ficha, pero comparten página de jugador.
