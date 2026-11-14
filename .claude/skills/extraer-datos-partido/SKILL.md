---
name: extraer-datos-partido
description: Extrae e importa a PostgreSQL el detalle de los partidos de una liga — jugada a jugada (point-by-point), estadísticas de equipo y estadísticas de jugadores — con el scraper de Flashscore. Usar cuando el usuario pida las estadísticas, el play-by-play, los datos de jugadores o "el resto de CSV" de una liga, o cuando un partido tenga marcador pero le falte el detalle.
---

# Extraer el detalle de los partidos

Requiere que los marcadores ya estén cargados: si la liga va atrasada en
`results.results`, ejecutar antes la skill `extraer-resultados`.

## Qué dataset va a qué tabla

| Dataset | Tabla |
|---|---|
| Jugada a jugada (`POINT_BY_POINT`) | `point_by_point.point_by_point_event` |
| Estadísticas de equipo (`TEAM_STATS`) | `team_stats.team_stats` |
| Estadísticas de jugadores (`PLAYER_STATS`) | `stats_player.stats_player` |
| Resumen de marcador (`MATCH_SUMMARY`) | `match_summary.match_summary` |

## 1. Extraer e importar los tres datasets de una liga

Desde bash, con ruta completa y en segundo plano (tarda varios minutos por
partido):

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\LIGAS_ORQUESTAR.bat EUROLIGA datos 10"
```

- Argumentos: `<LIGA> datos <limite>`. La liga es un `code` de `LIGAS_BASKET.json`
  (`EUROLIGA`, `ACB`, `NBA`... o `ALL`). El límite es el número de partidos, entre
  1 y 100; por defecto 10.
- Para cada dataset extrae y, si la extracción va bien, importa. Un fallo en un
  dataset no detiene los demás: queda anotado en el resumen final.
- Si algo falla, el orquestador deja en
  `C:\data\basketball\reports\orchestrator\ligas-orquestar-pendientes-<fecha>.csv`
  los partidos a recuperar, listo para `MATCHIDS_PENDIENTES.bat <csv>`.

Alternativa que además completa los pendientes al acabar:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\EXTRAER_CSV_COMPLETO.bat EUROLIGA 10"
```

No usar `DATOS_EUROLIGA.bat` ni `ULTIMOS_PARTIDOS.bat` desde aquí: el primero abre
un menú interactivo (`choice`) y el segundo termina en `pause`, y ambos se quedan
colgados sin teclado.

## 2. Un solo dataset

Cada uno tiene su par extraer / importar, con `<pais> <competicion> [limite]`:

```bash
cmd //c "C:\Develop\basketball\scripts\extraer\EXTRAER_POINT_BY_POINT.bat europe euroleague 10"
```

```bash
cmd //c "C:\Develop\basketball\scripts\importar\IMPORTAR_POINT_BY_POINT.bat europe euroleague"
```

Lo mismo con `TEAM_STATS` y `PLAYER_STATS`. Antes hay que asegurar los servicios:

```bash
cmd //c "C:\Develop\basketball\scripts\arranque\ASEGURAR.bat antibloqueo postgres launcher navegador"
```

## 3. Verificar

Cargas del launcher (deben salir `COMPLETED` y `exit_code = 0`):

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT batch_type, status, exit_code, created_at FROM public.batch_launch_request ORDER BY created_at DESC LIMIT 15;"
```

Cobertura por partido de la liga (sustituir `<competicion>`):

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT r.match_id, r.home_team, r.away_team, EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = r.match_id) AS pbp, EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id = r.match_id) AS equipo, EXISTS (SELECT 1 FROM stats_player.stats_player s WHERE s.match_id = r.match_id) AS jugadores FROM results.results r WHERE r.competition = '<competicion>' ORDER BY r.event_datetime DESC NULLS LAST LIMIT 15;"
```

Si la consulta falla por el nombre de una columna, mirar la tabla con `\d` antes de
corregirla; no asumir el esquema.

Un `false` no siempre es un fallo: Flashscore no publica todos los datasets de todos
los partidos. Los que se han intentado y no existen en la fuente quedan en
`fixtures_processing_audit.dataset_unavailable` (skill `procesar-pendientes`).

## Notas

- Los CSV crudos van a `C:\data\basketball\competitions\<pais>\<competicion>\<matchId>\`.
  No copiarlos a mano a `C:\data\basketball-ready\current`: deben consolidarse antes.
- Las consultas ejecutadas se guardan en `sql\consultas\` (regla `consultas-sql`).
