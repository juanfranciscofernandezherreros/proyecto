-- =============================================================================
-- AUDITORÍA DE INTEGRIDAD DEL READ MODEL (Postgres -> Mongo -> API/web)
-- =============================================================================
-- Fecha:     2026-11-07 19:15
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-07_1915_auditoria-integridad-read-model.sql
--
-- PARA QUÉ SIRVE   Medir huecos de datos que afectan a lo que se ve en la web:
--                  results sin hora/país/competición, fixtures sin hora, y el
--                  desajuste entre fixtures de Postgres y el objeto fixture del
--                  read model de Mongo.
-- CUÁNDO USARLA    Cuando falten partidos en la web o se vean tarjetas vacías.
-- CÓMO LEER EL RESULTADO  Cada PASO indica qué valor es "malo".
-- QUÉ HACER DESPUÉS  Si hay results sin hora -> backfill
--                  (2026-11-07_1830_results-sin-event-time-no-salen-en-web.sql).
--                  Si fixtures sin event_time no proyectan el objeto fixture ->
--                  es un bug del projector (ver informe).
-- RESULTADO EL 2026-11-07
--   results total 647 · sin event_time 0 (tras backfill) · sin country/competition 10
--   fixtures 3081 (todas distintas) · sin event_time 1975
--   Mongo matches 3533 · con objeto fixture 1744 · con availableSections=[fixture]
--   pero fixture null: 1337 · scheduled (result null) 2886, de ellos 1337 sin fixture.
-- =============================================================================

-- PASO 1 · LECTURA · Huecos en results (lo que puede ocultar/romper tarjetas).
SELECT
  count(*)                                                        AS total,
  count(*) FILTER (WHERE event_time IS NULL OR event_time='')     AS sin_event_time,
  count(*) FILTER (WHERE country  IS NULL OR country='')          AS sin_country,
  count(*) FILTER (WHERE competition IS NULL OR competition='')   AS sin_competition,
  count(*) FILTER (WHERE event_datetime IS NULL)                  AS sin_event_datetime
FROM results.results;

-- PASO 2 · LECTURA · results duplicados por match_id (deberían ser 0).
SELECT match_id, count(*) c
FROM results.results
GROUP BY match_id HAVING count(*) > 1
ORDER BY c DESC;

-- PASO 3 · LECTURA · fixtures: total, distintos y sin hora.
SELECT
  count(*)                                   AS filas,
  count(DISTINCT match_id)                   AS match_id_distintos,
  count(*) FILTER (WHERE event_time IS NULL) AS sin_event_time
FROM fixtures.fixtures;

-- PASO 4 · LECTURA · results que vinieron de SCORE_SUMMARY (sin país/comp/fecha)
--   pero que SÍ tienen fixture (se clasifican por la fixture en la web).
SELECT r.match_id, r.home_team, r.away_team,
       (SELECT count(*) FROM fixtures.fixtures f WHERE f.match_id = r.match_id) AS tiene_fixture
FROM results.results r
WHERE r.country IS NULL OR r.country = ''
ORDER BY r.match_id;
