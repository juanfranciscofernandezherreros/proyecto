-- =============================================================================
-- ESQUEMA Y VALORES DE LAS TABLAS QUE USA LA AUDITORÍA DE DATOS
-- =============================================================================
-- Fecha:     2026-11-15 14:37
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-15_1437_esquema-tablas-auditoria.sql
--
-- PARA QUÉ SIRVE   Consultas intermedias usadas para escribir
--                  2026-11-15_1445_auditoria-datos.sql: columnas y tipos de las tablas
--                  auditadas, y los valores reales de dataset/estado y batch_type/status.
-- CUÁNDO USARLA    Si la auditoría falla por una columna que ya no existe, o al añadirle
--                  un control nuevo y hacer falta recordar nombres y tipos.
-- CÓMO LEER EL RESULTADO  PASO 1: una fila por tabla con "columna tipo". PASO 2 y 3:
--                  combinaciones existentes y cuántas filas tiene cada una.
-- QUÉ HACER DESPUÉS       Ajustar la consulta de auditoría si el esquema ha cambiado.
-- RESULTADO EL 2026-11-15  8 tablas. Ojo: results.event_time es varchar y
--                  fixtures.event_time es time. Datasets: MATCH_SUMMARY, PLAYER_STATS,
--                  POINT_BY_POINT, TEAM_STATS (estados NO_PUBLICADO y VACIO). Cargas:
--                  fixtures, match-summary, point-by-point, results, stats-player,
--                  team-stats (COMPLETED / FAILED). Métricas reales: 13 etiquetas
--                  (incluye "Technical fouls"); el resto son valores descuadrados.
-- =============================================================================

-- PASO 1 · Columnas y tipos de las tablas auditadas.
SELECT table_schema||'.'||table_name AS tabla,
       string_agg(column_name||' '||data_type, ', ' ORDER BY ordinal_position)
FROM information_schema.columns
WHERE table_schema||'.'||table_name IN (
  'fixtures.fixtures','results.results','team_stats.team_stats','stats_player.stats_player',
  'point_by_point.point_by_point_event','match_summary.match_summary',
  'fixtures_processing_audit.dataset_unavailable','public.batch_launch_request')
GROUP BY table_schema, table_name;

-- PASO 2 · Datasets registrados como no disponibles en la fuente, por estado.
SELECT dataset, estado, count(*)
FROM fixtures_processing_audit.dataset_unavailable
GROUP BY 1,2 ORDER BY 1,2;

-- PASO 3 · Cargas del launcher por tipo y estado.
SELECT batch_type, status, count(*)
FROM public.batch_launch_request
GROUP BY 1,2 ORDER BY 1,2;

-- PASO 4 · Métricas de team_stats que existen de verdad (para distinguir etiquetas
--   reales de valores descuadrados como "50.0%" o "(2/2)").
SELECT metric, count(*) AS filas, count(DISTINCT match_id) AS partidos
FROM team_stats.team_stats
GROUP BY metric ORDER BY filas DESC LIMIT 40;
