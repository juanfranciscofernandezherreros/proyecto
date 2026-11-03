-- =============================================================================
-- AVANCE: PARTIDOS SIN event_datetime POR COMPETICIÓN
-- =============================================================================
-- Fecha:     2026-11-03 10:15
-- Tipo:      LECTURA (no modifica nada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1015_avance-reextraccion-event-datetime.sql
--
-- PARA QUÉ SIRVE
--   Mientras se vuelven a extraer e importar los RESULTS de varias ligas (por ejemplo con
--   1_EJECUTAR\LIGAS_ORQUESTAR.bat ALL results 10), cada liga corrige sus partidos al
--   importarse. Esta consulta muestra, liga a liga, cuántos partidos siguen sin fecha, para
--   ver el avance y saber cuándo ha terminado de verdad.
--
-- CUÁNDO USARLA
--   · Durante o después de una reextracción de RESULTS.
--   · Como comprobación rápida de que ninguna competición tiene partidos sin fecha.
--
-- CÓMO LEER EL RESULTADO
--   · Solo aparecen las competiciones a las que todavía les falta algo. Si no sale ninguna
--     fila, no queda ningún partido sin event_datetime.
--   · sin_event_datetime y sin_event_time deberían ser iguales. Si difieren, hay filas con
--     una de las dos columnas vacía: revisarlas con 2026-11-03_0925_partidos-sin-event-time.sql.
--   · Una competición que sigue apareciendo DESPUÉS de procesarse su liga indica que
--     Flashscore no da la hora de esos partidos o que la extracción de esa liga falló:
--     mirar el resumen ligas-orquestar-resumen-<fecha>.csv en C:\data\basketball\reports\orchestrator.
--
-- QUÉ HACER DESPUÉS
--   · Lista vacía → terminado.
--   · Quedan partidos de una liga que ya se procesó → diagnosticarlos con
--     2026-11-03_0925_partidos-sin-event-time.sql (PASO 3 y PASO 4).
--
-- RESULTADO EL 2026-11-03
--   10:15 → 13 pendientes (LNB 5, BBL 4, Winner 2, LKL 1, KLS 1).
--   10:30 → 3 pendientes (Winner 2, KLS 1) mientras se procesaba la última liga.
--   10:31 → 0 filas: los 635 partidos tienen event_datetime (reextracción con Edge,
--           22 pasos OK y 0 fallos).
-- =============================================================================


-- PASO ÚNICO · Por competición, cuántos partidos no tienen event_datetime ni event_time.
--              HAVING deja fuera las competiciones que ya están completas.
SELECT country || '/' || competition                               AS competicion,
       count(*) FILTER (WHERE event_datetime IS NULL)               AS sin_event_datetime,
       count(*) FILTER (WHERE coalesce(trim(event_time), '') = '')  AS sin_event_time
FROM results.results
GROUP BY 1
HAVING count(*) FILTER (WHERE event_datetime IS NULL) > 0
ORDER BY 2 DESC;
