-- =============================================================================
-- PARTIDOS DE HOY QUE EL CONTEO DE PENDIENTES DEJA FUERA
-- =============================================================================
-- Fecha:     2026-11-18 09:35
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-18_0935_partidos-hoy-fuera-del-conteo.sql
--
-- PARA QUÉ SIRVE   El dashboard de pendientes solo mostraba 3 de Euroliga mientras se
--                  extraían partidos NBA. La auditoría excluye los partidos con fecha
--                  de hoy (hora de Madrid) sin fila en results.results. Esta consulta
--                  lista los fixtures de hoy ya empezados y si tienen resultado.
-- CUÁNDO USARLA    Si el conteo de pendientes parece corto a primera hora.
-- CÓMO LEER EL RESULTADO  con_resultado = false y empezado hace horas => la
--                  auditoría lo deja fuera aunque ya se jugó.
-- QUÉ HACER DESPUÉS       Revisar la regla de elegibilidad de fixtures-processing-audit.
-- RESULTADO EL 2026-11-18 (ver la respuesta de la sesión)
-- =============================================================================

-- Paso 1: fixtures de hoy (Madrid) ya empezados, con o sin resultado
SELECT f.country, f.competition, f.match_id, f.event_datetime,
       EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id) AS con_resultado
FROM fixtures.fixtures f
WHERE (f.event_datetime AT TIME ZONE 'Europe/Madrid')::date = (now() AT TIME ZONE 'Europe/Madrid')::date
  AND f.event_datetime < now()
ORDER BY f.event_datetime;

-- Paso 2: ¿el partido NBA que datos-ayer está reextrayendo (KfR8jPS7) ya estaba completo?
SELECT m.match_id,
       EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = m.match_id) AS results,
       EXISTS (SELECT 1 FROM match_summary.match_summary s WHERE s.match_id = m.match_id) AS summary,
       EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = m.match_id) AS pbp,
       EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id = m.match_id) AS team,
       EXISTS (SELECT 1 FROM stats_player.stats_player sp WHERE sp.match_id = m.match_id) AS player
FROM (VALUES ('KfR8jPS7'), ('OjKNaT5L'), ('Sn91hobe'), ('t46eg5MP')) AS m(match_id);
