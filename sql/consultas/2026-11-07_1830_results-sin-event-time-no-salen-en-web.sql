-- =============================================================================
-- RESULTS SIN EVENT_TIME NO APARECEN EN LA WEB (aunque están en Mongo)
-- =============================================================================
-- Fecha:     2026-11-07 18:30
-- Tipo:      LECTURA (+ una ESCRITURA opcional de backfill, NO ejecutada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-07_1830_results-sin-event-time-no-salen-en-web.sql
--
-- PARA QUÉ SIRVE
--   Diagnóstico de por qué los partidos de euroleague extraídos el 2026-11-07
--   (p.ej. juVOVk74, IRWGXBxh, Ik9R0V7U, KxlaFUMN, nPkiHjhB, jLvV98po, tSnqJCNb,
--   xdTWTTyH, Y1qyLYhn) SÍ se cargan en Postgres y SÍ se proyectan a MongoDB,
--   pero NO salen en la web.
--   Causa: la web pide el listado con status=finished. El filtro "finished" de la
--   API (MatchServiceImpl.java:49-54) exige que result.eventTime NO sea null ni "".
--   En results.results esos partidos tienen event_time VACÍO, así que el projector
--   genera result.eventTime=null y el filtro los descarta. La hora sí existe en
--   fixtures.fixtures (20:30, 19:00, 20:45...), por eso el backfill es posible.
--
-- CUÁNDO USARLA
--   Cuando se procesen RESULTS nuevos y los partidos finalizados no aparezcan en la
--   web pese a estar en Mongo con marcador.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1: filas con event_time vacío = partidos que el filtro "finished" oculta.
--   PASO 2: confirma que la hora real existe en fixtures (columna event_time).
--   PASO 3 (verificación): tras el backfill, event_time debe quedar relleno.
--
-- QUÉ HACER DESPUÉS
--   Dos arreglos posibles:
--     (A) Backfill en results.event_time desde fixtures.event_time (PASO 3, ESCRITURA).
--     (B) Relajar el filtro "finished" de la API para basarse en homeScore/awayScore
--         presentes en vez de exigir result.eventTime. (cambio de código, no SQL)
--   Tras cualquiera, el projector reproyecta (~1 min) y la web los mostrará.
--
-- RESULTADO EL 2026-11-07
--   PASO 1 devolvió 9 partidos de euroleague de hoy con event_time vacío.
--   PASO 2 confirmó que fixtures.event_time tiene la hora real de los 9.
--   PASO 3 (backfill) EJECUTADO: UPDATE 10. Los 9 quedaron con su hora real
--   (20:45, 20:30, 19:00...). Tras la reproyección (~1 min) salen en la web.
--   Nota de causa: hoy NO se extrajo el CSV RESULTS_ (que trae eventTime); results
--   se rellenó desde SCORE_SUMMARY, que no tiene columna de hora. El backfill es un
--   parche; para que no reincida hay que extraer RESULTS_ o relajar el filtro de la API.
-- =============================================================================

-- PASO 1 · LECTURA · RESULTS de hoy con event_time vacío (los que oculta la web).
--   match_id sin event_time = partido finalizado que no pasa el filtro "finished".
SELECT r.match_id, r.event_time, r.home_score, r.away_score
FROM results.results r
WHERE r.match_id IN ('juVOVk74','IRWGXBxh','Ik9R0V7U','KxlaFUMN','nPkiHjhB',
                     'jLvV98po','tSnqJCNb','xdTWTTyH','Y1qyLYhn','KxK9hBgL','jLAumkHr')
ORDER BY r.match_id;

-- PASO 2 · LECTURA · La hora real SÍ está en fixtures (origen del backfill).
SELECT f.match_id, f.event_time
FROM fixtures.fixtures f
WHERE f.match_id IN ('juVOVk74','IRWGXBxh','Ik9R0V7U','KxlaFUMN','nPkiHjhB',
                     'jLvV98po','tSnqJCNb','xdTWTTyH','Y1qyLYhn')
ORDER BY f.match_id;

-- PASO 3 · ESCRITURA (OPCIONAL, NO EJECUTADA) · Backfill de results.event_time
--   desde fixtures.event_time.
--   Qué filas toca: SOLO results con event_time vacío que tengan una fixture con hora.
--   Protección: no pisa results que ya tengan hora; exige que la fixture tenga hora.
--   Cómo comprobar: repetir el PASO 1; event_time debe dejar de estar vacío.
-- OJO: results.event_time es varchar y fixtures.event_time es time; comparar el time
-- con '' da error, por eso el filtro usa solo IS NULL / IS NOT NULL.
UPDATE results.results r
SET event_time = f.event_time
FROM fixtures.fixtures f
WHERE f.match_id = r.match_id
  AND r.event_time IS NULL
  AND f.event_time IS NOT NULL;
