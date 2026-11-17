-- =============================================================================
-- ÚLTIMAS CARGAS DE RESULTADOS-AYER EN EL LAUNCHER
-- =============================================================================
-- Fecha:     2026-11-17 12:05
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_1205_cargas-resultados-ayer-launcher.sql
--
-- PARA QUÉ SIRVE   ver si las partes por liga que envía `basket resultados-ayer`
--                  (ficheros bajo reports\resultados-ayer\) se cargaron bien en el
--                  launcher (public.batch_launch_request) y, si no, con qué error.
--                  La misma consulta, cambiando el filtro por '%<match_id>%', sirve
--                  en procesar-pendientes para ver las cargas de un partido.
-- CUÁNDO USARLA    cuando resultados-ayer imprime PROCESAR ... -> FAILED o tiempo agotado.
-- CÓMO LEER EL RESULTADO  status COMPLETED y exit_code 0 = bien; FAILED o exit_code
--                  distinto de 0 = mirar la columna error.
-- QUÉ HACER DESPUÉS       corregir la causa y repetir `basket resultados-ayer`.
-- RESULTADO EL 2026-11-17 2 filas COMPLETED / 0 (cargas de 20261116 a las 09:18 UTC).
-- =============================================================================

-- PASO 1 · Estructura de la tabla (paso intermedio, desde psql): \d public.batch_launch_request
--          Confirmó que el fichero va en file_path (no hay columna de payload).

-- PASO 2 · Cargas de resultados-ayer, de la más reciente a la más antigua.
SELECT status, exit_code, finished_at, file_path, left(error, 200) AS error
FROM public.batch_launch_request
WHERE file_path LIKE '%resultados-ayer%'
ORDER BY created_at DESC
LIMIT 10;
