-- =============================================================================
-- CUOTAS (ODDS) Y H2H TRAS LA CARGA DE LOS CSV EXISTENTES
-- =============================================================================
-- Fecha:     2026-11-24 11:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1100_cuotas-estado.sql
--
-- PARA QUÉ SIRVE   Comprobar lo que cargó el extra-importer de los ODDS_*.csv (4
--                  mercados: home_away, 1x2, over_under, asian_handicap) y de los
--                  H2H_*.csv, y ver la forma de los datos antes de proyectarlos.
-- CUÁNDO USARLA    Tras cargar CSV de cuotas o H2H.
-- CÓMO LEER EL RESULTADO  Paso 1: H2H (esperado 394 ficheros, 276 partidos).
--                  Paso 2: por mercado, filas, ficheros, partidos y casas de apuestas.
--                  Paso 3: periodos que aparecen (FT including OT, 1st half…).
--                  Paso 4: cuotas de un partido (0fAJZWz1) para ver la forma.
-- QUÉ HACER DESPUÉS       Proyectar a Mongo (projector) y revisar la pestaña Cuotas.
-- RESULTADO EL 2026-11-24 · H2H 3924 filas, 292 ficheros, 217 partidos (de 394 CSV: 79 solo cabecera y 23 copias idénticas). Cuotas antes del arreglo del mercado: 1x2 1156 filas/186 partidos, asian 15472/274, home 2232/272, over 19203/274; un único periodo «FT including OT»; 13-17 casas por mercado.
-- =============================================================================

-- PASO 1 · H2H cargado.
SELECT count(*) AS filas, count(DISTINCT source_file) AS ficheros, count(DISTINCT match_id) AS partidos
FROM h2h.h2h;

-- PASO 2 · Cuotas por mercado.
SELECT market_type, count(*) AS filas, count(DISTINCT source_file) AS ficheros,
       count(DISTINCT match_id) AS partidos, count(DISTINCT bookmaker) AS casas
FROM odds.odds
GROUP BY market_type
ORDER BY market_type;

-- PASO 3 · Periodos por mercado.
SELECT market_type, period, count(*) AS filas
FROM odds.odds
GROUP BY market_type, period
ORDER BY market_type, filas DESC;

-- PASO 4 · Forma de los datos de un partido.
SELECT market_type, period, bookmaker, line, home_line, away_line,
       home_odds, draw_odds, away_odds, over_odds, under_odds, source_file
FROM odds.odds
WHERE match_id = '0fAJZWz1'
ORDER BY market_type, period, bookmaker, line, home_line
LIMIT 25;
