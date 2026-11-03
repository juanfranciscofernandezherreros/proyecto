-- =============================================================================
-- MARCAR PARA REIMPORTAR LOS POINT_BY_POINT "COMPLETED" CUYOS DATOS YA NO ESTÁN
-- =============================================================================
-- Fecha:     2026-11-03 17:00
-- Tipo:      ESCRITURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1700_reimportar-point-by-point-sin-datos.sql
--
-- PARA QUÉ SIRVE
--   Diagnóstico en 2026-11-03_1650_pendientes-completados-sin-datos.sql: 66 peticiones de
--   point-by-point (61 partidos) importadas el 2026-10-21 están COMPLETED en
--   public.batch_launch_request, pero sus datos no están en point_by_point.point_by_point_event.
--   Como el launcher no reimporta un contenido (hash) ya COMPLETED, esos partidos quedan
--   pendientes para siempre y se extraen una y otra vez (CSV "repetidos" en Grafana).
--   Al pasarlas a FAILED, el launcher (BatchLaunchQueue.enqueue) las vuelve a poner en cola
--   la próxima vez que reciba ese mismo CSV, y esta vez sí se importan.
--
-- CUÁNDO USARLA
--   Si la consulta de diagnóstico vuelve a dar filas de point-by-point.
--
-- QUÉ TOCA Y QUÉ PROTEGE
--   Solo filas de public.batch_launch_request con status = 'COMPLETED', batch_type =
--   'point-by-point', con match_id en el nombre del fichero y SIN ninguna fila de ese partido
--   en point_by_point.point_by_point_event. No toca datos de partidos ni otras peticiones.
--   Cambia status a 'FAILED' y deja en error el motivo, para poder localizarlas.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  cuántas filas cumplen la condición antes de cambiar (esperado: 66).
--   PASO 2  "UPDATE n": n debe coincidir con el PASO 1.
--   PASO 3  0 filas = ya no queda ningún point-by-point COMPLETED sin datos.
--
-- QUÉ HACER DESPUÉS
--   Dejar que MATCHIDS_PENDIENTES procese esos partidos. Comprobar con:
--     SELECT status, count(*) FROM public.batch_launch_request
--     WHERE error = 'Reimportar: COMPLETED sin datos en point_by_point (2026-11-03)' GROUP BY 1;
--   Las que pasen a COMPLETED ya tienen sus datos en la base.
--
-- RESULTADO EL 2026-11-03
--   (se completa tras ejecutarla)
-- =============================================================================


-- PASO 1 · Cuántas peticiones se van a marcar.
SELECT count(*) AS a_marcar
FROM public.batch_launch_request b
WHERE b.status = 'COMPLETED' AND b.batch_type = 'point-by-point'
  AND substring(b.file_path FROM '_([A-Za-z0-9]{8})\.csv$') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p
                  WHERE p.match_id = substring(b.file_path FROM '_([A-Za-z0-9]{8})\.csv$'));

-- PASO 2 · Marcarlas como FAILED para que el launcher las reimporte al recibirlas.
UPDATE public.batch_launch_request b
SET status = 'FAILED',
    error = 'Reimportar: COMPLETED sin datos en point_by_point (2026-11-03)'
WHERE b.status = 'COMPLETED' AND b.batch_type = 'point-by-point'
  AND substring(b.file_path FROM '_([A-Za-z0-9]{8})\.csv$') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p
                  WHERE p.match_id = substring(b.file_path FROM '_([A-Za-z0-9]{8})\.csv$'));

-- PASO 3 · Comprobar: no debe quedar ninguna.
SELECT count(*) AS siguen_completed_sin_datos
FROM public.batch_launch_request b
WHERE b.status = 'COMPLETED' AND b.batch_type = 'point-by-point'
  AND substring(b.file_path FROM '_([A-Za-z0-9]{8})\.csv$') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p
                  WHERE p.match_id = substring(b.file_path FROM '_([A-Za-z0-9]{8})\.csv$'));
