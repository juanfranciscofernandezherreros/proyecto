-- =============================================================================
-- PLAYER_STATS FALLIDO EN BUCLE PARA UN PARTIDO (h81tlrkd)
-- =============================================================================
-- Fecha:     2026-11-17 15:50
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_1550_player-stats-fallido-h81tlrkd.sql
--
-- PARA QUÉ SIRVE   El partido NBA h81tlrkd (Spurs vs Thunder) sale en cada pasada de
--                  `basket pendientes` y su carga de PLAYER_STATS termina FAILED en el
--                  batch stats-player (10/11, 14/11, 16/11 y dos veces el 17/11). Lee de
--                  public.batch_launch_request el error que guardó el launcher.
-- CUÁNDO USARLA    Cuando un partido falle una y otra vez en el mismo dataset; cambiar
--                  el match_id del LIKE.
-- CÓMO LEER EL RESULTADO  batch_type y status de cada envío; `error` trae el motivo
--                  (columna que falta, tipo inválido, clave duplicada...). Si todos
--                  repiten el mismo error, es un problema del CSV o del batch, no de red.
-- QUÉ HACER DESPUÉS       Si el error es del contenido del CSV, mirar ese fichero en
--                  C:\data\basketball-ready\current\h81tlrkd; si es del batch, revisar
--                  stats-player. Reintentar con `basket reextraer h81tlrkd`.
-- RESULTADO EL 2026-11-17  (se completa tras ejecutarla)
-- =============================================================================

-- PASO 1 · Últimos envíos del partido y su error (el texto recortado a 300 caracteres).
SELECT created_at, batch_type, status, left(error, 300) AS error
FROM public.batch_launch_request
WHERE file_path LIKE '%h81tlrkd%'
ORDER BY created_at DESC
LIMIT 10;

-- PASO 2 · Cuántas veces se ha reintentado y cuándo terminó el último intento. El launcher
-- reencola los FAILED con el mismo request_id (hash del CSV), así que created_at no cambia:
-- attempts y finished_at dicen si de verdad se reintenta.
SELECT request_id, status, attempts, exit_code, started_at, finished_at
FROM public.batch_launch_request
WHERE file_path LIKE '%h81tlrkd%' AND batch_type = 'stats-player';
