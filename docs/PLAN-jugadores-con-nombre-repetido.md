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

- [x] 1. Scraper (`python-pyppeter`): columna nueva `player_url` al final de
  `PLAYER_STATS_FIELDS`. `player_rows` empareja cada fila con el enlace de su `label`
  en orden de aparición (dos «Williams J.» → primer y segundo enlace). La cabecera
  visible se sigue buscando con las 23 columnas de Flashscore. Test con el caso OKC.
- [x] 2. Batch `stats-player` (`csv-extra-batch`): `ResultRow` acepta 24 columnas
  (CSV antiguos) o 25 (con `player_url`) y saca `player_id` del enlace. Migración V2:
  columnas `player_id` y `player_key` (generada: `player_id` o, si falta, `name`),
  índice único `(match_id, team, player_key)` en lugar del de `(match_id, name, team)`.
  El writer usa ese `ON CONFLICT` y, si el CSV trae ids, borra antes las filas antiguas
  sin id de ese partido (si no, quedarían duplicadas). Tests del parser y del writer.
- [x] 3. Launcher (`csv-extra-batch`): la salida del batch va a
  `REPORT_DIR\batch-logs\<request_id>.log` y, si falla, `batch_launch_request.error`
  guarda las últimas líneas útiles (`Caused by` / `ERROR`). Test del recorte.
- [x] 4. Recompilar los JAR y reiniciar el launcher; `basket reextraer` de los 3 partidos
  de OKC; comprobar en Postgres (dos «Williams J.» con distinto `player_id`) y en Mongo.
- [x] 5. Tests, `basket verificar` en VERDE, evidencia en `docs/VERIFICACION-SDD.md`,
  commit + push en cada submódulo y en el repo principal.

Fuera de alcance: las páginas de jugador de la web/API siguen identificando por nombre;
dos jugadores con el mismo nombre abreviado en un partido se ven como dos filas en la
ficha, pero comparten página de jugador.

## Resultado (2026-11-17)

- Paso 1: `python-pyppeter` 9fc61b8; 347 tests OK.
- Paso 2: `csv-extra-batch` e1a74c4; además `CsvInput` validaba la cabecera aparte y solo
  admitía 24 columnas (el primer reintento falló por eso). 5 tests OK. La migración V2 ya
  está aplicada en la BD.
- Paso 3: `csv-extra-batch` 5ffbcb7; 8 tests OK. **Código hecho, sin desplegar**: el JAR del
  launcher no se puede reemplazar mientras el launcher corre, y estaba atendiendo a
  `basket pendientes`. Falta `mvn package` en `launcher` y reiniciar el launcher al terminar.
  La carpeta de logs no es `REPORT_DIR\batch-logs` sino `batch-logs` junto a la carpeta
  vigilada (o `BATCH_LOG_DIR`).
- Paso 4: recarga sin navegador desde el `MATCH_DETAILS` ya descargado (que trae los enlaces).
  Postgres: 27, 22 y 26 jugadores, todos con `player_id`; dos «Williams J.» con id distinto
  en cada partido. Mongo y la API igual. En `l40Wzzzi` y `zFyE2s4k` faltaba un jugador
  desde noviembre.
- Paso 5: tests del repo 65 OK; `basket verificar` VERDE.
- Paso 3 desplegado el 17/11 a las 16:21, en el hueco entre dos partidos de `pendientes`.
  Compilar el launcher suelto (`mvn -pl launcher`) usa una copia vieja del módulo
  `pronostico` y no arranca (falta `ArticleGeneratorService`): hay que compilar con
  `mvn -pl launcher -am package` desde `csv-extra-batch`. Por la parada, dos partidos
  (`j33O51XI`, `I9eAT4PP`) no cargaron su POINT_BY_POINT; se cargaron a mano desde su CSV
  y sus estadísticas quedan para la siguiente pasada de pendientes.
