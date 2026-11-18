-- =============================================================================
-- DATOS-AYER: SOLO PARTIDOS DE AYER A LOS QUE LES FALTA ALGÚN DATASET
-- =============================================================================
-- Fecha:     2026-11-18 10:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-18_1000_datos-ayer-solo-incompletos.sql
--
-- PARA QUÉ SIRVE   Es la consulta que genera scripts\py\lanzadores\datos_ayer.py.
--                  Antes devolvía los 17 partidos de ayer y se reextraían los NBA ya
--                  completos antes de llegar a la Euroliga. Ahora solo devuelve los que
--                  les falta resultado, resumen, jugada a jugada o estadísticas
--                  (salvo los marcados como no disponibles en la fuente).
-- CUÁNDO USARLA    Para saber qué va a extraer basket datos-ayer.
-- CÓMO LEER EL RESULTADO  cada fila es un partido que se va a reextraer.
-- QUÉ HACER DESPUÉS       basket datos-ayer
-- RESULTADO EL 2026-11-18  3 filas: UkWOzxk1, ld4AV1UI, xGZWYFJD (Euroliga)
-- =============================================================================

-- Paso 1: partidos de ayer incompletos
SELECT f.match_id FROM fixtures.fixtures f WHERE (f.event_datetime AT TIME ZONE 'Europe/Madrid')::date = ((now() AT TIME ZONE 'Europe/Madrid')::date - 1) AND ((NOT EXISTS (SELECT 1 FROM results.results x WHERE x.match_id = f.match_id) AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u WHERE u.match_id = f.match_id AND u.dataset = 'MATCH_SUMMARY')) OR (NOT EXISTS (SELECT 1 FROM match_summary.match_summary x WHERE x.match_id = f.match_id) AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u WHERE u.match_id = f.match_id AND u.dataset = 'MATCH_SUMMARY')) OR (NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event x WHERE x.match_id = f.match_id) AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u WHERE u.match_id = f.match_id AND u.dataset = 'POINT_BY_POINT')) OR (NOT EXISTS (SELECT 1 FROM team_stats.team_stats x WHERE x.match_id = f.match_id) AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u WHERE u.match_id = f.match_id AND u.dataset = 'TEAM_STATS')) OR (NOT EXISTS (SELECT 1 FROM stats_player.stats_player x WHERE x.match_id = f.match_id) AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u WHERE u.match_id = f.match_id AND u.dataset = 'PLAYER_STATS'))) ORDER BY f.match_id;
