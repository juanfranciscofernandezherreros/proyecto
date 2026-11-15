-- =============================================================================
-- LOS 50 ÚLTIMOS RESULTADOS AGREGADOS A results.results
-- =============================================================================
-- Fecha:     2026-11-15 20:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-15_2030_ultimos-50-resultados-agregados.sql
--
-- PARA QUÉ SIRVE   Listar los 50 últimos resultados de results.results, con su
--                  marcador, para ver de un vistazo qué ha entrado. Es la consulta
--                  que lanza la skill `ultimos-resultados`. Sustituye como salida
--                  de la skill a 2026-11-15_2000_ultimos-resultados-agregados.sql,
--                  que daba tres tablas (reparto de updated_at, resumen por liga y
--                  40 partidos) cuando lo que se quiere es solo la lista.
-- CUÁNDO USARLA    Después de una extracción de resultados, o cuando se pregunte
--                  qué resultados han entrado o cuáles son los últimos.
-- CÓMO LEER EL RESULTADO
--                  Una fila por partido, del más reciente al más antiguo. La tabla
--                  no tiene fecha de alta y cada recarga reescribe updated_at de
--                  toda la liga, así que "último" es por fecha del partido
--                  (event_datetime); `cargado` (updated_at) solo dice cuándo se
--                  recargó esa fila por última vez. Horas en Europe/Madrid.
-- QUÉ HACER DESPUÉS
--                  Si falta un partido ya jugado → skill `extraer-resultados` o
--                  `resultados-todas-las-ligas`. Para el resumen por liga, la
--                  consulta 2026-11-15_2000 o `basket comprobar`.
-- RESULTADO EL 2026-11-15 20:30   ver al final del fichero.
-- =============================================================================

-- PASO 1 · Los 50 partidos más recientes con resultado.
SELECT to_char(event_datetime AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI')  AS partido,
       country || '/' || competition                                          AS liga,
       home_team || ' ' || home_score || '-' || away_score || ' ' || away_team AS marcador,
       to_char(updated_at AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI')      AS cargado,
       match_id
FROM results.results
ORDER BY event_datetime DESC NULLS LAST, updated_at DESC
LIMIT 50;

-- RESULTADO EL 2026-11-15 20:30
--   50 filas, del 15/11 18:00 (Venezia 88-81 Maxima Roma) al 14/11 13:30
--   (Tofas 75-61 Trabzonspor): 26 partidos del 15/11 y 24 del 14/11.
