---
name: diagnosticar-partido
description: Averigua por qué un partido o un conjunto de partidos no aparece en la web del proyecto Basketball, aparece incompleto o con datos erróneos, siguiéndolo por cada etapa — fixtures y results en PostgreSQL, datasets de detalle, MongoDB y la API. Usar cuando el usuario diga que un partido no sale, que falta el marcador, la hora o las estadísticas, que la web no refleja lo cargado, o pregunte dónde se ha quedado un partido.
---

# Diagnosticar un partido que no sale bien en la web

El dato recorre este camino, y el fallo está en la primera etapa donde falta:

CSV → `csv-batch-launcher` → **Postgres** → `basketball-match-projector` →
**MongoDB** → `basketball-match-api` → **web**

Seguir las etapas en orden y parar en la primera que falle. No saltar a Mongo o a
la API sin haber confirmado Postgres.

## 0. Identificar el partido

Si el usuario da equipos y fecha en vez de `match_id`:

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT match_id, country, competition, event_datetime, home_team, away_team FROM fixtures.fixtures WHERE home_team ILIKE '%<equipo>%' OR away_team ILIKE '%<equipo>%' ORDER BY event_datetime DESC LIMIT 20;"
```

## 1. Postgres: calendario y resultado

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT 'fixture' AS origen, match_id, country, competition, event_time::text, event_datetime, home_team, away_team, NULL::text AS marcador FROM fixtures.fixtures WHERE match_id = '<MATCH_ID>' UNION ALL SELECT 'result', match_id, country, competition, event_time::text, event_datetime, home_team, away_team, home_score || '-' || away_score FROM results.results WHERE match_id = '<MATCH_ID>';"
```

Qué mirar:

- **Sin fila `result`**: el marcador no se ha extraído → skill `extraer-resultados`.
- **`result` con `event_time` vacío**: la API filtra los finalizados por
  `result.eventTime` y oculta el partido. Es el caso más frecuente. Rescate en
  `sql\consultas\2026-11-07_1830_results-sin-event-time-no-salen-en-web.sql`.
- **`country` o `competition` vacíos**, o con un slug no canónico (`acb`,
  `super-league` en vez de `liga-endesa`, `winner-league`): el partido cae fuera de
  los filtros de la web. Ver `sql\consultas\2026-11-08_0000_normalizar-competiciones-fixtures.sql`.
- **`fixture` y `result` con competición distinta**: no se unen en la ficha.
- **`event_datetime` en un año equivocado**: ver
  `sql\consultas\2026-11-04_0900_results-fecha-futura-ano-mal.sql`.

## 2. Postgres: datasets de detalle

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT (SELECT count(*) FROM match_summary.match_summary WHERE match_id = '<MATCH_ID>') AS resumen, (SELECT count(*) FROM point_by_point.point_by_point_event WHERE match_id = '<MATCH_ID>') AS jugadas, (SELECT count(*) FROM team_stats.team_stats WHERE match_id = '<MATCH_ID>') AS stats_equipo, (SELECT count(*) FROM stats_player.stats_player WHERE match_id = '<MATCH_ID>') AS stats_jugadores;"
```

Un cero no siempre es un fallo: comprobar si la fuente no lo publica.

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT dataset, estado, reason, attempts, last_seen, source_url FROM fixtures_processing_audit.dataset_unavailable WHERE match_id = '<MATCH_ID>';"
```

Si falta y no está registrado como no disponible → skill `extraer-datos-partido`
o `procesar-pendientes`.

## 3. Cargas del launcher

Si los CSV existen en `C:\data\basketball\competitions\<pais>\<competicion>\<MATCH_ID>\`
pero no llegaron a Postgres:

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT batch_type, status, exit_code, created_at FROM public.batch_launch_request ORDER BY created_at DESC LIMIT 20;"
```

Filas con `status` distinto de `COMPLETED` o `exit_code` distinto de 0 señalan la
carga que falló. Cuidado con las cargas `COMPLETED` que no insertaron nada:
`sql\consultas\2026-11-03_1745_imports-completed-sin-datos.sql`.

## 4. MongoDB (read model)

Requiere el stack arrancado (skill `arrancar-todo`). El projector reproyecta cada
~60 s, así que tras una carga hay que esperar un minuto antes de mirar.

```bash
docker exec -i local-validation-mongo-1 mongosh --quiet basketball --eval "printjson(db.matches.findOne({matchId:'<MATCH_ID>'}, {matchId:1, availableSections:1, 'fixture.competition':1, 'fixture.eventTime':1, 'result.eventTime':1, 'result.homeScore':1, 'result.awayScore':1}))"
```

- **`null`**: el projector no lo ha proyectado. Mirar sus logs:
  `docker logs --tail 100 local-validation-basketball-match-projector-1`
  (confirmar el nombre con `docker ps`).
- **`fixture: null` con `availableSections` que incluye `fixture`**: documento
  obsoleto; se arregla subiendo `PROJECTION_VERSION` en `MatchProjectionService`
  (verificación D3 en `docs\VERIFICACION-SDD.md`).
- **Postgres correcto y Mongo desfasado**: esperar un ciclo o reiniciar el projector.

## 5. API y web

```bash
curl -s http://localhost:8082/api/v1/matches/<MATCH_ID>
```

```bash
curl -s http://localhost:8082/api/v1/matches/<MATCH_ID>/processing
```

- La ficha responde pero el partido no sale en el listado: lo descarta un filtro
  (`status=finished` exige `result.eventTime`; país y competición deben coincidir
  con `GET /api/v1/matches/filters`).
- La API lo devuelve bien y la web no: caché del navegador o nginx
  (`basketball-match-web`, http://localhost:8083).

## Varios partidos a la vez

Para medir huecos en bloque en lugar de partido a partido:
`sql\consultas\2026-11-07_1915_auditoria-integridad-read-model.sql`. Y para el
estado general, `1_EJECUTAR\VERIFICAR.bat` (skill `estado-del-sistema`).

## Al terminar

Decir en qué etapa se rompe, con el dato que lo demuestra, y qué arreglo
corresponde. No aplicar escrituras en la base de datos sin guardar antes la
consulta en `sql\consultas\` marcada como `ESCRITURA` (regla `consultas-sql`).
