-- =============================================================================
-- NOMBRES DE EQUIPO CORRUPTOS CON INSIGNIAS DE FLASHSCORE
-- =============================================================================
-- Fecha:     2026-11-03 10:30
-- Tipo:      LECTURA (no modifica nada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1030_nombres-equipo-con-insignias.sql
--
-- PARA QUÉ SIRVE
--   En las páginas de resultados, Flashscore mete dentro del elemento de cada equipo
--   insignias de texto como "Winner: X" o "Advancing to next round: X". El scraper antiguo
--   las pegaba al nombre ("Spartak SuboticaWinner: Spartak Subotica"). Esta consulta busca
--   nombres de equipo que contengan esos textos en results.results.
--
-- CUÁNDO USARLA
--   · Después de importar RESULTS, sobre todo de fases eliminatorias (playoffs, copa).
--   · Si en la web aparece un equipo con un nombre raro o duplicado.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  afectados debería ser 0.
--   PASO 2  lista los partidos con el nombre roto, por si hay que revisarlos uno a uno.
--
-- QUÉ HACER DESPUÉS
--   Si aparece alguno, volver a extraer los RESULTS de esa liga con el scraper corregido
--   (KAN-343): 1_EJECUTAR\LIGAS_ORQUESTAR.bat <LIGA> results 10. El importador sustituye
--   home_team / away_team por el valor nuevo.
--
-- RESULTADO EL 2026-11-03
--   Tras la reextracción de las 11 ligas con el scraper corregido (10:24): 0 afectados.
--   Ejemplo arreglado: 2wmXA36F "FMP Beograd - Spartak Subotica" (antes
--   "Spartak SuboticaWinner: Spartak Subotica").
-- =============================================================================


-- PASO 1 · Cuántos partidos tienen alguna insignia pegada al nombre de un equipo.
SELECT count(*) AS afectados
FROM results.results
WHERE home_team ~* '(winner|advancing to next round|vencedor):'
   OR away_team ~* '(winner|advancing to next round|vencedor):';


-- PASO 2 · Detalle de los partidos afectados.
SELECT match_id, country, competition, home_team, away_team
FROM results.results
WHERE home_team ~* '(winner|advancing to next round|vencedor):'
   OR away_team ~* '(winner|advancing to next round|vencedor):'
ORDER BY country, competition, match_id;
