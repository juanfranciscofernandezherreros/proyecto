# Análisis inverso completo: web → Python scraper

Fecha: 2026-10-26  
Alcance: aplicación web local, API, proyección, PostgreSQL, batches CSV y `python-pyppeter`.

## Diagrama de trazabilidad

```text
USUARIO / NAVEGADOR
  │
  │  Web React: basketball-match-web
  │  GET /api/v1/matches, /filters, /{matchId}, /stats, /players,
  │      /point-by-point, /processing y /performances
  ▼
API REST: basketball-match-api (puerto local 8082 → contenedor 8080)
  │  Lee el modelo de consulta; no lee CSV ni PostgreSQL de ingesta directamente.
  ▼
MONGODB: basketball
  │  Modelo de lectura materializado por partido.
  │  El detalle expone result.homePeriods y result.awayPeriods.
  ▼
PROJECTOR: basketball-match-projector
  │  Reconcilia las tablas de PostgreSQL y materializa el documento Mongo.
  ▼
POSTGRESQL: basketball (localhost:55432)
  ├─ results.results             ← resultado final + parciales Q1..Q5
  ├─ fixtures.fixtures           ← calendario
  ├─ match_summary.match_summary ← equipos + resultado final, sin parciales
  ├─ team_stats.team_stats       ← estadísticas de equipo
  ├─ stats_player.stats_player   ← estadísticas de jugadores
  └─ point_by_point.*            ← jugada a jugada
  ▲
  │  CSV batch launcher (host, Java 21, puerto 8088)
  │  Orden obligatorio: RESULTS → FIXTURES → SCORE_SUMMARY →
  │                     STATS_ALL_PERIODS → PLAYER_STATS → POINT_BY_POINT
  │
CSV CONSOLIDADO: C:\data\basketball-ready\current
  │  Consolidado atómico desde artefactos por partido.
  ▼
PYTHON: python-pyppeter
  ├─ consolidate_csv.py
  ├─ extract_competition_all.py
  ├─ extract_flashscore_matches.py
  └─ extract_flashscore_match_bundle.py
  ▼
FLASHSCORE
  ├─ listado de resultados: final, equipos, hora, URL y matchId
  └─ detalle de cada partido: parciales, resumen, jugadores, stats, PBP, H2H y cuotas
```

## 1. Web

`basketball-match-web/src/api/matchesApi.ts` usa `VITE_API_URL` y, si no existe,
una URL relativa. Hace `fetch` a la API y mantiene una caché en memoria de 15 s.

| Vista/dato | Endpoint |
|---|---|
| Lista de partidos | `GET /api/v1/matches` |
| Filtros | `GET /api/v1/matches/filters` |
| Detalle | `GET /api/v1/matches/{matchId}` |
| Estadísticas | `GET /api/v1/matches/{matchId}/stats` |
| Jugadores | `GET /api/v1/matches/{matchId}/players` |
| Jugada a jugada | `GET /api/v1/matches/{matchId}/point-by-point` |
| Estado de proyección | `GET /api/v1/matches/{matchId}/processing` |

Los parciales que pinta el detalle provienen de `result.homePeriods` y
`result.awayPeriods`; no de `SCORE_SUMMARY`.

## 2. API, Mongo y projector

La API publica un modelo de lectura. La cabecera HTTP de las respuestas API
permite caché de 15 s (`max-age=15`, con `stale-while-revalidate=60`).

El projector convierte las tablas de PostgreSQL en documentos Mongo. Por ello,
un CSV correctamente insertado no es todavía una garantía visual: hay que
esperar la reconciliación y verificar el endpoint de detalle.

## 3. PostgreSQL: dueño de cada dato

| Tabla | Fuente CSV | Responsabilidad |
|---|---|---|
| `results.results` | `RESULTS_*` | marcador final y `home_score1..5` / `away_score1..5` |
| `fixtures.fixtures` | `FIXTURES_*` | fecha/calendario |
| `match_summary.match_summary` | `SCORE_SUMMARY_*` | equipos, URLs de equipos y total final; **sin parciales** |
| `team_stats.team_stats` | `STATS_ALL_PERIODS_*` | métricas por periodo |
| `stats_player.stats_player` | `PLAYER_STATS_*` | estadísticas individuales |
| `point_by_point.point_by_point_event` | `POINT_BY_POINT_*` | secuencia de acciones |

### Invariante de resultados

Para un partido finalizado, `results.results` debe cumplir:

```text
home_score = home_score1 + home_score2 + home_score3 + home_score4 + COALESCE(home_score5, 0)
away_score = away_score1 + away_score2 + away_score3 + away_score4 + COALESCE(away_score5, 0)
Q1..Q4: presentes y no negativos para ambos equipos
Q5: presente para ambos equipos o ausente para ambos
```

La jornada de Euroliga inspeccionada cumple estas reglas en los 15 partidos.

## 4. Batches

El launcher clasifica el archivo por nombre y lanza el batch correspondiente.
`RESULTS` se procesa primero porque crea/actualiza el registro que consumen los
restantes flujos.

`csv-results-batch` valida la cabecera, convierte puntuaciones a enteros y hace
UPSERT por `match_id`. La cabecera canónica nueva utiliza las mismas etiquetas
que PostgreSQL para los parciales:

```text
home_score1,home_score2,home_score3,home_score4,home_score5
away_score1,away_score2,away_score3,away_score4,away_score5
```

La lectura mantiene compatibilidad temporal con CSV históricos camelCase.

## 5. Consolidación

`consolidate_csv.py` publica de manera atómica en
`C:\data\basketball-ready\current`. Los CSV crudos nunca se modifican.

### Incidente corregido: SCORE_SUMMARY

El contrato de `SCORE_SUMMARY` es:

```text
match_id,side,team,team_url,total
```

Cada partido requiere exactamente dos filas consecutivas:

```text
<match_id>,home,<equipo local>,<url>,<total>
<match_id>,away,<equipo visitante>,<url>,<total>
```

El defecto era una clave de deduplicación basada en `homeName` y `awayName`,
campos que no existen en ese CSV. Al ser ambos vacíos, se eliminaba la fila
`away`. El batch recibía bloques de `home` sin su pareja y abortaba.

Corrección aplicada:

```text
clave de deduplicación: (match_id, side)
orden de publicación:  match_id, home, away
validación:            exactamente {home, away} por match_id
```

## 6. Python scraper

### `extract_flashscore_matches.py`

Obtiene el listado de resultados de una competición. El listado aporta el
marcador final; `enrich_result_periods()` visita el detalle de cada encuentro
para obtener Q1..Q5. Publica `RESULTS_*` con los campos canónicos.

### `extract_flashscore_match_bundle.py`

Para cada `match_id` crea:

```text
MATCH_DETAILS, SCORE_SUMMARY, STATS_ALL_PERIODS, PLAYER_STATS,
POINT_BY_POINT, H2H, ODDS_HOME_AWAY, ODDS_1X2,
ODDS_OVER_UNDER, ODDS_ASIAN_HANDICAP
```

`SCORE_SUMMARY` se deriva de `MATCH_DETAILS` usando eventos `score_team` y
`score_total`. No es fuente de parciales.

### `extract_competition_all.py`

Orquesta fixtures, resultados y bundles por partido. Publica una barrera de
validación de `RESULTS` antes de lanzar los workers de detalle y mantiene
inventario/manifest de cada ejecución.

## 7. Puntos de control operativos

```text
1. Validar header y tipos de RESULTS antes de consolidar.
2. Verificar invariantes de parciales antes del UPSERT.
3. Consolidar sin tocar los CSV crudos.
4. Validar pares home/away de SCORE_SUMMARY antes de publicar current.
5. Ingerir en orden fijo.
6. Esperar projector.
7. Confirmar API: result.homePeriods y result.awayPeriods.
```

## 8. Diagnóstico rápido por síntoma

| Síntoma web | Verificación inversa |
|---|---|
| Sin parciales | API → Mongo → `results.results` → `RESULTS_*` |
| Equipos/resultado final ausentes en resumen | API → Mongo → `match_summary` → `SCORE_SUMMARY_*` |
| PBP vacío | API → Mongo → `point_by_point` → `POINT_BY_POINT_*` |
| Datos correctos en PostgreSQL, web antigua | comprobar projector y caché de API/web |
| Batch de summary falla | comprobar dos filas `home`/`away` por `match_id` en el CSV consolidado |

