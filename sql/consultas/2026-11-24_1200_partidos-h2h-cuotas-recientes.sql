-- =============================================================================
-- PARTIDOS A LOS QUE EXTRAER H2H Y CUOTAS: PRÓXIMOS 7 DÍAS Y ÚLTIMOS 7 DÍAS
-- =============================================================================
-- Fecha:     2026-11-24 12:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1200_partidos-h2h-cuotas-recientes.sql
--
-- PARA QUÉ SIRVE   Los CSV H2H y ODDS en disco solo cubren del 5 al 30 de octubre, así
--                  que la web no muestra H2H ni cuotas en los partidos actuales. Esta
--                  consulta lista los partidos a extraer de Flashscore: los de los
--                  próximos 7 días (fixtures sin resultado) y los jugados los últimos 7
--                  días (results), sin la pretemporada de la NBA.
-- CUÁNDO USARLA    Antes de lanzar basket reextraer --dataset h2h-cuotas.
-- CÓMO LEER EL RESULTADO  Paso 1: cuántos por tramo y liga. Paso 2: la lista de
--                  match_id (la que se pasa a reextraer con --fichero).
-- QUÉ HACER DESPUÉS       Guardar el Paso 2 en un fichero y lanzar la reextracción.
-- RESULTADO EL 2026-11-24 (se completa tras ejecutarla)
-- =============================================================================

-- PASO 1 · Partidos por tramo y competición.
WITH candidatos AS (
    SELECT match_id, competition, 'ultimos 7 dias' AS tramo
    FROM results.results
    WHERE event_datetime >= now() - interval '7 days' AND event_datetime < now()
    UNION
    SELECT f.match_id, f.competition, 'proximos 7 dias'
    FROM fixtures.fixtures f
    WHERE f.event_datetime >= now() AND f.event_datetime < now() + interval '7 days'
      AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id AND r.home_score IS NOT NULL)
)
SELECT tramo, competition, count(DISTINCT match_id) AS partidos
FROM candidatos
GROUP BY ROLLUP (tramo, competition)
ORDER BY tramo NULLS LAST, competition NULLS LAST;

-- PASO 2 · Lista de match_id, del más próximo al más antiguo.
SELECT match_id
FROM (
    SELECT match_id, event_datetime FROM results.results
    WHERE event_datetime >= now() - interval '7 days' AND event_datetime < now()
    UNION
    SELECT f.match_id, f.event_datetime FROM fixtures.fixtures f
    WHERE f.event_datetime >= now() AND f.event_datetime < now() + interval '7 days'
      AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id AND r.home_score IS NOT NULL)
) p
GROUP BY match_id
ORDER BY max(event_datetime) DESC;
