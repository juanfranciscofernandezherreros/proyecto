-- =============================================================================
-- BORRAR LOS PASOS DE SPRING BATCH QUE IMPIDEN REIMPORTAR LOS POINT_BY_POINT
-- =============================================================================
-- Fecha:     2026-11-03 17:25
-- Tipo:      ESCRITURA (borra filas de historial interno de Spring Batch)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1725_reimportar-point-by-point-borrar-pasos.sql
--
-- PARA QUÉ SIRVE
--   Tercer paso tras 2026-11-03_1700_... y 2026-11-03_1715_... Con los jobs ya en FAILED,
--   Spring Batch intenta CONTINUAR el paso antiguo desde la fila donde se quedó (88 en
--   OQIrqQse) y falla con "Could not move to stored position on restart". Borrando el
--   registro del paso (batch_step_execution y su contexto), al relanzar el job el paso
--   empieza desde la primera fila y escribe los datos.
--
-- QUÉ TOCA Y QUÉ PROTEGE
--   Solo filas de point_by_point_batch.batch_step_execution_context y batch_step_execution
--   de los jobs FAILED de las peticiones marcadas a las 17:00 (y la de OQIrqQse). Es solo el
--   historial de ejecución de Spring Batch: no toca datos de partidos, ni los jobs, ni otras
--   peticiones. No se puede deshacer, pero no hace falta: el historial se vuelve a crear al
--   relanzar.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  cuántos pasos se van a borrar.  PASO 2-3 "DELETE n".  PASO 4  0.
--
-- QUÉ HACER DESPUÉS
--   Dejar que MATCHIDS_PENDIENTES relance esos partidos y comprobar que tienen filas:
--   SELECT count(*) FROM point_by_point.point_by_point_event WHERE match_id = 'OQIrqQse';
-- =============================================================================

-- PASO 1 · Pasos que se van a borrar.
SELECT count(*) AS pasos_a_borrar
FROM point_by_point_batch.batch_step_execution s
WHERE s.job_execution_id IN (
    SELECT e.job_execution_id
    FROM point_by_point_batch.batch_job_execution e
    JOIN point_by_point_batch.batch_job_execution_params p USING (job_execution_id)
    WHERE p.parameter_name = 'sourceEventId' AND e.status = 'FAILED'
      AND p.parameter_value IN (SELECT request_id FROM public.batch_launch_request
                                WHERE error = 'Reimportar: COMPLETED sin datos en point_by_point (2026-11-03)'
                                   OR request_id = 'csv-sha256-8dd16dbfd8e861d935330389629a824e8b546dd1e348243f3ab5da56333cb943'));

-- PASO 2 · Borrar el contexto de esos pasos (depende del paso, va primero).
DELETE FROM point_by_point_batch.batch_step_execution_context
WHERE step_execution_id IN (
    SELECT s.step_execution_id
    FROM point_by_point_batch.batch_step_execution s
    JOIN point_by_point_batch.batch_job_execution e USING (job_execution_id)
    JOIN point_by_point_batch.batch_job_execution_params p USING (job_execution_id)
    WHERE p.parameter_name = 'sourceEventId' AND e.status = 'FAILED'
      AND p.parameter_value IN (SELECT request_id FROM public.batch_launch_request
                                WHERE error = 'Reimportar: COMPLETED sin datos en point_by_point (2026-11-03)'
                                   OR request_id = 'csv-sha256-8dd16dbfd8e861d935330389629a824e8b546dd1e348243f3ab5da56333cb943'));

-- PASO 3 · Borrar los pasos.
DELETE FROM point_by_point_batch.batch_step_execution
WHERE job_execution_id IN (
    SELECT e.job_execution_id
    FROM point_by_point_batch.batch_job_execution e
    JOIN point_by_point_batch.batch_job_execution_params p USING (job_execution_id)
    WHERE p.parameter_name = 'sourceEventId' AND e.status = 'FAILED'
      AND p.parameter_value IN (SELECT request_id FROM public.batch_launch_request
                                WHERE error = 'Reimportar: COMPLETED sin datos en point_by_point (2026-11-03)'
                                   OR request_id = 'csv-sha256-8dd16dbfd8e861d935330389629a824e8b546dd1e348243f3ab5da56333cb943'));

-- PASO 4 · Comprobar: no queda ninguno.
SELECT count(*) AS pasos_restantes
FROM point_by_point_batch.batch_step_execution s
WHERE s.job_execution_id IN (
    SELECT e.job_execution_id
    FROM point_by_point_batch.batch_job_execution e
    JOIN point_by_point_batch.batch_job_execution_params p USING (job_execution_id)
    WHERE p.parameter_name = 'sourceEventId' AND e.status = 'FAILED'
      AND p.parameter_value IN (SELECT request_id FROM public.batch_launch_request
                                WHERE error = 'Reimportar: COMPLETED sin datos en point_by_point (2026-11-03)'
                                   OR request_id = 'csv-sha256-8dd16dbfd8e861d935330389629a824e8b546dd1e348243f3ab5da56333cb943'));
