-- =============================================================================
-- PARTIDOS DEL CALENDARIO YA JUGADOS QUE TODAVÍA NO TIENEN RESULTADO
-- =============================================================================
-- Fecha:     2026-11-03 13:00
-- Tipo:      LECTURA (no modifica nada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1300_fixtures-jugados-sin-results.sql
--
-- PARA QUÉ SIRVE
--   fixtures.fixtures es el calendario (partidos programados) y results.results los partidos
--   ya jugados con su marcador. Un partido cuya fecha (event_datetime) ya pasó pero que no está
--   en results.results es un hueco: falta importar los RESULTS de su liga. Mientras falte, la
--   auditoría de pendientes no puede tratarlo como partido jugado y no se procesan sus datos.
--   Se cruza por match_id. Se deja un margen de 3 horas desde el inicio para no contar
--   partidos que aún se están jugando.
--
-- CUÁNDO USARLA
--   · Antes y después de lanzar LIGAS_ORQUESTAR ALL results, para ver qué huecos cubrió.
--   · La ejecutan AUTOMATICO_INICIO y CICLO_DIARIO (scripts\pendientes\FIXTURES_SIN_RESULTS.bat)
--     y dejan el resultado en su log.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  una fila por competición con huecos: sin_resultado = partidos jugados sin fila en
--           results; mas_antiguo / mas_reciente = rango de fechas de esos partidos.
--           Lo bueno es que no salga ninguna fila, o solo partidos de las últimas horas.
--   PASO 2  total de huecos.
--
-- QUÉ HACER DESPUÉS
--   · Si quedan huecos tras lanzar RESULTS: revisar el log de esa liga en LIGAS_ORQUESTAR
--     (extracción fallida) o la resultsUrl de la liga en LIGAS_BASKET.json.
--   · Huecos muy antiguos que nunca se cubren: partidos aplazados o cancelados en el calendario.
--
-- RESULTADO EL 2026-11-03
--   0 filas en el PASO 1 y total_sin_resultado = 0: todos los partidos jugados del
--   calendario tienen resultado.
-- =============================================================================

-- PASO 1 · Huecos por competición: fixtures con fecha pasada (más 3 h de margen) sin results.
SELECT f.country,
       f.competition,
       count(*)                                                        AS sin_resultado,
       min(f.event_datetime AT TIME ZONE 'Europe/Madrid')::date        AS mas_antiguo,
       max(f.event_datetime AT TIME ZONE 'Europe/Madrid')::date        AS mas_reciente
FROM fixtures.fixtures f
WHERE f.event_datetime < now() - interval '3 hours'
  AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id)
GROUP BY f.country, f.competition
ORDER BY sin_resultado DESC, f.country, f.competition;

-- PASO 2 · Total de huecos.
SELECT count(*) AS total_sin_resultado
FROM fixtures.fixtures f
WHERE f.event_datetime < now() - interval '3 hours'
  AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id);
