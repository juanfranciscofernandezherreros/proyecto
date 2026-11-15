-- =============================================================================
-- ÚLTIMOS RESULTADOS AGREGADOS A results.results
-- =============================================================================
-- Fecha:     2026-11-15 20:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-15_2000_ultimos-resultados-agregados.sql
--
-- PARA QUÉ SIRVE   Ver de un vistazo qué marcadores han entrado en results.results
--                  tras una extracción: por liga, cuál es el último partido con
--                  resultado y cuándo se cargó; y la lista de los 40 partidos más
--                  recientes con su marcador. La usa la skill `ultimos-resultados`.
-- CUÁNDO USARLA    Después de `basket resultados ALL` o `basket resultados <liga>`,
--                  o cuando se pregunte "¿qué resultados han entrado?" o "¿está el
--                  partido de ayer?".
-- CÓMO LEER EL RESULTADO
--                  La tabla no tiene fecha de alta, solo updated_at, y cada recarga
--                  reescribe updated_at de TODAS las filas de la liga (paso 1: una
--                  sola hora concentra casi todas las filas). Por eso "último
--                  agregado" se ordena por la fecha del partido (event_datetime) y
--                  updated_at solo dice cuándo se cargó la liga por última vez.
--                  Paso 2: `ultimo_partido` antiguo en una liga en temporada, o
--                  `ultima_carga` de otro día, indican que esa liga no está al día.
--                  Paso 3: partidos sin marcador (home_score nulo) no deberían salir.
--                  Horas en Europe/Madrid.
-- QUÉ HACER DESPUÉS
--                  Liga atrasada → skill `extraer-resultados` (una liga) o
--                  `resultados-todas-las-ligas`. Para saber cuántos partidos
--                  jugados siguen sin resultado → `basket comprobar`.
-- RESULTADO EL 2026-11-15 20:05   ver al final del fichero.
-- =============================================================================

-- PASO 1 · Cómo se reparte updated_at. Si casi todas las filas caen en la misma
-- hora, updated_at no distingue las filas nuevas de las recargadas.
SELECT to_char(date_trunc('hour', updated_at AT TIME ZONE 'Europe/Madrid'), 'DD/MM HH24:00') AS hora_carga,
       count(*)                                        AS filas,
       count(DISTINCT country || '/' || competition)   AS ligas
FROM results.results
GROUP BY 1
ORDER BY min(updated_at) DESC
LIMIT 12;

-- PASO 2 · Resumen por liga: total de resultados, último partido con resultado,
-- cuántos son de los últimos 3 días y cuándo se cargó la liga por última vez.
SELECT country || '/' || competition                                                AS liga,
       count(*)                                                                     AS resultados,
       to_char(max(event_datetime) AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI')   AS ultimo_partido,
       count(*) FILTER (WHERE event_datetime >= now() - interval '3 days')          AS ultimos_3_dias,
       to_char(max(updated_at) AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI')       AS ultima_carga
FROM results.results
GROUP BY country, competition
ORDER BY max(event_datetime) DESC NULLS LAST;

-- PASO 3 · Los 40 partidos más recientes con resultado, del más nuevo al más antiguo.
SELECT to_char(event_datetime AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI')  AS partido,
       country || '/' || competition                                          AS liga,
       home_team || ' ' || home_score || '-' || away_score || ' ' || away_team AS marcador,
       to_char(updated_at AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI')      AS cargado,
       match_id
FROM results.results
ORDER BY event_datetime DESC NULLS LAST, updated_at DESC
LIMIT 40;

-- RESULTADO EL 2026-11-15 20:05 (justo después de `basket resultados ALL`)
--   Paso 1: una sola fila, 15/11 19:00, 847 filas, 11 ligas → updated_at no
--           distingue las filas nuevas.
--   Paso 2: 11 ligas, todas con ultima_carga el 15/11 entre 19:51 y 19:59. Último
--           partido del 15/11 en 8 ligas; Israel 14/11, Euroliga 13/11, Serbia 31/05.
--   Paso 3: 40 filas; la más reciente, Venezia 88-81 Maxima Roma (15/11 18:00).
