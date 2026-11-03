-- =============================================================================
-- PARTIDOS DE results QUE LA AUDITORÍA DE PENDIENTES NO VE
-- =============================================================================
-- Fecha:     2026-11-03 10:40
-- Tipo:      LECTURA (no modifica nada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1040_results-fuera-de-la-auditoria.sql
--
-- PARA QUÉ SIRVE
--   La auditoría de pendientes (módulo csv-extra-batch\fixtures-processing-audit, la que
--   alimenta Grafana y MATCHIDS_PENDIENTES) recorre SOLO la tabla fixtures.fixtures (el
--   calendario) y, para cada partido ya jugado, mira si faltan datasets: match_summary,
--   point_by_point, team_stats y stats_player. La tabla results solo se consulta para
--   saber si hay resultado.
--   Consecuencia: un partido que está en results.results pero NO en fixtures.fixtures no
--   aparece nunca en la auditoría (ni como pendiente ni como completo), y por tanto nadie
--   procesa sus estadísticas aunque le falten. Esta consulta cuenta esos partidos.
--
-- CUÁNDO USARLA
--   · Si el número de pendientes de Grafana parece bajo respecto a los partidos de results.
--   · Después de importar RESULTS de ligas o temporadas cuyo calendario no se ha importado.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  partidos de results con y sin fila en fixtures. "fuera_de_la_auditoria" son los
--           que la auditoría no ve.
--   PASO 2  de esos, por competición, cuántos tienen cada dataset. Las columnas sin_* son los
--           partidos a los que les falta ese dataset: serían pendientes si la auditoría los viera.
--   PASO 3  cuántos de ellos están completos y cuántos incompletos (pendientes ocultos).
--
-- QUÉ HACER DESPUÉS
--   · Importar el calendario (FIXTURES) de esas competiciones para que la auditoría los vea, o
--   · Cambiar la auditoría para que parta de results además de fixtures.
--   Ver la respuesta del 2026-11-03 sobre qué opción se eligió.
--
-- RESULTADO EL 2026-11-03
--   635 partidos en results: 183 también en fixtures y 452 fuera de la auditoría.
--   De esos 452: 80 completos y 372 incompletos (pendientes ocultos). Casi todos sin ningún
--   dataset (NBA 69, ACB 48, LNB 47, Lega A 43, BSL 43, LKL 36, GBL 33, Winner 22, KLS 12);
--   la Euroliga (56) está completa y la BBL parcialmente.
-- =============================================================================


-- PASO 1 · Partidos de results según estén o no en fixtures.
SELECT count(*)                                         AS total_results,
       count(*) FILTER (WHERE f.match_id IS NOT NULL)   AS tambien_en_fixtures,
       count(*) FILTER (WHERE f.match_id IS NULL)       AS fuera_de_la_auditoria
FROM results.results r
LEFT JOIN fixtures.fixtures f ON f.match_id = r.match_id;


-- PASO 2 · Los que no están en fixtures, por competición, con los datasets que les faltan.
SELECT r.country || '/' || r.competition AS competicion,
       count(*) AS partidos,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM match_summary.match_summary s WHERE s.match_id = r.match_id))           AS sin_match_summary,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = r.match_id))   AS sin_point_by_point,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id = r.match_id))                 AS sin_team_stats,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM stats_player.stats_player sp WHERE sp.match_id = r.match_id))           AS sin_player_stats
FROM results.results r
WHERE NOT EXISTS (SELECT 1 FROM fixtures.fixtures f WHERE f.match_id = r.match_id)
GROUP BY 1
ORDER BY 2 DESC;


-- PASO 3 · De los que no están en fixtures, cuántos están completos y cuántos incompletos.
SELECT count(*) FILTER (WHERE faltan = 0) AS completos,
       count(*) FILTER (WHERE faltan > 0) AS pendientes_ocultos
FROM (
    SELECT r.match_id,
           (NOT EXISTS (SELECT 1 FROM match_summary.match_summary s WHERE s.match_id = r.match_id))::int
         + (NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = r.match_id))::int
         + (NOT EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id = r.match_id))::int
         + (NOT EXISTS (SELECT 1 FROM stats_player.stats_player sp WHERE sp.match_id = r.match_id))::int AS faltan
    FROM results.results r
    WHERE NOT EXISTS (SELECT 1 FROM fixtures.fixtures f WHERE f.match_id = r.match_id)
) x;
