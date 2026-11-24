-- =============================================================================
-- CUOTAS: CONSULTA DEL PROJECTOR (PostgresMatchReader.ODDS_SQL)
-- =============================================================================
-- Fecha:     2026-11-24 11:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1130_cuotas-lector-projector.sql
--
-- PARA QUÉ SIRVE   Probar con un partido real la consulta con la que el projector lee
--                  las cuotas: por mercado, solo el CSV más reciente; orden por mercado,
--                  casa y línea.
-- CUÁNDO USARLA    Si cambia la consulta del projector o la pestaña Cuotas sale rara.
-- CÓMO LEER EL RESULTADO  Paso 1: filas por mercado que proyectaría para 0fAJZWz1.
--                  Paso 2: las 12 primeras filas en el orden del projector.
-- QUÉ HACER DESPUÉS       Desplegar el projector y mirar matches.odds en Mongo.
-- RESULTADO EL 2026-11-24 · 0fAJZWz1: asian_handicap 3 filas, home_away 1, over_under 3 (1 casa, bet365.nl; sin 1x2), ordenadas por mercado y línea.
-- =============================================================================

-- PASO 1 · Filas por mercado para 0fAJZWz1 (último CSV de cada mercado).
WITH files AS (
    SELECT match_id, market_type, source_file,
           row_number() OVER (
               PARTITION BY market_type
               ORDER BY coalesce(substring(source_file from '_([0-9]{14})_'), '') DESC, source_file DESC
           ) AS n
    FROM (SELECT DISTINCT match_id, market_type, source_file FROM odds.odds WHERE match_id = '0fAJZWz1') f
)
SELECT o.market_type, count(*) AS filas, count(DISTINCT o.bookmaker) AS casas
FROM odds.odds o
JOIN files f ON f.match_id = o.match_id AND f.market_type = o.market_type
            AND f.source_file = o.source_file AND f.n = 1
GROUP BY o.market_type
ORDER BY o.market_type;

-- PASO 2 · Consulta del projector tal cual (con el partido fijo).
WITH files AS (
    SELECT match_id, market_type, source_file,
           row_number() OVER (
               PARTITION BY market_type
               ORDER BY coalesce(substring(source_file from '_([0-9]{14})_'), '') DESC, source_file DESC
           ) AS n
    FROM (SELECT DISTINCT match_id, market_type, source_file FROM odds.odds WHERE match_id = '0fAJZWz1') f
)
SELECT o.market_type, o.period, o.bookmaker, o.line, o.home_line, o.away_line,
       o.home_odds, o.draw_odds, o.away_odds, o.over_odds, o.under_odds
FROM odds.odds o
JOIN files f ON f.match_id = o.match_id AND f.market_type = o.market_type
            AND f.source_file = o.source_file AND f.n = 1
ORDER BY o.market_type, o.bookmaker,
         CASE WHEN o.line ~ '^[+-]?[0-9]+([.][0-9]+)?$' THEN o.line::numeric END NULLS FIRST,
         CASE WHEN o.home_line ~ '^[+-]?[0-9]+([.][0-9]+)?$' THEN o.home_line::numeric END NULLS FIRST
LIMIT 12;
