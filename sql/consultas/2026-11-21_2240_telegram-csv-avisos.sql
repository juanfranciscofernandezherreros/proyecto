-- =============================================================================
-- AVISOS DE TELEGRAM POR CSV: CUÁNTOS SE PROCESAN, DE QUÉ PARTIDOS Y SI SE REPITEN
-- =============================================================================
-- Fecha:     2026-11-21 22:40
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-21_2240_telegram-csv-avisos.sql
--
-- PARA QUÉ SIRVE   El vigilante de Telegram (scripts\py\monitor\telegram_csv.py) manda un mensaje por
--                  cada fila COMPLETED/FAILED de public.batch_launch_request, es decir, por cada CSV
--                  procesado. Esta consulta mide cuántos mensajes salen y si se repiten los mismos
--                  partidos (un bucle de reproceso) o son partidos distintos (procesamiento normal).
-- CUÁNDO USARLA    Cuando el bot de Telegram manda demasiados avisos o no se ve un mensaje importante.
-- CÓMO LEER EL RESULTADO
--   PASO 1  CSV procesados por hora (≈ mensajes de Telegram por hora).
--   PASO 2  por partido (carpeta de C:\data\basketball-ready\current\<match_id>): cuántos CSV y cuántas
--           veces se procesó el mismo tipo; un partido con más CSV que tipos distintos se está reprocesando.
-- QUÉ HACER DESPUÉS  Si son partidos distintos, es procesamiento normal (hay que silenciar el aviso o
--                  separar el pronóstico). Si se repiten, hay un bucle que arreglar.
-- RESULTADO EL 2026-11-21  (ver el informe de la sesión)
-- =============================================================================

-- PASO 1 · CSV procesados por hora en las últimas 6 horas.
SELECT to_char(date_trunc('hour', finished_at AT TIME ZONE 'Europe/Madrid'), 'DD/MM HH24:00') AS hora,
       COUNT(*) AS csv
FROM public.batch_launch_request
WHERE status IN ('COMPLETED', 'FAILED') AND finished_at > now() - interval '6 hours'
GROUP BY 1 ORDER BY 1;

-- PASO 2 · Por partido: CSV procesados, tipos distintos y primera/última hora.
SELECT split_part(file_path, '\current\', 2) AS ruta, COUNT(*) AS csv
FROM public.batch_launch_request
WHERE status IN ('COMPLETED', 'FAILED') AND finished_at > now() - interval '6 hours'
GROUP BY 1 ORDER BY 1 LIMIT 0;  -- (solo valida la sintaxis; el agrupado real va debajo)

SELECT split_part(split_part(file_path, '\current\', 2), '\', 1) AS partido,
       COUNT(*) AS csv,
       COUNT(DISTINCT batch_type) AS tipos,
       to_char(MIN(finished_at AT TIME ZONE 'Europe/Madrid'), 'HH24:MI') AS primero,
       to_char(MAX(finished_at AT TIME ZONE 'Europe/Madrid'), 'HH24:MI') AS ultimo
FROM public.batch_launch_request
WHERE status IN ('COMPLETED', 'FAILED') AND finished_at > now() - interval '6 hours'
GROUP BY 1
ORDER BY MIN(finished_at);
