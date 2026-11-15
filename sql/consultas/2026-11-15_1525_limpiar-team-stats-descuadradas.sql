-- =============================================================================
-- LIMPIAR LAS TEAM_STATS DESCUADRADAS TRAS REEXTRAER LOS PARTIDOS
-- =============================================================================
-- Fecha:     2026-11-15 15:25
-- Tipo:      LECTURA + ESCRITURA (DELETE en el PASO 3)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-15_1525_limpiar-team-stats-descuadradas.sql
--
-- PARA QUÉ SIRVE
--   El scraper antiguo de TEAM_STATS guardaba las filas de tiro desplazadas: la métrica
--   era un valor ("50.0%", "(2/2)") y la etiqueta real acababa en home_value o
--   away_value. Son 7480 filas en 262 partidos que no tienen copia buena (ver
--   2026-11-15_1510_team-stats-descuadradas-sin-copia-buena.sql). El arreglo tiene dos
--   partes: reextraer TEAM_STATS de esos partidos con el scraper corregido (el batch
--   hace UPSERT por match_id+period+category+metric, así que añade las filas buenas y
--   corrige las de etiqueta válida con valor malo) y borrar después las filas cuya
--   métrica es un valor, que el UPSERT no pisa.
--
-- CUÁNDO USARLA
--   Cuando el control 15 de la auditoría (2026-11-15_1445_auditoria-datos.sql) dé
--   afectados. PASO 1 para sacar la lista a reextraer; PASOS 2–4 tras reextraer.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  partidos a reextraer, con su liga (la carpeta de CSV sale de ahí).
--   PASO 2  cuántos partidos afectados tienen ya "Field goal %" (reextraídos) y cuántos
--           no. Solo los primeros entran en el borrado.
--   PASO 3  DELETE n: filas descuadradas borradas.
--   PASO 4  lo que queda descuadrado: debe ser 0, o solo los partidos que no se
--           pudieron reextraer.
--
-- QUÉ HACER DESPUÉS
--   El projector reproyecta a Mongo en su siguiente ciclo (~60 s). Volver a lanzar la
--   auditoría (skill auditar-datos) y comprobar el control 15.
--
-- RESULTADO EL 2026-11-15
--   (se rellena al ejecutar)
-- =============================================================================

-- PASO 1 · LECTURA · Partidos con filas descuadradas y su liga, para reextraerlos.
SELECT DISTINCT t.match_id, r.country, r.competition
FROM team_stats.team_stats t
JOIN results.results r USING (match_id)
WHERE t.metric ~ '^\(?[0-9]+(\.[0-9]+)?[%/]'
ORDER BY r.country, r.competition, t.match_id;

-- PASO 2 · LECTURA · De los partidos afectados, cuántos están ya reextraídos.
SELECT count(*) AS partidos_afectados,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM team_stats.team_stats b
                                      WHERE b.match_id = m.match_id AND b.metric = 'Field goal %')) AS reextraidos
FROM (SELECT DISTINCT match_id FROM team_stats.team_stats
      WHERE metric ~ '^\(?[0-9]+(\.[0-9]+)?[%/]') m;

-- PASO 3 · ESCRITURA · Borra las filas cuya métrica es un valor.
--   Qué filas toca: solo las de métrica "número seguido de % o /" (nunca una etiqueta
--   real: "2-point field goal %" no encaja en el patrón).
--   Protección: solo en partidos que ya tienen la fila buena "Field goal %", es decir,
--   reextraídos con el scraper corregido. Un partido sin reextraer no se toca.
--   Además borra los rebotes guardados con categoría 'Scoring': el scraper antiguo
--   los metía ahí y el corregido los guarda en 'Rebounds', así que tras reextraer
--   quedan duplicados (visto en la prueba con 0bG6tX1t). Los buenos no se tocan.
--   Cómo comprobar: PASO 4.
DELETE FROM team_stats.team_stats t
WHERE (t.metric ~ '^\(?[0-9]+(\.[0-9]+)?[%/]'
       OR (t.category = 'Scoring'
           AND t.metric IN ('Offensive rebounds', 'Defensive rebounds', 'Total rebounds')))
  AND EXISTS (SELECT 1 FROM team_stats.team_stats b
              WHERE b.match_id = t.match_id AND b.metric = 'Field goal %');

-- PASO 4 · LECTURA · Comprobación: filas y partidos que siguen descuadrados.
SELECT count(*) AS filas_restantes, count(DISTINCT match_id) AS partidos_restantes
FROM team_stats.team_stats
WHERE metric ~ '^\(?[0-9]+(\.[0-9]+)?[%/]'
   OR (category = 'Scoring'
       AND metric IN ('Offensive rebounds', 'Defensive rebounds', 'Total rebounds'));
