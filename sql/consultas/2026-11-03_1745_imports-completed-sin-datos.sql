-- =============================================================================
-- IMPORTS "COMPLETED" QUE NO DEJAN DATOS EN LA BD
-- =============================================================================
-- Fecha:     2026-11-03 17:45
-- Tipo:      LECTURA (no modifica nada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1745_imports-completed-sin-datos.sql
--
-- PARA QUÉ SIRVE
--   El launcher (public.batch_launch_request) y cada job (esquemas *_batch) deduplicaban
--   por el SHA-256 del CSV. Si un CSV con el mismo contenido se importó una vez (p. ej. el
--   2026-10-21) y luego los datos desaparecieron de la BD, cada reextracción devolvía
--   "COMPLETED" sin ejecutar nada: la auditoría seguía viendo el partido pendiente y
--   MATCHIDS_PENDIENTES lo repetía eternamente ("no se procesa nada").
--   Corregido el 2026-11-03: un CSV con otra ruta se vuelve a importar (launcher
--   BatchLaunchQueue + parámetro "file" identificador en los 6 ImportService).
--
-- CUÁNDO USARLA
--   · Si un partido sale "COMPLETED" en csv-batch-ingestion-report.json pero sigue pendiente.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  estado de la petición del launcher: attempts y finished_at. Un finished_at
--           antiguo con el fichero de hoy = deduplicado sin ejecutar (el fallo).
--   PASO 2  últimas ejecuciones reales del job de player stats con lo leído y escrito.
--           Si no hay ejecución a la hora del envío, el job no corrió.
--   PASO 3  filas reales del partido. 0 = no se importó.
--
-- QUÉ HACER DESPUÉS
--   Con el arreglo, basta con volver a lanzar MATCHIDS_PENDIENTES.
--
-- RESULTADO EL 2026-11-03
--   McU4j8kL: petición COMPLETED desde 2026-10-21, 0 filas en stats_player; ningún job a
--   las 17:45. Tras el arreglo y reenvío: 22 filas.
-- =============================================================================

-- PASO 1 · Petición del launcher para el CSV de PLAYER_STATS de McU4j8kL.
SELECT request_id, file_path, status, attempts, created_at, finished_at, exit_code
FROM batch_launch_request
WHERE request_id LIKE 'csv-sha256-6ef6cfb4%';

-- PASO 2 · Últimas ejecuciones reales del job de player stats.
SELECT je.job_execution_id, je.status, je.exit_message, se.read_count, se.write_count,
       se.filter_count, se.read_skip_count, se.process_skip_count, se.write_skip_count, je.end_time
FROM stats_player_batch.batch_job_execution je
JOIN stats_player_batch.batch_step_execution se USING (job_execution_id)
ORDER BY je.job_execution_id DESC
LIMIT 4;

-- PASO 3 · Filas reales del partido.
SELECT count(*) FROM stats_player.stats_player WHERE match_id = 'McU4j8kL';
