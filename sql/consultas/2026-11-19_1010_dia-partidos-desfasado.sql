-- =============================================================================
-- DÍA DE PARTIDOS DESFASADO EN LA WEB
-- =============================================================================
-- Fecha:     2026-11-19 10:10
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-19_1010_dia-partidos-desfasado.sql
--
-- PARA QUÉ SIRVE   Ver si el día de un partido cambia al pasar de UTC a Madrid.
--                  La web muestra el día de event_datetime (UTC); el día real es
--                  el de event_time en Madrid. Si difieren, el partido sale en otro día.
-- CUÁNDO USARLA    Cuando un partido aparece el día anterior o posterior en la web.
-- CÓMO LEER        dia_utc (lo que muestra la web) frente a dia_madrid (el real).
--                  Las filas con dia_utc <> dia_madrid son las desfasadas.
-- QUÉ HACER DESPUÉS Corregir la conversión de fecha en la API o el proyector.
-- RESULTADO EL 2026-11-19  Hora en UTC en los 40 últimos; 67 partidos con el día desfasado. Corregido en el projector (726f5db).
-- =============================================================================

-- PASO 1 · Partidos cuyo día en UTC no coincide con el día real de Madrid.
SELECT r.source_event_id,
       r.event_datetime                                   AS guardado_utc,
       r.event_time                                       AS hora_local_flashscore,
       (r.event_datetime)::date                           AS dia_utc,
       (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date AS dia_madrid
FROM results.results r
WHERE r.event_datetime IS NOT NULL
  AND (r.event_datetime)::date <> (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date
ORDER BY r.event_datetime DESC
LIMIT 50;

-- PASO 2 · Cuántos partidos hay en total afectados.
SELECT count(*) AS partidos_desfasados
FROM results.results r
WHERE r.event_datetime IS NOT NULL
  AND (r.event_datetime)::date <> (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date;
