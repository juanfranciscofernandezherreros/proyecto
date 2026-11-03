-- =============================================================================
-- ¿SE HAN IMPORTADO LOS CSV DE RESULTS DESDE QUE ARRANCÓ EL PC?
-- =============================================================================
-- Fecha:     2026-11-03 16:20
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1620_csv-results-desde-el-arranque.sql
--
-- PARA QUÉ SIRVE
--   El orquestador genera un RESULTS_<fecha>_<pais>_<competicion>.csv por liga y lo importa
--   por el launcher, que lo apunta en public.batch_launch_request. El request_id es el hash
--   del contenido (csv-sha256-...): si el CSV nuevo es idéntico a uno ya importado (no hubo
--   partidos nuevos en Flashscore), el launcher reutiliza la fila existente: solo cambia
--   file_path y NO crea fila nueva ni toca created_at. Por eso el dashboard "Procesamiento
--   en vivo", que cuenta por created_at, puede no mostrar nada aunque se esté importando.
--
-- CUÁNDO USARLA
--   Cuando el dashboard parezca parado pero en C:\data\basketball\competitions aparezcan
--   CSV de RESULTS nuevos.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  filas creadas después del arranque (cambiar la hora). 0 filas no significa que
--           fallara: puede que todo fuera contenido repetido.
--   PASO 2  filas cuyo file_path apunta a un CSV generado hoy a partir de las 16:00 pero con
--           created_at anterior: son CSV repetidos que el launcher reaprovechó.
--   PASO 3  última actualización de results.results por liga.
--
-- QUÉ HACER DESPUÉS
--   Si el PASO 2 lista las ligas recién extraídas, la importación fue bien (contenido sin
--   cambios). Si no aparecen ni en el PASO 1 ni en el 2, revisar los informes
--   C:\data\basketball\reports\<pais>\<competicion>\postgresql-import-*.csv.
--
-- RESULTADO EL 2026-11-03
--   PASO 1: 0 filas. PASO 2: las 8 ligas extraídas entre 16:10 y 16:17 (p. ej. germany/bbl,
--   request de las 10:21 con file_path ...RESULTS_20261103161613_germany_bbl.csv).
--   Los informes postgresql-count confirman 60 de 60 partidos en results.results para la BBL.
-- =============================================================================


-- PASO 1 · Peticiones creadas desde el arranque del PC (16:07:56 hora de Madrid).
SELECT created_at AT TIME ZONE 'Europe/Madrid' AS hora, status, batch_type, file_path
FROM public.batch_launch_request
WHERE created_at >= '2026-11-03 16:07:56 Europe/Madrid'
ORDER BY created_at;

-- PASO 2 · CSV de RESULTS recientes que el launcher reaprovechó (contenido repetido).
SELECT created_at AT TIME ZONE 'Europe/Madrid' AS creada, status, file_path
FROM public.batch_launch_request
WHERE batch_type = 'results'
  AND file_path LIKE '%RESULTS_2026110316%'
ORDER BY file_path;

-- PASO 3 · Última actualización de resultados por liga.
SELECT country, competition, count(*) AS partidos, max(updated_at) AT TIME ZONE 'Europe/Madrid' AS ultima
FROM results.results
GROUP BY 1, 2
ORDER BY 4 DESC NULLS LAST;
