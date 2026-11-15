-- =============================================================================
-- TEAM_STATS DESCUADRADAS: LOS PARTIDOS AFECTADOS NO TIENEN COPIA BUENA
-- =============================================================================
-- Fecha:     2026-11-15 15:10
-- Tipo:      LECTURA (no modifica nada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-15_1510_team-stats-descuadradas-sin-copia-buena.sql
--
-- PARA QUÉ SIRVE
--   El control 15 de la auditoría (2026-11-15_1445_auditoria-datos.sql) dio 7480 filas
--   de team_stats cuya métrica es un valor ("50.0%", "(2/2)"). Antes de borrarlas se
--   comprueba si esos partidos tienen ya las métricas de tiro correctas (como pasaba en
--   2026-11-04_1135_team-stats-duplicadas-tras-reextraer.sql) o si las descuadradas son
--   lo único que hay.
--
-- CUÁNDO USARLA
--   Antes de borrar filas descuadradas de team_stats, para saber si basta con borrar o
--   hay que reextraer TEAM_STATS de esos partidos.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  con_field_goal = partidos afectados que YA tienen la fila buena
--           "Field goal %". Si es igual a `partidos`, borrar es seguro y suficiente.
--           Si es 0, las filas descuadradas son los únicos datos de tiro del partido.
--   PASO 2  muestra de un partido afectado: se ve la etiqueta desplazada a home_value
--           o away_value.
--   PASO 3  cuándo se cargaron las filas descuadradas.
--   PASO 4  cuándo se cargaron partidos con la fila buena "Field goal %".
--
-- QUÉ HACER DESPUÉS
--   Si con_field_goal = 0: reextraer TEAM_STATS de esos partidos (skill
--   extraer-datos-partido) y después borrar las filas descuadradas. Borrar solo deja
--   los partidos sin porcentajes de tiro, y la auditoría de pendientes no los vuelve a
--   pedir porque el partido sigue teniendo filas en team_stats.
--
-- RESULTADO EL 2026-11-15
--   PASO 1: 262 partidos, con_field_goal = 0, con_rebotes = 253. Ninguno tiene copia
--           buena de los porcentajes de tiro.
--   PASO 2: en la muestra, además de las filas con métrica-valor, la fila
--           "2-point field goal %" trae valores "(8/16)" en las dos columnas: también
--           está descuadrada aunque su etiqueta parezca válida (el control 15 no la cuenta).
--   PASO 3: cargadas entre el 2026-10-21 y el 2026-11-04 (261 partidos) y 1 partido el
--           2026-11-10.
--   PASO 4: las filas buenas empiezan el 2026-11-04 (scraper corregido); 470 partidos.
--   NO se ha borrado nada.
-- =============================================================================

-- PASO 1 · Partidos con filas descuadradas y cuántos tienen ya las métricas buenas.
WITH malos AS (SELECT DISTINCT match_id FROM team_stats.team_stats WHERE metric ~ '^\(?[0-9]+(\.[0-9]+)?[%/]')
SELECT count(*) AS partidos,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id=m.match_id AND t.metric='Field goal %')) AS con_field_goal,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id=m.match_id AND t.metric='Total rebounds')) AS con_rebotes
FROM malos m;

-- PASO 2 · Muestra: el partido afectado más reciente, fila a fila.
SELECT period, category, metric, home_value, away_value, created_at::date, updated_at::date
FROM team_stats.team_stats
WHERE match_id = (SELECT match_id FROM team_stats.team_stats WHERE metric ~ '^\(?[0-9]+(\.[0-9]+)?[%/]' ORDER BY updated_at DESC LIMIT 1)
ORDER BY period, id LIMIT 30;

-- PASO 3 · Cuándo se cargaron las filas descuadradas.
SELECT created_at::date AS creada, count(DISTINCT match_id) AS partidos, count(*) AS filas
FROM team_stats.team_stats WHERE metric ~ '^\(?[0-9]+(\.[0-9]+)?[%/]' GROUP BY 1 ORDER BY 1;

-- PASO 4 · Cuándo se cargaron partidos con la fila buena "Field goal %".
SELECT created_at::date AS creada, count(DISTINCT match_id) AS partidos_bien
FROM team_stats.team_stats WHERE metric = 'Field goal %' GROUP BY 1 ORDER BY 1;
