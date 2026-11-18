-- =============================================================================
-- CONTADOR DE PARTIDOS DE AYER (panel «Ayer» del dashboard de pendientes)
-- =============================================================================
-- Fecha:     2026-11-18 09:50
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-18_0950_contador-partidos-ayer.sql
--
-- PARA QUÉ SIRVE   Contar los partidos de ayer (fecha en Europe/Madrid) que hay en
--                  fixtures, cuántos tienen ya los 4 datasets y cuántos se están
--                  extrayendo ahora (filas RUNNING de pipeline_step de la última hora).
--                  Es el SQL del panel «Ayer» de fixtures-audit-live.
-- CUÁNDO USARLA    Mientras corre resultados-ayer / datos-ayer.
-- CÓMO LEER EL RESULTADO  ayer = total; completos = con resultado, resumen, jugada a
--                  jugada, equipo y jugadores; extrayendo = partidos de ayer en curso.
-- QUÉ HACER DESPUÉS       Si completos < ayer al terminar, basket csv-faltan.
-- RESULTADO EL 2026-11-18 (ver la respuesta de la sesión)
-- =============================================================================

-- Paso 1: contadores de ayer
WITH ayer AS (
    SELECT f.match_id FROM fixtures.fixtures f
    WHERE (f.event_datetime AT TIME ZONE 'Europe/Madrid')::date = (now() AT TIME ZONE 'Europe/Madrid')::date - 1
)
SELECT count(*) AS ayer,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = a.match_id)
                          AND EXISTS (SELECT 1 FROM match_summary.match_summary s WHERE s.match_id = a.match_id)
                          AND EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = a.match_id)
                          AND EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id = a.match_id)
                          AND EXISTS (SELECT 1 FROM stats_player.stats_player sp WHERE sp.match_id = a.match_id)) AS completos,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.pipeline_step ps
                                      WHERE ps.estado = 'RUNNING' AND ps.started_at > now() - interval '1 hour'
                                        AND ps.paso LIKE '% ' || a.match_id)) AS extrayendo
FROM ayer a;
