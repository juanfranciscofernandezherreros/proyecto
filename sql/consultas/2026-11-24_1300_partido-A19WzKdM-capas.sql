-- =============================================================================
-- PARTIDO A19WzKdM: QUÉ HAY EN CADA TABLA DE POSTGRES
-- =============================================================================
-- Fecha:     2026-11-24 13:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1300_partido-A19WzKdM-capas.sql
--
-- PARA QUÉ SIRVE   El usuario quiere todo el flujo (resumen, estadísticas de equipo y
--                  jugadores, jugada a jugada, H2H y cuotas) para A19WzKdM. Esta
--                  consulta dice qué datasets tiene ya cargados y cuáles faltan.
-- CUÁNDO USARLA    Antes y después de reextraer el partido.
-- CÓMO LEER EL RESULTADO  Paso 1: fixture y resultado. Paso 2: filas por dataset (0 = falta).
-- QUÉ HACER DESPUÉS       basket reextraer --dataset todo y --dataset h2h-cuotas A19WzKdM.
-- RESULTADO EL 2026-11-24 (se completa tras ejecutarla)
-- =============================================================================

-- PASO 1 · Identidad del partido.
SELECT 'fixture' AS origen, country, competition, event_datetime, home_team, away_team, NULL::int AS home_score, NULL::int AS away_score
FROM fixtures.fixtures WHERE match_id = 'A19WzKdM'
UNION ALL
SELECT 'result', country, competition, event_datetime, home_team, away_team, home_score, away_score
FROM results.results WHERE match_id = 'A19WzKdM';

-- PASO 2 · Filas por dataset.
SELECT 'match_summary' AS dataset, count(*) FROM match_summary.match_summary WHERE match_id = 'A19WzKdM'
UNION ALL SELECT 'team_stats', count(*) FROM team_stats.team_stats WHERE match_id = 'A19WzKdM'
UNION ALL SELECT 'stats_player', count(*) FROM stats_player.stats_player WHERE match_id = 'A19WzKdM'
UNION ALL SELECT 'point_by_point', count(*) FROM point_by_point.point_by_point_event WHERE match_id = 'A19WzKdM'
UNION ALL SELECT 'h2h', count(*) FROM h2h.h2h WHERE match_id = 'A19WzKdM'
UNION ALL SELECT 'odds', count(*) FROM odds.odds WHERE match_id = 'A19WzKdM';
