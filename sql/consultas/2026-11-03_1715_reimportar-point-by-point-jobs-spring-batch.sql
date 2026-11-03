-- =============================================================================
-- PERMITIR QUE SPRING BATCH VUELVA A IMPORTAR LOS POINT_BY_POINT QUE YA NO ESTÁN EN LA BASE
-- =============================================================================
-- Fecha:     2026-11-03 17:15
-- Tipo:      ESCRITURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1715_reimportar-point-by-point-jobs-spring-batch.sql
--
-- PARA QUÉ SIRVE
--   Complementa 2026-11-03_1700_reimportar-point-by-point-sin-datos.sql. Aunque el launcher
--   vuelva a lanzar el CSV, el importador de point-by-point (ImportService) busca en
--   point_by_point_batch el último job con el mismo sourceEventId (csv-sha256-<hash>) y, si
--   está COMPLETED, no lee el fichero: termina "COMPLETED" sin escribir nada. Los jobs del
--   2026-10-21 de esos partidos escribieron sus filas, pero esas filas ya no están en
--   point_by_point.point_by_point_event (se borraron después, fuera del importador).
--   Pasando a FAILED el job y sus pasos, Spring Batch vuelve a ejecutarlos al relanzarlos y
--   las filas se escriben de nuevo (el INSERT es ON CONFLICT DO UPDATE: no duplica).
--
-- CUÁNDO USARLA
--   Junto con la de las 17:00, cuando haya point-by-point COMPLETED sin datos en la base.
--
-- QUÉ TOCA Y QUÉ PROTEGE
--   Solo point_by_point_batch.batch_job_execution y batch_step_execution de los jobs cuyo
--   sourceEventId es una de las peticiones marcadas a las 17:00 (error = 'Reimportar: ...').
--   Solo cambia status/exit_code a FAILED. No borra nada ni toca datos de partidos.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  número de jobs y de peticiones afectadas.
--   PASO 2-3 "UPDATE n" de jobs y de pasos.
--   PASO 4  0 = ningún job COMPLETED queda bloqueando esas peticiones.
--
-- QUÉ HACER DESPUÉS
--   Relanzar los CSV (lo hace solo MATCHIDS_PENDIENTES) y comprobar que el partido ya tiene
--   filas: SELECT count(*) FROM point_by_point.point_by_point_event WHERE match_id = '<id>';
--
-- RESULTADO EL 2026-11-03
--   PASO 1: 66 jobs de 66 peticiones. PASO 2-3: UPDATE 66 y UPDATE 66. PASO 4: 0.
--   Además, a mano: UPDATE de la petición de OQIrqQse a FAILED (se había reprobado).
--   Al relanzar OQIrqQse falló con "Could not move to stored position on restart": Spring
--   Batch intentaba CONTINUAR el paso antiguo desde la fila 88. Siguiente paso:
--   2026-11-03_1725_reimportar-point-by-point-borrar-pasos.sql.
-- =============================================================================


-- PASO 1 · Jobs COMPLETED de las peticiones marcadas para reimportar.
SELECT count(DISTINCT e.job_execution_id) AS jobs, count(DISTINCT p.parameter_value) AS peticiones
FROM point_by_point_batch.batch_job_execution_params p
JOIN point_by_point_batch.batch_job_execution e USING (job_execution_id)
WHERE p.parameter_name = 'sourceEventId' AND e.status = 'COMPLETED'
  AND p.parameter_value IN (SELECT request_id FROM public.batch_launch_request
                            WHERE error = 'Reimportar: COMPLETED sin datos en point_by_point (2026-11-03)'
                               OR request_id = 'csv-sha256-8dd16dbfd8e861d935330389629a824e8b546dd1e348243f3ab5da56333cb943');

-- PASO 2 · Pasos (steps) de esos jobs a FAILED, para que se vuelvan a ejecutar.
UPDATE point_by_point_batch.batch_step_execution s
SET status = 'FAILED', exit_code = 'FAILED'
WHERE s.status = 'COMPLETED' AND s.job_execution_id IN (
    SELECT e.job_execution_id
    FROM point_by_point_batch.batch_job_execution_params p
    JOIN point_by_point_batch.batch_job_execution e USING (job_execution_id)
    WHERE p.parameter_name = 'sourceEventId' AND e.status = 'COMPLETED'
      AND p.parameter_value IN (SELECT request_id FROM public.batch_launch_request
                                WHERE error = 'Reimportar: COMPLETED sin datos en point_by_point (2026-11-03)'
                                   OR request_id = 'csv-sha256-8dd16dbfd8e861d935330389629a824e8b546dd1e348243f3ab5da56333cb943'));

-- PASO 3 · Los jobs a FAILED.
UPDATE point_by_point_batch.batch_job_execution e
SET status = 'FAILED', exit_code = 'FAILED'
WHERE e.status = 'COMPLETED' AND e.job_execution_id IN (
    SELECT p.job_execution_id FROM point_by_point_batch.batch_job_execution_params p
    WHERE p.parameter_name = 'sourceEventId'
      AND p.parameter_value IN (SELECT request_id FROM public.batch_launch_request
                                WHERE error = 'Reimportar: COMPLETED sin datos en point_by_point (2026-11-03)'
                                   OR request_id = 'csv-sha256-8dd16dbfd8e861d935330389629a824e8b546dd1e348243f3ab5da56333cb943'));

-- PASO 4 · Comprobar: no debe quedar ningún job COMPLETED de esas peticiones.
SELECT count(*) AS siguen_completed
FROM point_by_point_batch.batch_job_execution_params p
JOIN point_by_point_batch.batch_job_execution e USING (job_execution_id)
WHERE p.parameter_name = 'sourceEventId' AND e.status = 'COMPLETED'
  AND p.parameter_value IN (SELECT request_id FROM public.batch_launch_request
                            WHERE error = 'Reimportar: COMPLETED sin datos en point_by_point (2026-11-03)'
                               OR request_id = 'csv-sha256-8dd16dbfd8e861d935330389629a824e8b546dd1e348243f3ab5da56333cb943');
