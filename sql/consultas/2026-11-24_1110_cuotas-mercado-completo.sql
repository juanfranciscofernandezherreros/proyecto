-- =============================================================================
-- CUOTAS: NOMBRE COMPLETO DEL MERCADO EN odds.odds.market_type
-- =============================================================================
-- Fecha:     2026-11-24 11:10
-- Tipo:      ESCRITURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1110_cuotas-mercado-completo.sql
--
-- PARA QUÉ SIRVE   El extra-importer sacaba el mercado cortando el nombre del fichero
--                  en el primer «_»: ODDS_HOME_AWAY_… quedaba «home», ODDS_OVER_UNDER_…
--                  «over» y ODDS_ASIAN_HANDICAP_… «asian». El importador ya está
--                  corregido (ExtraCsvImporter.marketType); esto arregla lo ya cargado.
-- CUÁNDO USARLA    Una sola vez, tras cargar con el importador antiguo.
-- CÓMO LEER EL RESULTADO  Paso 1 (antes): filas por mercado. Paso 2: UPDATE n por
--                  mercado. Paso 3 (después): solo 1x2, asian_handicap, home_away y
--                  over_under, con las mismas filas que antes.
-- QUÉ HACER DESPUÉS       Proyectar las cuotas con el projector.
-- QUÉ TOCA          Solo filas de odds.odds con market_type 'home', 'over' o 'asian'.
--                  La clave primaria es (match_id, market_type, row_hash): no puede
--                  chocar porque aún no hay filas con los nombres nuevos (Paso 1).
-- RESULTADO EL 2026-11-24 · UPDATE 2232 (home_away), 19203 (over_under), 15472 (asian_handicap); 1x2 sin cambios (1156). Total igual antes y después: 38063 filas.
-- =============================================================================

-- PASO 1 · Antes: filas por mercado.
SELECT market_type, count(*) AS filas FROM odds.odds GROUP BY market_type ORDER BY market_type;

-- PASO 2 · Corregir el mercado (en una transacción).
BEGIN;
UPDATE odds.odds SET market_type = 'home_away'      WHERE market_type = 'home';
UPDATE odds.odds SET market_type = 'over_under'     WHERE market_type = 'over';
UPDATE odds.odds SET market_type = 'asian_handicap' WHERE market_type = 'asian';
COMMIT;

-- PASO 3 · Después: mismas filas con el nombre completo.
SELECT market_type, count(*) AS filas FROM odds.odds GROUP BY market_type ORDER BY market_type;
