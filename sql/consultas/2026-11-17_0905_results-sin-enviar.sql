-- =============================================================================
-- RESULTS "SIN ENVIAR" EN EL DASHBOARD DE CSV PROCESADOS
-- =============================================================================
-- Fecha:     2026-11-17 09:05
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_0905_results-sin-enviar.sql
--
-- PARA QUÉ SIRVE   El dashboard "CSV procesados" muestra CSV de RESULTS de hoy como
--                  SIN ENVIAR. Se mira qué peticiones del launcher hay para los RESULTS
--                  de hoy y si cada liga tiene al menos un fichero COMPLETED.
-- CUÁNDO USARLA    Cuando salgan RESULTS SIN ENVIAR en el dashboard.
-- CÓMO LEER EL RESULTADO  Paso 1: todas las peticiones de RESULTS de hoy con su estado.
--                  Paso 2: por liga, cuántos ficheros sin enviar y cuántos completados.
--                  Si una liga tiene completados > 0, sus SIN ENVIAR son copias repetidas.
-- QUÉ HACER DESPUÉS       Si una liga tiene 0 completados, reimportar con basket procesar-csv <LIGA>.
-- RESULTADO EL 2026-11-17 Paso 1 falló (la tabla no tiene columna id). Paso 2: las 11 ligas
--                  tienen 1 RESULTS COMPLETED; los SIN ENVIAR (2 en Euroliga, 1 en el resto) son
--                  copias de una extracción anterior (~07:50) con el mismo contenido.
-- =============================================================================

-- PASO 1 · Peticiones de RESULTS creadas hoy.
SELECT id, status, created_at, finished_at, file_path
FROM public.batch_launch_request
WHERE batch_type ILIKE '%RESULT%' AND created_at >= current_date
ORDER BY created_at;

-- PASO 2 · Por liga: ficheros RESULTS de hoy, sin enviar y completados.
SELECT liga,
       count(*) FILTER (WHERE estado = 'SIN ENVIAR') AS sin_enviar,
       count(*) FILTER (WHERE estado = 'COMPLETED')  AS completados
FROM public.v_csv_generados
WHERE dataset = 'RESULTS' AND generado >= current_date
GROUP BY liga ORDER BY liga;
