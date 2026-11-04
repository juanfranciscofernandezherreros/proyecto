-- =============================================================================
-- LIMPIAR TEAM_STATS DESCUADRADAS QUE QUEDAN TRAS RE-EXTRAER
-- =============================================================================
-- Fecha:     2026-11-04 11:35
-- Tipo:      LECTURA + ESCRITURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-04_1135_team-stats-duplicadas-tras-reextraer.sql
--
-- PARA QUÉ SIRVE
--   Al re-extraer un partido con el scraper de team-stats ya corregido, el batch de
--   importacion hace UPSERT por (match_id, period, category, metric). Las filas nuevas
--   traen la metrica real ("Field goal %", "3-point field goal %"...), pero las viejas
--   descuadradas tenian la metrica puesta como un VALOR ("(38/72)", "51.4%", "33.3%"...),
--   asi que no coinciden con ninguna fila nueva y NO se sobrescriben: quedan duplicadas.
--   Esto borra esas filas obsoletas (metrica que no es una etiqueta real de estadistica),
--   dejando solo las correctas recien importadas.
--
-- CUÁNDO USARLA
--   Despues de re-extraer un partido que ya estaba importado con el scraper antiguo, cuando
--   en team_stats aparezcan a la vez filas correctas y filas con metrica numerica/porcentaje.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1 lista las filas obsoletas (su metrica es un valor, no una estadistica). PASO 3
--   debe devolver solo metricas reales (sin "(.../...)" ni "%").
--
-- QUÉ HACER DESPUÉS
--   El projector re-proyecta a Mongo en su siguiente ciclo (~60 s) y la web muestra solo las
--   filas correctas.
--
-- RESULTADO EL 2026-11-04  PASO 1 listo 30 filas obsoletas; PASO 2 borro 30 (DELETE 30);
--   PASO 3 dejo solo 12 metricas reales. Estadisticas del partido ya alineadas.

-- Etiquetas reales de estadistica de equipo (lo demas es basura del descuadre antiguo).
-- PASO 1 · LECTURA · Filas obsoletas del partido (metrica que no es una etiqueta valida).
SELECT period, category, metric, home_value, away_value
FROM team_stats.team_stats
WHERE match_id = 'A7ObYlS9'
  AND metric NOT IN (
    'Field goal %', '2-point field goal %', '3-point field goal %', 'Free throw %',
    'Offensive rebounds', 'Defensive rebounds', 'Total rebounds',
    'Assists', 'Blocks', 'Personal fouls', 'Steals', 'Turnovers'
  )
ORDER BY period, id;

-- PASO 2 · ESCRITURA · Borra esas filas obsoletas. Solo toca el partido indicado y solo las
--   filas cuya metrica no es una estadistica real; las correctas no se tocan.
DELETE FROM team_stats.team_stats
WHERE match_id = 'A7ObYlS9'
  AND metric NOT IN (
    'Field goal %', '2-point field goal %', '3-point field goal %', 'Free throw %',
    'Offensive rebounds', 'Defensive rebounds', 'Total rebounds',
    'Assists', 'Blocks', 'Personal fouls', 'Steals', 'Turnovers'
  );

-- PASO 3 · LECTURA · Comprobacion: deben quedar solo metricas reales.
SELECT DISTINCT metric
FROM team_stats.team_stats
WHERE match_id = 'A7ObYlS9'
ORDER BY metric;
