-- =============================================================================
-- CSV TERMINADOS EN EL LAUNCHER DESDE UNA FECHA (VIGILANTE DE TELEGRAM)
-- =============================================================================
-- Fecha:     2026-11-17 12:40
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_1240_csv-terminados-para-telegram.sql
--
-- PARA QUÉ SIRVE   el vigilante scripts\py\monitor\telegram_csv.py la lanza cada 10 s
--                  para saber qué CSV ha terminado de procesar el launcher
--                  (public.batch_launch_request, una fila por CSV enviado) desde el
--                  último que ya mandó al bot, y enviarlos en orden.
-- CUÁNDO USARLA    para ver a mano qué CSV debería haber recibido el bot desde una hora.
-- CÓMO LEER EL RESULTADO  un JSON con una entrada por CSV: request_id, batch_type,
--                  status (COMPLETED bien, FAILED mal), exit_code, file_path (el CSV
--                  que se adjunta), finished_at (marca de agua del vigilante) y error.
-- QUÉ HACER DESPUÉS       si hay filas que el bot no recibió, revisar el log del vigilante
--                  y el estado DATA_DIR\state\telegram_csv.json.
-- RESULTADO EL 2026-11-17 el vigilante la ejecuta con la marca de agua real; aquí,
--                  como ejemplo, desde hace una hora.
-- =============================================================================

-- PASO 1 · CSV terminados después de la marca de agua (el vigilante pone su fecha), máximo 50.
SELECT COALESCE(json_agg(to_jsonb(t) ORDER BY t.finished_at), '[]'::json)::text
FROM (
    SELECT request_id, batch_type, status, exit_code, file_path,
           to_char(finished_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS finished_at,
           left(error, 300) AS error
    FROM public.batch_launch_request
    WHERE status IN ('COMPLETED', 'FAILED')
      AND finished_at > now() - interval '1 hour'
    ORDER BY finished_at
    LIMIT 50
) t;
