-- =============================================================================
-- PENDIENTES QUE EL LAUNCHER DA POR COMPLETADOS PERO CUYOS DATOS NO ESTÁN EN LA BASE
-- =============================================================================
-- Fecha:     2026-11-03 16:50
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1650_pendientes-completados-sin-datos.sql
--
-- PARA QUÉ SIRVE
--   El launcher identifica cada CSV por el hash de su contenido (request_id = csv-sha256-...).
--   Si llega un CSV idéntico a uno que ya está COMPLETED, no lo vuelve a importar: devuelve la
--   petición antigua como COMPLETED. Si esos datos se borraron después (p. ej. la importación
--   del 21/10 de point_by_point ya no está en point_by_point.point_by_point_event), el partido
--   queda pendiente para siempre: se extrae, el launcher dice "COMPLETED" sin importar nada, la
--   auditoría lo sigue viendo pendiente y se vuelve a extraer. En Grafana se ve como CSV
--   "repetidos" del mismo partido una y otra vez.
--   Esta consulta cuenta, por dataset, las peticiones COMPLETED de CSV de partido cuyo partido
--   no tiene datos de ese dataset en la base.
--
-- CUÁNDO USARLA
--   Cuando los mismos partidos sigan pendientes tras procesarlos y salgan CSV repetidos.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  por dataset: peticiones COMPLETED sin datos y partidos afectados. Lo bueno es 0.
--   PASO 2  ejemplo de partidos afectados con la fecha de la importación antigua.
--
-- QUÉ HACER DESPUÉS
--   Si hay filas, hay que forzar que el launcher vuelva a importarlas (marcar esas peticiones
--   para reintento o cambiar el launcher para que reimporte el contenido repetido).
--
-- RESULTADO EL 2026-11-03
--   point-by-point: 66 peticiones COMPLETED de 61 partidos, todas importadas el 2026-10-21,
--   sin ninguna fila en point_by_point.point_by_point_event (p. ej. OQIrqQse, Nancy - Cholet).
--   Son los POINT_BY_POINT que la auditoría da como pendientes una y otra vez.
-- =============================================================================


-- PASO 1 · Peticiones COMPLETED de CSV de partido sin datos en su tabla, por dataset.
WITH req AS (
    SELECT request_id, batch_type, created_at,
           substring(file_path FROM '_([A-Za-z0-9]{8})\.csv$') AS match_id
    FROM public.batch_launch_request
    WHERE status = 'COMPLETED'
      AND batch_type IN ('point-by-point', 'team-stats', 'stats-player', 'match-summary')
), sin_datos AS (
    SELECT r.*
    FROM req r
    WHERE r.match_id IS NOT NULL
      AND NOT CASE r.batch_type
          WHEN 'point-by-point' THEN EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = r.match_id)
          ELSE true   -- los demás datasets se revisan en el PASO 3
      END
)
SELECT batch_type, count(*) AS peticiones, count(DISTINCT match_id) AS partidos,
       min(created_at)::date AS desde, max(created_at)::date AS hasta
FROM sin_datos GROUP BY 1;

-- PASO 2 · Ejemplos (point-by-point).
SELECT substring(file_path FROM '_([A-Za-z0-9]{8})\.csv$') AS match_id, created_at::date AS importado_el, request_id
FROM public.batch_launch_request b
WHERE status = 'COMPLETED' AND batch_type = 'point-by-point'
  AND NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p
                  WHERE p.match_id = substring(b.file_path FROM '_([A-Za-z0-9]{8})\.csv$'))
ORDER BY created_at DESC LIMIT 10;
