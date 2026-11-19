-- =============================================================================
-- FECHAS DE PARTIDOS EN LA WEB (8083)
-- =============================================================================
-- Fecha:     2026-11-19 10:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-19_1000_fechas-partidos-web.sql
--
-- PARA QUÉ SIRVE   El usuario ve fechas incorrectas en localhost:8083. Compara la
--                  fecha/hora guardada en results (event_datetime y event_time) y
--                  en fixtures para los partidos de la última semana.
-- CUÁNDO USARLA    Cuando la fecha de un partido en la web no coincide con Flashscore.
-- CÓMO LEER        event_datetime (timestamptz) frente a event_time (texto) y
--                  fixtures.event_datetime: si difieren en horas o en un día, hay
--                  desfase de zona horaria o de fecha en la carga.
-- QUÉ HACER DESPUÉS Si hay desfase, revisar cómo se convierte la hora en el CSV/projector.
-- RESULTADO EL 2026-11-19  Hora en UTC en los 40 últimos; 67 partidos con el día desfasado. Corregido en el projector (726f5db).
-- =============================================================================

-- PASO 1 · Resultados recientes con su fecha/hora guardada en las dos formas.
SELECT r.source_event_id, r.event_datetime, r.event_time, r.event_datetime AT TIME ZONE 'Europe/Madrid' AS madrid
FROM results.results r
WHERE r.event_datetime >= now() - interval '5 days'
ORDER BY r.event_datetime DESC
LIMIT 30;

-- PASO 2 · Mismos partidos en fixtures, para comparar.
SELECT f.source_event_id, f.event_datetime, f.event_time
FROM fixtures.fixtures f
WHERE f.event_datetime >= now() - interval '5 days'
ORDER BY f.event_datetime DESC
LIMIT 30;
